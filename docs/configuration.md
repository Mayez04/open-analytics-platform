# Configuration Guide

All platform settings are managed through environment variables. No passwords or ports are hardcoded in source code.

## Quick setup

```bash
# Option A — use the default template
cp .env.example .env

# Option B — use a deployment preset
cp config/env/development.env.example .env    # local development
cp config/env/pilot.env.example .env          # client demo / pilot
```

On Windows (PowerShell):

```powershell
Copy-Item .env.example .env
# or
Copy-Item config/env/development.env.example .env
```

Then start the platform:

```bash
docker compose up -d
```

Docker Compose reads `.env` from the project root automatically.

## Deployment modes

| Mode | Preset file | Use case |
|------|-------------|----------|
| **development** | `config/env/development.env.example` | Local work, simple credentials, fast iteration |
| **pilot** | `config/env/pilot.env.example` | Client demos, stronger secrets, production-like settings |

Set `DEPLOYMENT_MODE` in `.env` to `development` or `pilot`. The value is informational for now; the actual behavior is driven by the credentials and ports you choose.

### Development mode

- Simple, memorable passwords (`admin`, `password123`)
- Default ports (5432, 8081, 8088, 9000/9001)
- Safe for local machines only

### Pilot mode

- Unique admin usernames per service
- All passwords set to `CHANGE_ME_*` placeholders — **replace before any demo**
- Generate a Fernet key for Airflow:

```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

## Variable reference

### Deployment

| Variable | Description | Default |
|----------|-------------|---------|
| `DEPLOYMENT_MODE` | `development` or `pilot` | `development` |

### PostgreSQL

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_USER` | Database user | `analytics_user` |
| `POSTGRES_PASSWORD` | Database password | — |
| `POSTGRES_DB` | Database name | `analytics_warehouse` |
| `POSTGRES_HOST` | Host inside Docker network | `postgres` |
| `POSTGRES_PORT` | Host port mapping | `5432` |
| `POSTGRES_INTERNAL_PORT` | Port inside Docker network | `5432` |

Connection string used by DAGs:

```
postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_INTERNAL_PORT}/${POSTGRES_DB}
```

### MinIO

| Variable | Description | Default |
|----------|-------------|---------|
| `MINIO_ROOT_USER` | Admin username | `admin` |
| `MINIO_ROOT_PASSWORD` | Admin password | — |
| `MINIO_ENDPOINT` | Internal Docker URL | `http://minio:9000` |
| `MINIO_API_PORT` | Host port for S3 API | `9000` |
| `MINIO_CONSOLE_PORT` | Host port for web console | `9001` |
| `MINIO_BUCKET` | Default bronze bucket name | `bronze` |

### Airflow

| Variable | Description | Default |
|----------|-------------|---------|
| `AIRFLOW_WEB_PORT` | Host port for web UI | `8081` |
| `AIRFLOW_ADMIN_USER` | Initial admin username | `admin` |
| `AIRFLOW_ADMIN_PASSWORD` | Initial admin password | — |
| `AIRFLOW_ADMIN_EMAIL` | Admin email | `admin@example.com` |
| `AIRFLOW_FERNET_KEY` | Encryption key for connections | — |
| `AIRFLOW_SECRET_KEY` | Webserver session secret | — |

### Superset

| Variable | Description | Default |
|----------|-------------|---------|
| `SUPERSET_PORT` | Host port for web UI | `8088` |
| `SUPERSET_ADMIN_USER` | Initial admin username | `admin` |
| `SUPERSET_ADMIN_PASSWORD` | Initial admin password | — |
| `SUPERSET_ADMIN_EMAIL` | Admin email | `admin@superset.com` |
| `SUPERSET_SECRET_KEY` | Application secret key | — |

### Keycloak (Phase 6)

| Variable | Description | Default |
|----------|-------------|---------|
| `KEYCLOAK_PORT` | Host port | `8080` |
| `KEYCLOAK_ADMIN_USER` | Admin username | `admin` |
| `KEYCLOAK_ADMIN_PASSWORD` | Admin password | — |

### AI Assistant (Phase 5)

| Variable | Description | Default |
|----------|-------------|---------|
| `LLM_PROVIDER` | Provider name (`openai`, `azure`, `anthropic`, `local`) | `openai` |
| `LLM_API_KEY` | API key for the provider | — |
| `LLM_MODEL` | Model identifier | `gpt-4o-mini` |

### DHIS2 pipeline (optional)

| Variable | Description | Default |
|----------|-------------|---------|
| `DHIS2_BASE_URL` | DHIS2 instance URL | play sandbox |
| `DHIS2_USERNAME` | API username | `admin` |
| `DHIS2_PASSWORD` | API password | — |

These override the values in `airflow/dags/config/dhis2_config.json`. Pipeline-specific settings (datasets, date ranges, schedule) remain in the JSON config file.

## How configuration flows

```
.env  ──▶  docker-compose.yml  ──▶  service containers
  │
  └──▶  Airflow container  ──▶  lib/platform_config.py  ──▶  DAGs
```

1. You edit `.env` (never committed — see `.gitignore`).
2. Docker Compose substitutes `${VAR}` in `docker-compose.yml` and passes variables into containers via `env_file: .env`.
3. Airflow DAGs read connection settings through `lib/platform_config.py`.

## Changing ports

If port `8081` is already in use, change only `.env`:

```env
AIRFLOW_WEB_PORT=8082
```

Then restart:

```bash
docker compose down
docker compose up -d
```

No source code changes needed.

## Security notes

- **Never commit `.env`** — it contains secrets. Only `.env.example` and preset templates are tracked.
- After changing PostgreSQL credentials in `.env`, existing data in `data/postgres/` was created with the old password. Either keep the same password or run a full reset (`docker compose down -v && rm -rf data/`).
- For pilot demos, replace every `CHANGE_ME_*` value in the pilot preset before starting.

## Related docs

- [Installation Guide](installation-guide.md)
- [Repository Structure](repository-structure.md)
