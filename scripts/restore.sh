#!/usr/bin/env bash
# Restore platform data from a backup created by backup.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

BACKUP_PATH=""
DB_NAME=""
RESTORE_POSTGRES=true
RESTORE_MINIO=true
RESTORE_SUPERSET=true
RESTORE_CONFIG=false
FORCE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") BACKUP_PATH [OPTIONS]

Restore the Open Analytics Platform from a backup directory or .tar.gz archive.

Arguments:
  BACKUP_PATH        Path to backup folder or .tar.gz archive

Options:
  --db-name NAME     Target PostgreSQL database name (default: from .env or manifest)
  --postgres-only    Restore PostgreSQL only
  --minio-only       Restore MinIO only
  --superset-only    Restore Superset metadata only
  --config-only      Restore configuration files only
  --skip-postgres    Skip PostgreSQL restore
  --skip-minio       Skip MinIO restore
  --skip-superset    Skip Superset metadata restore
  --with-config      Also restore configuration files (.env, DAG configs)
  --force            Skip confirmation prompt
  -h, --help         Show this help message

Examples:
  ./scripts/restore.sh backups/platform-20250614-120000
  ./scripts/restore.sh backups/platform-20250614-120000.tar.gz --db-name analytics_warehouse
  ./scripts/restore.sh backups/platform-20250614-120000 --postgres-only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-name) DB_NAME="$2"; shift 2 ;;
    --postgres-only)
      RESTORE_MINIO=false; RESTORE_SUPERSET=false; RESTORE_CONFIG=false; shift ;;
    --minio-only)
      RESTORE_POSTGRES=false; RESTORE_SUPERSET=false; RESTORE_CONFIG=false; shift ;;
    --superset-only)
      RESTORE_POSTGRES=false; RESTORE_MINIO=false; RESTORE_CONFIG=false; shift ;;
    --config-only)
      RESTORE_POSTGRES=false; RESTORE_MINIO=false; RESTORE_SUPERSET=false
      RESTORE_CONFIG=true; shift ;;
    --skip-postgres) RESTORE_POSTGRES=false; shift ;;
    --skip-minio) RESTORE_MINIO=false; shift ;;
    --skip-superset) RESTORE_SUPERSET=false; shift ;;
    --with-config) RESTORE_CONFIG=true; shift ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$BACKUP_PATH" ]]; then
        BACKUP_PATH="$1"
      else
        log_error "Unexpected argument: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$BACKUP_PATH" ]]; then
  log_error "BACKUP_PATH is required"
  usage
  exit 1
fi

require_command docker
load_env

TEMP_DIR=""
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

resolve_backup_path() {
  local input="$1"

  if [[ ! -e "$input" ]]; then
    log_error "Backup path not found: $input"
    exit 1
  fi

  if [[ -f "$input" && "$input" == *.tar.gz ]]; then
    require_command tar
    TEMP_DIR="$(mktemp -d)"
    log_info "Extracting archive..."
    tar -xzf "$input" -C "$TEMP_DIR"
    local extracted
    extracted="$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -z "$extracted" ]]; then
      log_error "Archive does not contain a backup directory"
      exit 1
    fi
    printf '%s' "$extracted"
    return
  fi

  if [[ -d "$input" ]]; then
    printf '%s' "$(cd "$input" && pwd)"
    return
  fi

  log_error "Backup path must be a directory or .tar.gz file: $input"
  exit 1
}

BACKUP_ROOT="$(resolve_backup_path "$BACKUP_PATH")"

if [[ ! -f "${BACKUP_ROOT}/manifest.json" ]]; then
  log_error "Invalid backup: manifest.json not found in ${BACKUP_ROOT}"
  exit 1
fi

if [[ -z "$DB_NAME" ]]; then
  DB_NAME="${POSTGRES_DB:-analytics_warehouse}"
  if command -v python3 >/dev/null 2>&1; then
    DB_NAME="$(python3 -c "import json; print(json.load(open('${BACKUP_ROOT}/manifest.json'))['postgres']['database'])" 2>/dev/null || echo "$DB_NAME")"
  elif command -v python >/dev/null 2>&1; then
    DB_NAME="$(python -c "import json; print(json.load(open('${BACKUP_ROOT}/manifest.json'))['postgres']['database'])" 2>/dev/null || echo "$DB_NAME")"
  fi
fi

