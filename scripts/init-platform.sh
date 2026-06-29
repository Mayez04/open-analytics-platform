#!/usr/bin/env bash
# Initialize the Open Analytics Platform after docker compose up -d.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

SKIP_DEMO=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Initialize the platform: create runtime directories, wait for services,
load demo data, and configure Superset.

Run this after:
  cp .env.example .env
  docker compose up -d

Options:
  --skip-demo   Skip demo data upload and pipeline execution
  -h, --help    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-demo) SKIP_DEMO=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_command docker
require_command curl
load_env

log_info "Initializing Open Analytics Platform (mode: ${DEPLOYMENT_MODE:-development})"

ensure_runtime_dirs
log_ok "Runtime directories ready"

if ! compose ps --status running --services 2>/dev/null | grep -q .; then
  log_error "No running containers found. Start the platform first:"
  log_error "  docker compose up -d"
  exit 1
fi

wait_for_postgres 180
wait_for_http "MinIO" "http://localhost:${MINIO_API_PORT:-9000}/minio/health/live" 120
wait_for_http "Airflow" "http://localhost:${AIRFLOW_WEB_PORT:-8081}/health" 240
wait_for_http "Superset" "http://localhost:${SUPERSET_PORT:-8088}/login/" 240

if [[ "$SKIP_DEMO" != "true" ]]; then
  bash "$SCRIPT_DIR/load-demo-data.sh"
else
  log_warn "Skipping demo data load (--skip-demo)"
fi

log_info "Configuring Superset database connection..."
if bash "$SCRIPT_DIR/configure-superset.sh"; then
  log_ok "Superset configured"
else
  log_warn "Superset auto-configuration skipped or failed — connect manually (see docs/installation-guide.md)"
fi

log_ok "Platform initialization complete"
print_service_summary
