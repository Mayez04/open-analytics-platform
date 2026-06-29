# Documentation

Complete technical documentation for the **Open Analytics Platform**.

## Getting started

| Guide | Audience | Description |
|-------|----------|-------------|
| [Installation Guide](installation-guide.md) | New users | Install and first-run setup |
| [Configuration Guide](configuration.md) | Operators | Environment variables and deployment modes |
| [Demo Guide](demo-guide.md) | Presenters | Client demo walkthrough |

## Architecture and design

| Guide | Description |
|-------|-------------|
| [Architecture Overview](architecture.md) | Components, data flow, network topology, roadmap |
| [Repository Structure](repository-structure.md) | Folder layout and naming conventions |
| [Platform Overview](platform-overview.md) | Presentation-style overview for stakeholders |

## Day-to-day operations

| Guide | Description |
|-------|-------------|
| [Operations Guide](operations-guide.md) | Start/stop, pipelines, maintenance, health checks |
| [Backup and Restore Guide](backup-restore-guide.md) | Backup procedures and disaster recovery |
| [Troubleshooting Guide](troubleshooting-guide.md) | Common issues and fixes |

## Quick reference

### Install from scratch

```bash
git clone <repository-url>
cd open-analytics-platform
chmod +x scripts/*.sh
cp .env.example .env
docker compose up -d
./scripts/init-platform.sh
```

### Essential commands

| Task | Command |
|------|---------|
| Start platform | `docker compose up -d` |
| Stop platform | `docker compose down` |
| Initialize / load demo | `./scripts/init-platform.sh` |
| Reload demo data | `./scripts/load-demo-data.sh` |
| Create backup | `./scripts/backup.sh` |
| Restore backup | `./scripts/restore.sh backups/platform-...` |
| View logs | `docker compose logs -f <service>` |
| Full reset | `docker compose down -v && rm -rf data/` |

### Service URLs (defaults)

| Service | URL |
|---------|-----|
| MinIO Console | http://localhost:9001 |
| Airflow | http://localhost:8081 |
| Superset | http://localhost:8088 |
| PostgreSQL | localhost:5432 |

Credentials are defined in `.env`. See [configuration.md](configuration.md).

## Documentation map

```
docs/
├── README.md                  ← you are here
├── architecture.md            ← system design
├── platform-overview.md       ← stakeholder presentation
├── installation-guide.md      ← setup
├── configuration.md           ← .env reference
├── operations-guide.md        ← daily ops
├── backup-restore-guide.md    ← disaster recovery
├── troubleshooting-guide.md   ← problem solving
├── demo-guide.md              ← client demo script
└── repository-structure.md    ← codebase layout
```

## Phase coverage

| Work Package | Documentation |
|--------------|---------------|
| 4.1 Repository standardization | [repository-structure.md](repository-structure.md) |
| 4.2 Configuration management | [configuration.md](configuration.md) |
| 4.3 Automated deployment | [installation-guide.md](installation-guide.md), [demo-guide.md](demo-guide.md) |
| 4.4 Backup and restore | [backup-restore-guide.md](backup-restore-guide.md) |
| 4.5 Platform documentation | This index + all guides above |

