#Requires -Version 5.1
<#
.SYNOPSIS
  Restore platform data from a backup.

.EXAMPLE
  .\scripts\restore.ps1 backups\platform-20250614-120000
  .\scripts\restore.ps1 backups\platform-20250614-120000.tar.gz -DbName analytics_warehouse -Force
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BackupPath,

    [string]$DbName = "",
    [switch]$PostgresOnly,
    [switch]$MinioOnly,
    [switch]$SupersetOnly,
    [switch]$ConfigOnly,
    [switch]$SkipPostgres,
    [switch]$SkipMinio,
    [switch]$SkipSuperset,
    [switch]$WithConfig,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Load-Env {
    Get-Content (Join-Path $RootDir ".env") | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            Set-Item -Path "env:$($parts[0].Trim())" -Value $parts[1].Trim()
        }
    }
}

Load-Env

$restorePostgres = -not $SkipPostgres
$restoreMinio = -not $SkipMinio
$restoreSuperset = -not $SkipSuperset
$restoreConfig = $WithConfig

if ($PostgresOnly) { $restoreMinio = $false; $restoreSuperset = $false; $restoreConfig = $false }
if ($MinioOnly) { $restorePostgres = $false; $restoreSuperset = $false; $restoreConfig = $false }
if ($SupersetOnly) { $restorePostgres = $false; $restoreMinio = $false; $restoreConfig = $false }
if ($ConfigOnly) { $restorePostgres = $false; $restoreMinio = $false; $restoreSuperset = $false; $restoreConfig = $true }

$backupRoot = $BackupPath
$tempDir = $null

if (-not (Test-Path $BackupPath)) {
    Write-Err "Backup path not found: $BackupPath"
    exit 1
}

if ($BackupPath -match '\.tar\.gz$') {
    $tempDir = Join-Path $env:TEMP ("oap-restore-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    Write-Info "Extracting archive..."
    tar -xzf $BackupPath -C $tempDir
    $backupRoot = Get-ChildItem $tempDir -Directory | Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path "$backupRoot/manifest.json")) {
    Write-Err "Invalid backup: manifest.json not found in $backupRoot"
    exit 1
}

if (-not $DbName) {
    $manifest = Get-Content "$backupRoot/manifest.json" | ConvertFrom-Json
    $DbName = if ($manifest.postgres.database) { $manifest.postgres.database } else { $env:POSTGRES_DB }
}

$dumpFile = Join-Path $backupRoot "postgres/$DbName.sql.gz"
$minioBackup = Join-Path $backupRoot "minio/$($env:MINIO_BUCKET)"
$supersetBackup = Join-Path $backupRoot "superset/superset.db"

Write-Info "Restore source: $backupRoot"
Write-Info "Target database: $DbName"

if (-not $Force) {
    $confirm = Read-Host "WARNING: This will overwrite existing data. Continue? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Warn "Restore cancelled"
        exit 0
    }
}

try {
    if ($restorePostgres) {
        if (-not (Test-Path $dumpFile)) {
            Write-Err "PostgreSQL dump not found: $dumpFile"
            exit 1
        }
        Write-Info "Restoring PostgreSQL database '$DbName'..."
        $inputStream = [System.IO.File]::OpenRead($dumpFile)
        try {
            $gzip = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
            $reader = New-Object System.IO.StreamReader($gzip)
            $sql = $reader.ReadToEnd()
            $reader.Close()
        } finally {
            $inputStream.Close()
        }
        $sql | docker compose exec -T postgres psql -U $env:POSTGRES_USER -d postgres -v ON_ERROR_STOP=1
        Write-Ok "PostgreSQL restore complete"
    }

    if ($restoreMinio) {
        if (-not (Test-Path $minioBackup)) {
            Write-Warn "MinIO backup folder not found — skipping"
        } else {
            $network = docker inspect -f "{{range `$k, `$v := .NetworkSettings.Networks}}{{$k}}{{end}}" lakehouse_minio
            Write-Info "Restoring MinIO bucket '$($env:MINIO_BUCKET)'..."
            docker run --rm `
                --network $network `
                -v "${minioBackup}:/backup/$($env:MINIO_BUCKET):ro" `
                -e "MINIO_ROOT_USER=$($env:MINIO_ROOT_USER)" `
                -e "MINIO_ROOT_PASSWORD=$($env:MINIO_ROOT_PASSWORD)" `
                -e "MINIO_BUCKET=$($env:MINIO_BUCKET)" `
                minio/mc sh -c @"
mc alias set local http://minio:9000 `$MINIO_ROOT_USER `$MINIO_ROOT_PASSWORD
mc mb local/`$MINIO_BUCKET --ignore-existing
mc mirror --overwrite /backup/`$MINIO_BUCKET local/`$MINIO_BUCKET
"@
            Write-Ok "MinIO restore complete"
        }
    }

    if ($restoreSuperset) {
        if (-not (Test-Path $supersetBackup)) {
            Write-Warn "Superset metadata not found — skipping"
        } else {
            Write-Info "Restoring Superset metadata..."
            docker compose stop superset
            docker cp $supersetBackup lakehouse_superset:/app/superset_home/superset.db
            docker compose start superset
            Write-Ok "Superset metadata restored"
        }
    }

    if ($restoreConfig) {
        $configDir = Join-Path $backupRoot "config"
        if (-not (Test-Path $configDir)) {
            Write-Warn "Config backup not found — skipping"
        } else {
            Write-Info "Restoring configuration files..."
            if (Test-Path "$configDir/.env") {
                Copy-Item "$configDir/.env" ".env" -Force
                Write-Ok "Restored .env"
            }
            if (Test-Path "$configDir/airflow-dags-config") {
                Copy-Item -Recurse "$configDir/airflow-dags-config/*" "airflow/dags/config/" -Force
                Write-Ok "Restored Airflow DAG configs"
            }
            Write-Ok "Configuration restore complete"
        }
    }

    Write-Ok "Restore finished"
    Write-Info "Restart services if needed: docker compose restart"
} finally {
    if ($tempDir -and (Test-Path $tempDir)) {
        Remove-Item -Recurse -Force $tempDir
    }
}
