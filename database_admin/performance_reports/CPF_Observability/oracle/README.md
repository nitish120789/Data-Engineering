# CPF_Observability - oracle

## Purpose
Generate AWR-style deep performance diagnostics for **oracle** with default **30-minute snapshots** and **7-day retention**.

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

## AWR-Style Sections Produced (22 sections)
The Oracle report targets Oracle Standard Edition-compatible dynamic views and keeps the same diagnostic style as SQL Server/MySQL reports.

### Engine-Specific Requirements
- Client tools: sqlplus
- Recommended privileges: SELECT_CATALOG_ROLE or explicit grants to V$/DBA_ views used in sections
- Oracle Standard Edition note: sections intentionally avoid Enterprise AWR pack dependencies

| # | Section | AWR / ASH Analogue |
|---|---------|-------------------|
| 1 | Instance Identity and Version | DB/instance identity |
| 2 | Initialization Parameters (Key) | Parameter baseline |
| 3 | Database Inventory and Size | Segment footprint |
| 4 | Connection Pressure and Session Mix | Session pressure profile |
| 5 | Workload Throughput Counters | Load profile |
| 6 | Memory (SGA/PGA) Health | Memory advisory posture |
| 7 | Wait Events (Top) | Top wait events |
| 8 | Wait Class Profile | Wait-class pressure |
| 9 | Active Sessions (ASH Analogue) | Active session sample |
| 10 | Blocking Chains and Locks | Blocking diagnostics |
| 11 | Long Operations | Long-running operation visibility |
| 12 | Top SQL by Elapsed Time | Top SQL elapsed |
| 13 | Top SQL by CPU Time | Top SQL CPU |
| 14 | Top SQL by Buffer Gets | Logical read-heavy SQL |
| 15 | Top SQL by Disk Reads | Physical read-heavy SQL |
| 16 | Cursor and Parse Pressure | Parse efficiency |
| 17 | Redo and Archive Pressure | Redo/archivelog pressure |
| 18 | Undo and Transaction Health | Undo pressure |
| 19 | Datafile IO Latency | File IO stall analogue |
| 20 | Tablespace Utilization | Space pressure |
| 21 | Top Segments by Size | Segment growth hotspots |
| 22 | Invalid Objects and Object Churn | Object health |

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