DUMP_FILE="${BACKUP_ROOT}/postgres/${DB_NAME}.sql.gz"
MINIO_BACKUP="${BACKUP_ROOT}/minio/${MINIO_BUCKET}"
SUPERSET_BACKUP="${BACKUP_ROOT}/superset/superset.db"

log_info "Restore source: ${BACKUP_ROOT}"
log_info "Target database: ${DB_NAME}"

if [[ "$FORCE" != "true" ]]; then
  printf '\033[1;33mWARNING:\033[0m This will overwrite existing data. Continue? [y/N] '
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warn "Restore cancelled"
    exit 0
  fi
fi

# --- PostgreSQL ---
if [[ "$RESTORE_POSTGRES" == "true" ]]; then
  if [[ ! -f "$DUMP_FILE" ]]; then
    log_error "PostgreSQL dump not found: ${DUMP_FILE}"
    exit 1
  fi

  if ! compose ps --status running postgres >/dev/null 2>&1; then
    log_error "PostgreSQL container is not running"
    exit 1
  fi

  wait_for_postgres 60

  log_info "Restoring PostgreSQL database '${DB_NAME}'..."
  gunzip -c "$DUMP_FILE" | compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1
  log_ok "PostgreSQL restore complete"
fi

# --- MinIO ---
if [[ "$RESTORE_MINIO" == "true" ]]; then
  if [[ ! -d "$MINIO_BACKUP" ]]; then
    log_warn "MinIO backup folder not found: ${MINIO_BACKUP} — skipping"
  else
    NETWORK="$(get_compose_network)"
    log_info "Restoring MinIO bucket '${MINIO_BUCKET}'..."
    docker run --rm \
      --network "$NETWORK" \
      -v "${MINIO_BACKUP}:/backup/${MINIO_BUCKET}:ro" \
      -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
      -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
      -e "MINIO_BUCKET=${MINIO_BUCKET}" \
      --entrypoint /bin/sh \
      minio/mc -c '
        mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
        mc mb "local/${MINIO_BUCKET}" --ignore-existing
        mc mirror --overwrite "/backup/${MINIO_BUCKET}" "local/${MINIO_BUCKET}"
      '
    log_ok "MinIO restore complete"
  fi
fi

# --- Superset ---
if [[ "$RESTORE_SUPERSET" == "true" ]]; then
  if [[ ! -f "$SUPERSET_BACKUP" ]]; then
    log_warn "Superset metadata not found: ${SUPERSET_BACKUP} — skipping"
  elif ! compose ps --status running superset >/dev/null 2>&1; then
    log_warn "Superset is not running — skipping Superset metadata restore"
  else
    log_info "Restoring Superset metadata..."
    compose stop superset
    docker cp "${SUPERSET_BACKUP}" "lakehouse_superset:/app/superset_home/superset.db"
    compose start superset
    log_ok "Superset metadata restored (container restarted)"
  fi
fi

# --- Configuration ---
if [[ "$RESTORE_CONFIG" == "true" ]]; then
  CONFIG_DIR="${BACKUP_ROOT}/config"
  if [[ ! -d "$CONFIG_DIR" ]]; then
    log_warn "Config backup not found — skipping"
  else
    log_info "Restoring configuration files..."
    if [[ -f "${CONFIG_DIR}/.env" ]]; then
      cp "${CONFIG_DIR}/.env" "${ROOT_DIR}/.env"
      log_ok "Restored .env (review before restarting services)"
    fi
    if [[ -d "${CONFIG_DIR}/airflow-dags-config" ]]; then
      mkdir -p "${ROOT_DIR}/airflow/dags/config"
      cp -r "${CONFIG_DIR}/airflow-dags-config/." "${ROOT_DIR}/airflow/dags/config/"
      log_ok "Restored Airflow DAG configs"
    fi
    if [[ -d "${CONFIG_DIR}/superset-config" ]]; then
      mkdir -p "${ROOT_DIR}/superset/config"
      cp -r "${CONFIG_DIR}/superset-config/." "${ROOT_DIR}/superset/config/" 2>/dev/null || true
    fi
    if [[ -d "${CONFIG_DIR}/superset-dashboards" ]]; then
      mkdir -p "${ROOT_DIR}/superset/dashboards"
      cp -r "${CONFIG_DIR}/superset-dashboards/." "${ROOT_DIR}/superset/dashboards/" 2>/dev/null || true
    fi
    log_ok "Configuration restore complete"
  fi
fi

log_ok "Restore finished"
log_info "Restart services if needed: docker compose restart"
