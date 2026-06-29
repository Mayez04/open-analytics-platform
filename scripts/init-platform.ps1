#Requires -Version 5.1
<#
.SYNOPSIS
  Initialize the Open Analytics Platform after docker compose up -d.

.EXAMPLE
  .\scripts\init-platform.ps1
  .\scripts\init-platform.ps1 -SkipDemo
#>
param(
    [switch]$SkipDemo
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

function Wait-ForPostgres {
    param([int]$Timeout = 180)
    Write-Info "Waiting for PostgreSQL..."
    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        docker compose exec -T postgres pg_isready -U $env:POSTGRES_USER -d $env:POSTGRES_DB 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "PostgreSQL is ready"
            return
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    throw "PostgreSQL did not become ready within ${Timeout}s"
}

function Wait-ForHttp {
    param([string]$Name, [string]$Url, [int]$Timeout = 180)
    Write-Info "Waiting for $Name..."
    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -lt 500) {
                Write-Ok "$Name is ready"
                return
            }
        } catch {}
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    throw "$Name did not become ready at $Url within ${Timeout}s"
}

Load-Env

Write-Info "Initializing Open Analytics Platform (mode: $($env:DEPLOYMENT_MODE))"

New-Item -ItemType Directory -Force -Path "data/minio", "data/postgres", "airflow/logs" | Out-Null
Write-Ok "Runtime directories ready"

$running = docker compose ps --status running --services 2>$null
if (-not $running) {
    Write-Err "No running containers found. Start the platform first: docker compose up -d"
    exit 1
}

Wait-ForPostgres
Wait-ForHttp "MinIO" "http://localhost:$($env:MINIO_API_PORT)/minio/health/live"
Wait-ForHttp "Airflow" "http://localhost:$($env:AIRFLOW_WEB_PORT)/health" 240
Wait-ForHttp "Superset" "http://localhost:$($env:SUPERSET_PORT)/login/" 240

if (-not $SkipDemo) {
    & "$PSScriptRoot\load-demo-data.ps1"
} else {
    Write-Warn "Skipping demo data load (-SkipDemo)"
}

Write-Info "Configuring Superset database connection..."
try {
    & "$PSScriptRoot\configure-superset.ps1"
    Write-Ok "Superset configured"
} catch {
    Write-Warn "Superset auto-configuration failed — connect manually (see docs/installation-guide.md)"
}

Write-Ok "Platform initialization complete"
Write-Host @"

Platform is ready.

  MinIO Console : http://localhost:$($env:MINIO_CONSOLE_PORT)
  Airflow       : http://localhost:$($env:AIRFLOW_WEB_PORT)
  Superset      : http://localhost:$($env:SUPERSET_PORT)
  PostgreSQL    : localhost:$($env:POSTGRES_PORT)

Credentials are defined in .env (never commit this file).

See docs/demo-guide.md for a guided demo script.

"@
