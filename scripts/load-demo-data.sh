#!/usr/bin/env bash
# Upload sample datasets to MinIO and optionally run ETL pipelines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

SKIP_PIPELINES=false
PIPELINES_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Upload sample data to MinIO and run demo ETL pipelines.

Options:
  --skip-pipelines   Upload files to MinIO only (do not run Airflow DAGs)
  --pipelines-only   Run Airflow DAGs only (assume MinIO already has files)
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pipelines) SKIP_PIPELINES=true; shift ;;
    --pipelines-only) PIPELINES_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_command docker
load_env

SAMPLE_DIR="$ROOT_DIR/postgres/sample_data"
NETWORK="$(get_compose_network)"

if [[ "$PIPELINES_ONLY" != "true" ]]; then
  for file in life_expectancy.csv dhis2_data_values.json; do
    if [[ ! -f "$SAMPLE_DIR/$file" ]]; then
      log_error "Missing sample file: $SAMPLE_DIR/$file"
      exit 1
    fi
  done

  log_info "Creating MinIO bucket '${MINIO_BUCKET}' and uploading sample files..."
  docker run --rm \
    --network "$NETWORK" \
    -v "${SAMPLE_DIR}:/data:ro" \
    -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
    -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
    -e "MINIO_BUCKET=${MINIO_BUCKET}" \
    --entrypoint /bin/sh \
    minio/mc -c '
      mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
      mc mb "local/${MINIO_BUCKET}" --ignore-existing
      mc cp /data/life_expectancy.csv "local/${MINIO_BUCKET}/life_expectancy.csv"
      mc cp /data/dhis2_data_values.json "local/${MINIO_BUCKET}/dhis2_data_values.json"
    '
  log_ok "Sample files uploaded to MinIO bucket '${MINIO_BUCKET}'"
fi

if [[ "$SKIP_PIPELINES" == "true" ]]; then
  log_warn "Skipping Airflow pipelines (--skip-pipelines)"
  exit 0
fi

wait_for_postgres 120
wait_for_airflow_dag "csv_minio_to_postgres" 180
wait_for_airflow_dag "json_lakehouse_to_star_schema" 180

run_dag_test "csv_minio_to_postgres"
run_dag_test "json_lakehouse_to_star_schema"

log_ok "Demo data load complete"
