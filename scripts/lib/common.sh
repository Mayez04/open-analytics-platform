#!/usr/bin/env bash
# Shared helpers for platform deployment scripts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_ok()    { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Required command not found: $1"
    exit 1
  fi
}

load_env() {
  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    log_error ".env file not found. Copy .env.example to .env first:"
    log_error "  cp .env.example .env"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
}

ensure_runtime_dirs() {
  mkdir -p "$ROOT_DIR/data/minio" "$ROOT_DIR/data/postgres" "$ROOT_DIR/airflow/logs"
}

compose() {
  docker compose "$@"
}

get_compose_network() {
  local network
  network="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' lakehouse_minio 2>/dev/null | head -1 || true)"
  if [[ -z "$network" ]]; then
    log_error "Could not detect Docker network. Is MinIO running?"
    log_error "Run: docker compose up -d"
    exit 1
  fi
  printf '%s' "$network"
}

wait_for_postgres() {
  local timeout="${1:-120}"
  local elapsed=0

  log_info "Waiting for PostgreSQL..."
  while [[ "$elapsed" -lt "$timeout" ]]; do
    if compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
      log_ok "PostgreSQL is ready"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  log_error "PostgreSQL did not become ready within ${timeout}s"
  return 1
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local timeout="${3:-180}"
  local elapsed=0

  log_info "Waiting for ${name}..."
  while [[ "$elapsed" -lt "$timeout" ]]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      log_ok "${name} is ready"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  log_error "${name} did not become ready at ${url} within ${timeout}s"
  return 1
}

wait_for_airflow_dag() {
  local dag_id="$1"
  local timeout="${2:-120}"
  local elapsed=0

  log_info "Waiting for Airflow DAG '${dag_id}' to be registered..."
  while [[ "$elapsed" -lt "$timeout" ]]; do
    if compose exec -T airflow airflow dags list 2>/dev/null | grep -q "${dag_id}"; then
      log_ok "DAG '${dag_id}' is available"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  log_error "DAG '${dag_id}' was not registered within ${timeout}s"
  return 1
}

run_dag_test() {
  local dag_id="$1"
  local execution_date="${2:-2024-01-01}"

  log_info "Running pipeline: ${dag_id}"
  if compose exec -T airflow airflow dags test "${dag_id}" "${execution_date}"; then
    log_ok "Pipeline '${dag_id}' completed"
    return 0
  fi

  log_error "Pipeline '${dag_id}' failed"
  return 1
}

print_service_summary() {
  cat <<EOF

Platform is ready.

  MinIO Console : http://localhost:${MINIO_CONSOLE_PORT:-9001}
  Airflow       : http://localhost:${AIRFLOW_WEB_PORT:-8081}
  Superset      : http://localhost:${SUPERSET_PORT:-8088}
  PostgreSQL    : localhost:${POSTGRES_PORT:-5432}

Credentials are defined in .env (never commit this file).

Demo data:
  - MinIO bucket: ${MINIO_BUCKET:-bronze}
  - PostgreSQL tables loaded via Airflow pipelines

Next steps:
  - Open Superset and explore the Analytics Warehouse connection
  - See docs/demo-guide.md for a guided demo script

EOF
}
