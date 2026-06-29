#Requires -Version 5.1
param(
    [switch]$SkipPipelines,
    [switch]$PipelinesOnly
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

$SampleDir = Join-Path $RootDir "postgres\sample_data"
$network = docker inspect -f "{{range `$k, `$v := .NetworkSettings.Networks}}{{$k}}{{end}}" lakehouse_minio 2>$null
if (-not $network) {
    Write-Err "Could not detect Docker network. Is MinIO running?"
    exit 1
}

if (-not $PipelinesOnly) {
    foreach ($file in @("life_expectancy.csv", "dhis2_data_values.json")) {
        if (-not (Test-Path (Join-Path $SampleDir $file))) {
            Write-Err "Missing sample file: $SampleDir\$file"
            exit 1
        }
    }

    Write-Info "Creating MinIO bucket '$($env:MINIO_BUCKET)' and uploading sample files..."
    docker run --rm `
        --network $network `
        -v "${SampleDir}:/data:ro" `
        -e "MINIO_ROOT_USER=$($env:MINIO_ROOT_USER)" `
        -e "MINIO_ROOT_PASSWORD=$($env:MINIO_ROOT_PASSWORD)" `
        -e "MINIO_BUCKET=$($env:MINIO_BUCKET)" `
        minio/mc sh -c @"
mc alias set local http://minio:9000 `$MINIO_ROOT_USER `$MINIO_ROOT_PASSWORD
mc mb local/`$MINIO_BUCKET --ignore-existing
mc cp /data/life_expectancy.csv local/`$MINIO_BUCKET/life_expectancy.csv
mc cp /data/dhis2_data_values.json local/`$MINIO_BUCKET/dhis2_data_values.json
"@
    Write-Ok "Sample files uploaded to MinIO bucket '$($env:MINIO_BUCKET)'"
}

if ($SkipPipelines) {
    Write-Warn "Skipping Airflow pipelines (-SkipPipelines)"
    exit 0
}

# Wait for postgres
Write-Info "Waiting for PostgreSQL..."
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    docker compose exec -T postgres pg_isready -U $env:POSTGRES_USER -d $env:POSTGRES_DB 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw "PostgreSQL not ready" }

foreach ($dag in @("csv_minio_to_postgres", "json_to_star_schema")) {
    Write-Info "Waiting for Airflow DAG '$dag'..."
    for ($i = 0; $i -lt 60; $i++) {
        $list = docker compose exec -T airflow airflow dags list 2>$null
        if ($list -match $dag) { break }
        Start-Sleep -Seconds 3
    }

    Write-Info "Running pipeline: $dag"
    docker compose exec -T airflow airflow dags test $dag 2024-01-01
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Pipeline '$dag' failed"
        exit 1
    }
    Write-Ok "Pipeline '$dag' completed"
}

Write-Ok "Demo data load complete"
