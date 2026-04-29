# CPF_Observability - postgresql

## Purpose
Generate AWR-style deep performance diagnostics for **postgresql** with default **30-minute snapshots** and **7-day retention**.

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
The PostgreSQL report is structured in the same AWR-style layout used by SQL Server/MySQL: identity, configuration, pressure indicators, active workload, top SQL dimensions, contention, storage, and replication posture.

### Engine-Specific Requirements
- Client tools: psql
- Recommended privileges: pg_read_all_stats, access to pg_stat_statements, pg_stat_replication, and pg_replication_slots
- Recommended extension: pg_stat_statements

| # | Section | AWR / ASH Analogue |
|---|---------|-------------------|
| 1 | Instance Identity and Version | DB instance identity |
| 2 | Server Configuration Key Parameters | Parameter baseline |
| 3 | Database Inventory and Size | Tablespace/database footprint |
| 4 | Connection Pressure and Session Mix | Session pressure profile |
| 5 | Workload Throughput and Transaction Counters | Load profile |
| 6 | Temporary Objects and Sort Pressure | Temp spill pressure |
| 7 | Buffer Cache and IO Hit Ratios | Buffer cache efficiency |
| 8 | WAL and Checkpoint Pressure | Redo/checkpoint health |
| 9 | Wait Event Profile | Top wait classes/events |
| 10 | Active Sessions (ASH Analogue) | In-flight sessions and waits |
| 11 | Blocking Chains | Blocking tree diagnostics |
| 12 | Long-Running Transactions | Transaction age pressure |
| 13 | Top SQL by Total Time | Top SQL elapsed |
| 14 | Top SQL by Execution Count | Top SQL by calls |
| 15 | Top SQL by Shared Block Reads | Read-heavy SQL |
| 16 | Top SQL by Temp Blocks | Temp-heavy SQL |
| 17 | Table IO and Heap/Index Access | Segment IO analogue |
| 18 | Index Usage and Bloat Indicators | Index efficiency signals |
| 19 | Vacuum and Analyze Health | Maintenance health |
| 20 | Lock Inventory and Contention | Locking pressure |
| 21 | Replication and Slot Health | Replica/slot lag posture |
| 22 | (Section availability dependent on privileges/extensions) | Collection coverage signal |

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

