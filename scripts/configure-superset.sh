#!/usr/bin/env bash
# Register the PostgreSQL analytics database in Superset (idempotent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_env

DATABASE_URI="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
DATABASE_NAME="Analytics Warehouse"

compose exec -T superset python - <<PY
import os

uri = "${DATABASE_URI}"
name = "${DATABASE_NAME}"

from superset.app import create_app

app = create_app()
with app.app_context():
    from superset.extensions import db
    from superset.models.core import Database

    existing = db.session.query(Database).filter_by(database_name=name).one_or_none()
    if existing:
        print(f"Database connection already exists: {name}")
    else:
        database = Database(database_name=name, sqlalchemy_uri=uri)
        db.session.add(database)
        db.session.commit()
        print(f"Created database connection: {name}")
PY
