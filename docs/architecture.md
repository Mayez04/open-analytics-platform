# Architecture Overview

The Open Analytics Platform is a self-contained, open-source analytics stack designed to run on-premise or locally via Docker Compose. It follows a medallion-style data architecture and is built to be domain-agnostic, configurable, and client-ready.

## High-level architecture

```mermaid
flowchart TB
    subgraph Sources
        CSV[CSV files]
        JSON[JSON files]
        API[External APIs e.g. DHIS2]
    end

    subgraph Platform["Docker Compose — lakehouse_net"]
        MinIO["MinIO<br/>Bronze / Lake<br/>:9000 / :9001"]
        Airflow["Apache Airflow<br/>Orchestration<br/>:8081"]
        PG["PostgreSQL 15<br/>Warehouse + Airflow metadata<br/>:5432"]
        SS["Apache Superset<br/>Dashboards<br/>:8088"]
    end

    subgraph Users
        DE[Data Engineer]
        AN[Analyst]
    end

    CSV --> MinIO
    JSON --> MinIO
    API --> Airflow
    Airflow --> MinIO
    Airflow --> PG
    MinIO --> Airflow
    PG --> SS
    DE --> Airflow
    DE --> MinIO
    AN --> SS
```

## Component reference

| Component | Layer | Role | Technology | Default port |
|-----------|-------|------|------------|--------------|
| **MinIO** | Bronze (lake) | Raw file storage — CSV, JSON, Parquet | S3-compatible object storage | 9000 (API), 9001 (console) |
| **PostgreSQL** | Gold (warehouse) | Structured analytics tables, dimensions, facts | PostgreSQL 15 | 5432 |
| **Airflow** | Orchestration | ETL scheduling, pipeline execution, metadata | Apache Airflow 2.7 | 8081 |
| **Superset** | Presentation | Charts, dashboards, SQL exploration | Apache Superset | 8088 |

Airflow metadata (DAG runs, connections, variables) is stored in the same PostgreSQL instance as the analytics data.

## Data flow

### Medallion pattern

```mermaid
flowchart LR
    subgraph Bronze
        B1[Raw CSV]
        B2[Raw JSON]
        B3[API payloads]
    end

    subgraph Silver
        S1[Staging tables]
        S2[Cleaned records]
    end

    subgraph Gold
        G1[Dimension tables]
        G2[Fact tables]
        G3[Analytics views]
    end

    B1 --> S1
    B2 --> S1
    B3 --> S1
    S1 --> S2
    S2 --> G1
    S2 --> G2
    G1 --> G3
    G2 --> G3
```

### Pipeline flow (current)

1. **Ingest** — Raw files are uploaded to MinIO `bronze` bucket, or fetched by Airflow from external APIs (DHIS2).
2. **Stage** — Airflow DAGs read from MinIO and load into PostgreSQL staging tables.
3. **Transform** — Data is cleaned, deduplicated, and modeled into star schema (dimensions + facts).
4. **Serve** — Superset connects to PostgreSQL and exposes charts and dashboards to analysts.

```mermaid
sequenceDiagram
    participant User
    participant MinIO
    participant Airflow
    participant PostgreSQL
    participant Superset

    User->>MinIO: Upload raw file (or init script)
    User->>Airflow: Trigger DAG
    Airflow->>MinIO: Read bronze file
    Airflow->>PostgreSQL: Create schema / load staging
    Airflow->>PostgreSQL: Load dimensions & facts
    User->>Superset: Open dashboard
    Superset->>PostgreSQL: Query analytics tables
    Superset->>User: Render chart
```

## Network topology

All services run on a single Docker bridge network (`lakehouse_net`). Services reach each other by container/service name — not `localhost`.

```mermaid
flowchart LR
    subgraph Host["Host machine"]
        Browser[Browser / CLI]
    end

    subgraph Docker["lakehouse_net"]
        minio[minio :9000]
        postgres[postgres :5432]
        airflow[airflow :8080]
        superset[superset :8088]
    end

    Browser -->|"localhost:9001"| minio
    Browser -->|"localhost:8081"| airflow
    Browser -->|"localhost:8088"| superset
    Browser -->|"localhost:5432"| postgres
    airflow --> postgres
    airflow --> minio
    superset --> postgres
```

Internal connection examples:

| From | To | Host to use |
|------|----|-------------|
| Airflow DAG | PostgreSQL | `postgres:5432` |
| Airflow DAG | MinIO | `http://minio:9000` |
| Superset | PostgreSQL | `postgres:5432` |
| Host machine | PostgreSQL | `localhost:5432` |

