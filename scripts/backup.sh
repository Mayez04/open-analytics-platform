#!/usr/bin/env bash
# Create a full platform backup: PostgreSQL, MinIO, Superset metadata, and config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

OUTPUT_DIR="${ROOT_DIR}/backups"
LABEL=""
CREATE_ARCHIVE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create a backup of the Open Analytics Platform.

Backs up:
  - PostgreSQL (analytics database + Airflow metadata)
  - MinIO buckets
  - Superset metadata database
  - Platform configuration files

Options:
  --output-dir DIR   Backup root directory (default: ./backups)
  --label NAME       Optional label appended to backup folder name
  --archive          Also create a .tar.gz archive of the backup folder
  -h, --help         Show this help message

Example:
  ./scripts/backup.sh
  ./scripts/backup.sh --label pre-demo --archive
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --archive) CREATE_ARCHIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_command docker
load_env

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="platform-${TIMESTAMP}"
if [[ -n "$LABEL" ]]; then
  BACKUP_NAME="${BACKUP_NAME}-${LABEL}"
fi
BACKUP_PATH="${OUTPUT_DIR}/${BACKUP_NAME}"

mkdir -p "${BACKUP_PATH}/postgres" "${BACKUP_PATH}/minio" "${BACKUP_PATH}/superset" "${BACKUP_PATH}/config"

log_info "Creating backup at ${BACKUP_PATH}"

if ! compose ps --status running postgres >/dev/null 2>&1; then
  log_error "PostgreSQL container is not running. Start the platform first:"
  log_error "  docker compose up -d"
  exit 1
fi

wait_for_postgres 60

# --- PostgreSQL (analytics + Airflow metadata share this database) ---
DB_NAME="${POSTGRES_DB:-analytics_warehouse}"
DUMP_FILE="${BACKUP_PATH}/postgres/${DB_NAME}.sql.gz"

log_info "Backing up PostgreSQL database '${DB_NAME}'..."
compose exec -T postgres pg_dump \
  -U "${POSTGRES_USER}" \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  "${DB_NAME}" | gzip > "${DUMP_FILE}"
log_ok "PostgreSQL dump saved to postgres/${DB_NAME}.sql.gz"

# --- MinIO ---
NETWORK="$(get_compose_network)"
log_info "Backing up MinIO bucket '${MINIO_BUCKET}'..."
docker run --rm \
  --network "$NETWORK" \
  -v "${BACKUP_PATH}/minio:/backup" \
  -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
  -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
  -e "MINIO_BUCKET=${MINIO_BUCKET}" \
  --entrypoint /bin/sh \
  minio/mc -c '
    mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
    if mc ls "local/${MINIO_BUCKET}" >/dev/null 2>&1; then
      mc mirror --quiet "local/${MINIO_BUCKET}" "/backup/${MINIO_BUCKET}"
    else
      mkdir -p "/backup/${MINIO_BUCKET}"
      echo "Bucket ${MINIO_BUCKET} is empty or missing — created empty backup folder"
    fi
  '
log_ok "MinIO bucket mirrored to minio/${MINIO_BUCKET}/"

# --- Superset metadata ---
log_info "Backing up Superset metadata..."
if compose ps --status running superset >/dev/null 2>&1; then
  if docker cp "lakehouse_superset:/app/superset_home/superset.db" "${BACKUP_PATH}/superset/superset.db" 2>/dev/null; then
    log_ok "Superset metadata saved to superset/superset.db"
  else
    log_warn "Superset metadata database not found — skipping"
  fi
else
  log_warn "Superset is not running — skipping Superset metadata backup"
fi

# --- Platform configuration ---
log_info "Backing up platform configuration..."
[[ -f "${ROOT_DIR}/.env" ]] && cp "${ROOT_DIR}/.env" "${BACKUP_PATH}/config/.env"
[[ -f "${ROOT_DIR}/.env.example" ]] && cp "${ROOT_DIR}/.env.example" "${BACKUP_PATH}/config/.env.example"
cp "${ROOT_DIR}/docker-compose.yml" "${BACKUP_PATH}/config/docker-compose.yml"

if [[ -d "${ROOT_DIR}/airflow/dags/config" ]]; then
  mkdir -p "${BACKUP_PATH}/config/airflow-dags-config"
  cp -r "${ROOT_DIR}/airflow/dags/config/." "${BACKUP_PATH}/config/airflow-dags-config/"
fi

if [[ -d "${ROOT_DIR}/superset/config" ]]; then
  mkdir -p "${BACKUP_PATH}/config/superset-config"
  find "${ROOT_DIR}/superset/config" -type f ! -name '.gitkeep' -exec cp {} "${BACKUP_PATH}/config/superset-config/" \; 2>/dev/null || true
fi

if [[ -d "${ROOT_DIR}/superset/dashboards" ]]; then
  mkdir -p "${BACKUP_PATH}/config/superset-dashboards"
  find "${ROOT_DIR}/superset/dashboards" -type f ! -name '.gitkeep' -exec cp {} "${BACKUP_PATH}/config/superset-dashboards/" \; 2>/dev/null || true
fi

log_ok "Configuration files saved to config/"

# --- Manifest ---
cat > "${BACKUP_PATH}/manifest.json" <<EOF
{
  "platform": "open-analytics-platform",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployment_mode": "${DEPLOYMENT_MODE:-unknown}",
  "postgres": {
    "database": "${DB_NAME}",
    "dump_file": "postgres/${DB_NAME}.sql.gz"
  },
  "minio": {
    "bucket": "${MINIO_BUCKET}",
    "path": "minio/${MINIO_BUCKET}"
  },
  "superset": {
    "metadata_file": "superset/superset.db"
  },
  "config": {
    "path": "config"
  }
}
EOF

if [[ "$CREATE_ARCHIVE" == "true" ]]; then
  require_command tar
  ARCHIVE_PATH="${OUTPUT_DIR}/${BACKUP_NAME}.tar.gz"
  log_info "Creating archive ${ARCHIVE_PATH}..."
  tar -czf "${ARCHIVE_PATH}" -C "${OUTPUT_DIR}" "${BACKUP_NAME}"
  log_ok "Archive created: ${ARCHIVE_PATH}"
fi

log_ok "Backup complete: ${BACKUP_PATH}"
printf '\nRestore with:\n  ./scripts/restore.sh "%s"\n\n' "${BACKUP_PATH}"
