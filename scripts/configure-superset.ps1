#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

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

$uri = "postgresql+psycopg2://$($env:POSTGRES_USER):$($env:POSTGRES_PASSWORD)@postgres:5432/$($env:POSTGRES_DB)"
$name = "Analytics Warehouse"

$python = @"
import os
uri = '$uri'
name = '$name'
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset.extensions import db
    from superset.models.core import Database
    existing = db.session.query(Database).filter_by(database_name=name).one_or_none()
    if existing:
        print(f'Database connection already exists: {name}')
    else:
        database = Database(database_name=name, sqlalchemy_uri=uri)
        db.session.add(database)
        db.session.commit()
        print(f'Created database connection: {name}')
"@

$python | docker compose exec -T superset python -
