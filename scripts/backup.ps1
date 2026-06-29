#Requires -Version 5.1
<#
.SYNOPSIS
  Create a full platform backup.

.EXAMPLE
  .\scripts\backup.ps1
  .\scripts\backup.ps1 -Label pre-demo -Archive
#>
param(
    [string]$OutputDir = "",
    [string]$Label = "",
    [switch]$Archive
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Load-Env {
    $envFile = Join-Path $RootDir ".env"
    if (-not (Test-Path $envFile)) {
        Write-Err ".env file not found. Copy .env.example to .env first."
        exit 1
    }
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            Set-Item -Path "env:$($parts[0].Trim())" -Value $parts[1].Trim()
        }
    }
}

Load-Env

if (-not $OutputDir) { $OutputDir = Join-Path $RootDir "backups" }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "platform-$timestamp"
if ($Label) { $backupName = "$backupName-$Label" }
$backupPath = Join-Path $OutputDir $backupName

New-Item -ItemType Directory -Force -Path "$backupPath/postgres", "$backupPath/minio", "$backupPath/superset", "$backupPath/config" | Out-Null

Write-Info "Creating backup at $backupPath"

$pgRunning = docker compose ps --status running postgres 2>$null
if (-not $pgRunning) {
    Write-Err "PostgreSQL container is not running. Start the platform first: docker compose up -d"
    exit 1
}

$dbName = $env:POSTGRES_DB
$dumpFile = Join-Path $backupPath "postgres/$dbName.sql.gz"

Write-Info "Backing up PostgreSQL database '$dbName'..."
docker compose exec -T postgres pg_dump -U $env:POSTGRES_USER --no-owner --no-acl --clean --if-exists $dbName |
    & gzip > $dumpFile
Write-Ok "PostgreSQL dump saved"

$network = docker inspect -f "{{range `$k, `$v := .NetworkSettings.Networks}}{{$k}}{{end}}" lakehouse_minio 2>$null
if (-not $network) {
    Write-Err "Could not detect Docker network. Is MinIO running?"
    exit 1
}

Write-Info "Backing up MinIO bucket '$($env:MINIO_BUCKET)'..."
docker run --rm `
    --network $network `
    -v "${backupPath}/minio:/backup" `
    -e "MINIO_ROOT_USER=$($env:MINIO_ROOT_USER)" `
    -e "MINIO_ROOT_PASSWORD=$($env:MINIO_ROOT_PASSWORD)" `
    -e "MINIO_BUCKET=$($env:MINIO_BUCKET)" `
    minio/mc sh -c @"
mc alias set local http://minio:9000 `$MINIO_ROOT_USER `$MINIO_ROOT_PASSWORD
if mc ls local/`$MINIO_BUCKET >/dev/null 2>&1; then
  mc mirror --quiet local/`$MINIO_BUCKET /backup/`$MINIO_BUCKET
else
  mkdir -p /backup/`$MINIO_BUCKET
fi
"@
Write-Ok "MinIO bucket mirrored"

$supersetRunning = docker compose ps --status running superset 2>$null
if ($supersetRunning) {
    Write-Info "Backing up Superset metadata..."
    docker cp lakehouse_superset:/app/superset_home/superset.db "$backupPath/superset/superset.db" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Superset metadata saved"
    } else {
        Write-Warn "Superset metadata database not found — skipping"
    }
} else {
    Write-Warn "Superset is not running — skipping Superset metadata backup"
}

Write-Info "Backing up platform configuration..."
if (Test-Path ".env") { Copy-Item ".env" "$backupPath/config/.env" }
if (Test-Path ".env.example") { Copy-Item ".env.example" "$backupPath/config/.env.example" }
Copy-Item "docker-compose.yml" "$backupPath/config/docker-compose.yml"
if (Test-Path "airflow/dags/config") {
    Copy-Item -Recurse "airflow/dags/config" "$backupPath/config/airflow-dags-config"
}
Write-Ok "Configuration files saved"

$manifest = @{
    platform = "open-analytics-platform"
    created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    deployment_mode = $env:DEPLOYMENT_MODE
    postgres = @{ database = $dbName; dump_file = "postgres/$dbName.sql.gz" }
    minio = @{ bucket = $env:MINIO_BUCKET; path = "minio/$($env:MINIO_BUCKET)" }
    superset = @{ metadata_file = "superset/superset.db" }
    config = @{ path = "config" }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content "$backupPath/manifest.json"

if ($Archive) {
    $archivePath = "$backupPath.tar.gz"
    Write-Info "Creating archive $archivePath..."
    tar -czf $archivePath -C $OutputDir $backupName
    Write-Ok "Archive created: $archivePath"
}

Write-Ok "Backup complete: $backupPath"
Write-Host "`nRestore with:`n  .\scripts\restore.ps1 `"$backupPath`"`n"
