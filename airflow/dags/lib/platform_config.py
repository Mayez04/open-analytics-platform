"""Read platform connection settings from environment variables."""

import os
from typing import Optional


def _require(name: str, default: Optional[str] = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_platform_config() -> dict:
    user = _require("POSTGRES_USER", "analytics_user")
    password = _require("POSTGRES_PASSWORD", "analytics_password")
    db = _require("POSTGRES_DB", "analytics_warehouse")
    host = _require("POSTGRES_HOST", "postgres")
    port = _require("POSTGRES_INTERNAL_PORT", "5432")

    return {
        "pg_conn": f"postgresql://{user}:{password}@{host}:{port}/{db}",
        "minio_endpoint": _require("MINIO_ENDPOINT", "http://minio:9000"),
        "minio_access_key": _require("MINIO_ROOT_USER", "admin"),
        "minio_secret_key": _require("MINIO_ROOT_PASSWORD", "password123"),
        "minio_bucket": _require("MINIO_BUCKET", "bronze"),
    }
