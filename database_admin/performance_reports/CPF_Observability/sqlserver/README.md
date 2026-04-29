# CPF_Observability - sqlserver

## Purpose
Generate AWR-style deep performance diagnostics for **sqlserver** with default **30-minute snapshots** and **7-day retention**.

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

## AWR-Style Sections Produced (24 sections)
The HTML report is structured with a dashboard header, sticky sidebar navigation, auto-findings panel, and per-section data tables. All sections are collected from SQL Server DMVs and system catalog views with no external dependencies beyond `sqlcmd`.

| # | Section | AWR / ASH Analogue |
|---|---------|-------------------|
| 1 | Overview | Report header and metadata |
| 2 | Instance Identity and Version | DB_VERSION / instance info |
| 3 | Uptime, Build, and Server Configuration | Instance startup, CPU, memory, sp_configure |
| 4 | Database Inventory and Recovery Posture | Database flags, recovery models, isolation |
| 5 | Connection Pressure and Session Mix | Connection summary, session breakdown by login/app |
| 6 | Workload Throughput Counters | Batch requests, compilations, PLE, page IO |
| 7 | Scheduler and CPU Pressure | CPU runnable queue depth, load factor |
| 8 | Memory Grants and Buffer Health | Memory grant queue, buffer cache hit ratio, PLE |
| 9 | Waits by Category | AWR Top Wait Events (categorised: Lock, IO/Log, Parallelism, Memory, CPU, HADR, Latch) |
| 10 | Current Waiting Tasks and Wait Chains | ASH active wait chains with resource description |
| 11 | Active Requests (ASH Analogue) | ASH — in-flight statements with waits, CPU, reads |
| 12 | Long-Running Sessions and Open Transactions | Long-running and open-transaction session inventory |
| 13 | Blocking Sessions and Head Blockers | Blocking tree, head blocker identification |
| 14 | TempDB Usage and Version Store | TempDB allocation by type and per-session usage |
| 15 | Transaction Log and Recovery Health | Log space utilised, truncation reason, active log size |
| 16 | Database IO Stall by File | AWR File I/O — per-file read/write stall and avg latency |
| 17 | Top CPU Statements | AWR Top SQL by CPU — total and avg CPU ms |
| 18 | Top Duration Statements | AWR Top SQL by elapsed time — total and avg elapsed ms |
| 19 | Top Read and Write Statements | AWR Top SQL by logical reads and writes |
| 20 | Plan Cache Efficiency and Recompiles | Plan cache size, object types, recompile counters |
| 21 | Missing Index Candidates | Missing index DMV ranked by improvement measure |
| 22 | Query Store Regressions and Runtime Outliers | AWR SQL statistics / ASH — Query Store runtime outliers |
| 23 | Deadlock Signals from System Health | Deadlock XML from system_health XEvent session |
| 24 | AlwaysOn Replica Health | AG sync state, role, send/redo queue and lag |

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
