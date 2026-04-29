# CPF_Observability - aurora_mysql

## Purpose
Generate AWR-style deep performance diagnostics for **aurora_mysql** with default **30-minute snapshots** and **7-day retention**.

## Outputs
- Snapshot artifact: `data/snapshots/snapshot_<timestamp>.txt`
- Detailed TXT report: `data/reports/report_<timestamp>.txt`
- Detailed HTML report: `data/reports/report_<timestamp>.html`
- Operational logs: `logs/cpf.log`

## Scripts
### Linux
- One-off: `scripts/run_oneoff.sh`
- Schedule helper: `scripts/schedule_30m.sh`
- Retention cleanup: `scripts/cleanup_retention.sh`

### Windows
- One-off: `scripts/run_oneoff.ps1`
- Schedule helper (or installer): `scripts/schedule_30m.ps1`
- Retention cleanup: `scripts/cleanup_retention.ps1`

## Quick Start (Linux)
1. Update `config/default.env` with engine-specific connectivity.
2. Ensure LF line endings if files were transferred from Windows:
     - `sed -i 's/\r$//' config/default.env scripts/*.sh`
3. Set execute permission:
     - `chmod 750 scripts/*.sh`
4. Generate report:
     - `cd scripts && ./run_oneoff.sh`

## Quick Start (Windows)
1. Update `config/default.env`.
2. Generate report:
     - `powershell -ExecutionPolicy Bypass -File scripts/run_oneoff.ps1`
3. Print scheduler guidance:
     - `powershell -ExecutionPolicy Bypass -File scripts/schedule_30m.ps1`

## Configuration Notes
Edit `config/default.env`:
- Generic keys: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- Engine-specific keys are also available for MySQL, PostgreSQL, SQL Server, Oracle, Redis, MongoDB, ClickHouse, Cassandra, and Cosmos DB.

## AWR-Style Sections Produced (25 sections)
Aurora MySQL inherits the full MySQL deep collector (25 sections) and renders the same structured AWR-style report.

### Engine-Specific Requirements
- Client tools: mysql (or managed .NET fallback on Windows where enabled)
- Required access: performance_schema and information_schema access for statement/wait/lock diagnostics

The section map is identical to the MySQL README and includes identity/configuration, throughput, InnoDB pressure, ASH analogue, lock chains, top SQL dimensions, IO latency, and replication/binlog posture.

## Troubleshooting
- `No such file or directory` on Linux script execution:
    - Run: `sed -i 's/\r$//' scripts/*.sh config/default.env`
- `Permission denied`:
    - Run: `chmod 750 scripts/*.sh`
- Section marked unavailable:
    - Confirm required privileges/views/extensions are enabled on target engine.
- Missing client command:
    - Install the native CLI for your engine (`mysql`, `psql`, `sqlcmd`, `sqlplus`, `redis-cli`, `mongosh`, `clickhouse-client`, `cqlsh`, or `az`).

## Readiness Validator
Run these before one-off or scheduled execution to confirm required client tools, config presence, and connectivity.

- Linux: `cd scripts && ./validate_environment.sh`
- Windows: `powershell -ExecutionPolicy Bypass -File scripts/validate_environment.ps1`

The validator prints a pass/fail matrix by engine with notes for missing tools or connectivity failures.