## Configuration architecture

All secrets and ports are externalized to `.env`. Docker Compose injects variables into containers; Airflow DAGs read them via `lib/platform_config.py`.

```mermaid
flowchart TD
    ENV[".env file"]
    COMPOSE["docker-compose.yml"]
    MINIO_C[MinIO container]
    PG_C[PostgreSQL container]
    AF_C[Airflow container]
    SS_C[Superset container]
    DAGS["airflow/dags/*.py"]

    ENV --> COMPOSE
    COMPOSE --> MINIO_C
    COMPOSE --> PG_C
    COMPOSE --> AF_C
    COMPOSE --> SS_C
    ENV --> AF_C
    AF_C --> DAGS
```

See [configuration.md](configuration.md) for the full variable reference.

## Deployment scripts

```mermaid
flowchart TD
    INIT["init-platform.sh"]
    LOAD["load-demo-data.sh"]
    CONFIG["configure-superset.sh"]
    BACKUP["backup.sh"]
    RESTORE["restore.sh"]

    INIT --> LOAD
    INIT --> CONFIG
    BACKUP --> RESTORE
```

| Script | Purpose |
|--------|---------|
| `init-platform.sh` | Post-start initialization: wait for services, load demo, configure Superset |
| `load-demo-data.sh` | Upload sample files to MinIO and run ETL DAGs |
| `configure-superset.sh` | Register PostgreSQL connection in Superset |
| `backup.sh` | Snapshot PostgreSQL, MinIO, Superset metadata, and config |
| `restore.sh` | Restore from backup |

## Current pipelines

| DAG ID | Source | Target | Output |
|--------|--------|--------|--------|
| `csv_minio_to_postgres` | MinIO CSV | PostgreSQL | `raw_data` table |
| `json_to_star_schema` | MinIO JSON | PostgreSQL | Star schema (dims + facts) |
| `dhis2_to_star_schema` | DHIS2 API | MinIO → PostgreSQL | Star schema |

## Target architecture (Phases 5–6)

```mermaid
flowchart TB
    subgraph Phase5["Phase 5 — AI Assistant"]
        UI[Streamlit UI]
        API[FastAPI /ask]
        META[YAML Metadata]
        VALID[SQL Validation]
        LLM[LLM Provider]
    end

    subgraph Phase6["Phase 6 — Security"]
        KC[Keycloak OIDC]
        RBAC[Role-Based Access]
        POL[Data Access Policies]
        AUDIT[Audit Logs]
    end

    User --> KC
    KC --> UI
    KC --> SS[Superset]
    UI --> API
    API --> META
    API --> LLM
    API --> VALID
    VALID --> PG[(PostgreSQL)]
    API --> AUDIT
    RBAC --> API
    POL --> VALID
```

| Phase | Addition | Technology |
|-------|----------|------------|
| Phase 5 | Metadata-driven NL-to-SQL assistant | FastAPI, Streamlit, YAML metadata |
| Phase 5 | SQL validation and explainability | Python validation layer, audit tables |
| Phase 6 | Authentication | Keycloak, OpenID Connect |
| Phase 6 | Authorization | RBAC, row/table-level data policies |
| Phase 6 | Governance | Audit logs for queries, logins, exports |

## Design principles

1. **Domain-agnostic** — No hardcoded business logic; datasets and pipelines are configured externally.
2. **Reproducible** — Docker Compose + `.env` + init scripts = identical deployments.
3. **Metadata-driven AI** — The assistant (Phase 5) understands databases through YAML metadata, not model training.
4. **Security first** — SQL validation and access control before query execution (Phase 5–6).
5. **Operational readiness** — Backup/restore, documentation, and demo environment included from Phase 4.

## Technology stack summary

| Category | Technology |
|----------|------------|
| Analytics database | PostgreSQL 15 |
| Object storage | MinIO |
| Orchestration | Apache Airflow 2.7 |
| Business intelligence | Apache Superset |
| Containerization | Docker / Docker Compose |
| Configuration | Environment variables (`.env`) |
| AI assistant (planned) | FastAPI + Streamlit + LLM API |
| Identity (planned) | Keycloak (OIDC) |

## Related documentation

- [Repository Structure](repository-structure.md) — codebase layout
- [Configuration Guide](configuration.md) — environment variables
- [Installation Guide](installation-guide.md) — setup steps
- [Platform Overview](platform-overview.md) — stakeholder presentation
