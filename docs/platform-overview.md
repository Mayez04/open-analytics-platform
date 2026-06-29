# Platform Overview

> Presentation-style overview of the Open Analytics Platform.  
> Use this document for internal reviews, client pilots, or stakeholder meetings.

---

## Slide 1 — Title

**Open Analytics Platform**

A reusable, open-source analytics foundation for on-premise and low-resource environments.

- Self-contained Docker deployment
- End-to-end data pipeline: ingest → transform → visualize
- AI-assisted analytics layer (roadmap)
- Built for SolidLines client pilots

---

## Slide 2 — The problem

Organizations need analytics capabilities without:

- Expensive cloud lock-in
- Complex multi-vendor integrations
- Domain-specific tools that don't transfer between clients

**Goal:** A generic, reusable platform that can be adapted to any analytical database and client environment.

---

## Slide 3 — What we built

A complete analytics stack running on a single machine:

| Component | Purpose |
|-----------|---------|
| **MinIO** | Data lake — raw file storage |
| **PostgreSQL** | Data warehouse — structured analytics |
| **Airflow** | Pipeline orchestration — automated ETL |
| **Superset** | Business intelligence — dashboards and charts |

All services run in Docker. No cloud account required.

---

## Slide 4 — Architecture (current)

```
  Raw Data          Orchestration         Warehouse          Visualization
 ┌─────────┐       ┌───────────┐       ┌───────────┐       ┌───────────┐
 │  MinIO  │──────▶│  Airflow  │──────▶│ PostgreSQL│◀──────│ Superset  │
 │ (Lake)  │       │   (ETL)   │       │(Analytics)│       │ (Charts)  │
 └─────────┘       └───────────┘       └───────────┘       └───────────┘
```

**Medallion pattern:** Bronze (raw) → Silver (staging) → Gold (star schema)

---

## Slide 5 — Data flow example

1. Upload `life_expectancy.csv` to MinIO
2. Airflow DAG reads the file and loads it into PostgreSQL
3. Analyst opens Superset and builds a chart from `raw_data`
4. Another pipeline transforms DHIS2 JSON into a full star schema

**One command to set it all up:**

```bash
docker compose up -d && ./scripts/init-platform.sh
```

---

## Slide 6 — Key features (Phase 4)

| Feature | Status |
|---------|--------|
| Standardized repository structure | Done |
| Externalized configuration (`.env`) | Done |
| Automated deployment scripts | Done |
| Backup and restore | Done |
| Complete documentation | Done |
| Demo environment with sample data | Done |

Development and pilot deployment modes supported.

---

## Slide 7 — Operational readiness

**A new technical user can:**

1. Clone the repository
2. Copy `.env.example` to `.env`
3. Run `docker compose up -d`
4. Run `./scripts/init-platform.sh`
5. Access all four services with demo data loaded

**Backup before any demo:**

```bash
./scripts/backup.sh --label pre-demo
```

---

## Slide 8 — AI Assistant (Phase 5 roadmap)

Users ask questions in natural language:

> "Show total sales by month in 2025"

The assistant:

1. Reads **metadata** describing the database (tables, columns, synonyms)
2. Generates SQL via an LLM
3. **Validates** the SQL (SELECT only, approved tables, row limits)
4. Applies **access control** filters
5. Executes on PostgreSQL (read-only)
6. Returns data, chart, and explanation

**Principle:** Metadata-driven, not domain-specific.

---

## Slide 9 — Security and governance (Phase 6 roadmap)

| Capability | Description |
|------------|-------------|
| **Keycloak** | Single sign-on, OIDC, future Entra/Google integration |
| **RBAC** | Admin, Data Engineer, Analyst, Viewer roles |
| **Data policies** | Row/table-level access enforced in AI queries |
| **Audit logs** | Every question, SQL query, and export tracked |

The AI assistant will **never bypass permissions**.

---

## Slide 10 — Demo script (live)

| Step | Action | Time |
|------|--------|------|
| 1 | Show MinIO bronze bucket with raw files | 3 min |
| 2 | Show Airflow DAG runs (ETL success) | 5 min |
| 3 | Query PostgreSQL star schema | 3 min |
| 4 | Build a chart in Superset | 5 min |
| 5 | Tease AI assistant (Phase 5) | 2 min |

Full script: [demo-guide.md](demo-guide.md)

---

## Slide 11 — Technology choices

| Need | Choice | Why |
|------|--------|-----|
| Warehouse | PostgreSQL | Universal, low-resource, SQL-standard |
| Lake | MinIO | S3-compatible, runs locally |
| Orchestration | Airflow | Industry standard, Python DAGs |
| BI | Superset | Open-source, PostgreSQL-native |
| Containers | Docker Compose | Simple, reproducible, no K8s overhead |
| AI backend | FastAPI | Fast, async, easy LLM integration |
| Identity | Keycloak | OIDC, enterprise SSO ready |

---

## Slide 12 — What's out of scope (for now)

Deferred to future phases:

- Apache Spark / Trino / Iceberg
- Kubernetes deployment
- Terraform automation
- Prometheus / Grafana monitoring
- Multi-tenant SaaS

Focus: stable core platform + AI assistant + security.

---

## Slide 13 — Success criteria

The platform is successful when a new user can:

- [x] Deploy using provided documentation
- [x] Load sample analytical datasets
- [x] View data in Superset
- [ ] Authenticate via Keycloak *(Phase 6)*
- [ ] Ask analytical questions via AI assistant *(Phase 5)*
- [x] Backup and restore the platform
- [x] Review audit-ready documentation

---

## Slide 14 — Next steps

| Timeline | Deliverable |
|----------|-------------|
| Phase 4 (now) | Productized platform — **complete** |
| Phase 5 | Metadata-driven AI analytics assistant |
| Phase 6 | Keycloak auth, RBAC, data policies, audit |
| Future | Spark, Trino, K8s, enterprise monitoring |

**Immediate action:** Use the platform for internal demos and client pilots.

---

## Slide 15 — Resources

| Resource | Location |
|----------|----------|
| Repository | `open-analytics-platform/` |
| Documentation | [docs/README.md](README.md) |
| Installation | [installation-guide.md](installation-guide.md) |
| Demo script | [demo-guide.md](demo-guide.md) |
| Architecture | [architecture.md](architecture.md) |

**Contact:** SolidLines analytics team

---

*Open Analytics Platform — Phase 4 complete. Built for reuse, security, and AI-assisted decision support.*
