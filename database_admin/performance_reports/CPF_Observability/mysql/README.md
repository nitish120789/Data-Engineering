# CPF_Observability - mysql

## Purpose
Generate AWR-style deep performance diagnostics for **mysql** with default **30-minute snapshots** and **7-day retention**.

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

## AWR-Style Sections Produced
## AWR-Style Sections Produced (25 sections)
The HTML report is structured with a dashboard header, sticky sidebar navigation, auto-findings panel, and per-section data tables. All sections use `performance_schema`, `information_schema`, and `SHOW` commands — no external schema extensions required.

| # | Section | AWR / ASH Analogue |
|---|---------|-------------------|
| 1 | Instance Identity and Version | DB_VERSION / instance info |
| 2 | Server Configuration Key Variables | DB Parameters / init.ora equivalents |
| 3 | Database Inventory and Size | Segment / tablespace size summary |
| 4 | Connection Pressure and Session Mix | Active session summary, V$SESSION equivalent |
| 5 | Workload Throughput Counters | AWR Load Profile — batch rates, DML, slow queries |
| 6 | Temporary Objects and Sort Pressure | PGA/temp space workload indicators |
| 7 | InnoDB Buffer Pool Health | Buffer cache hit ratio, dirty pages, wait-free pages |
| 8 | InnoDB IO and Log Pressure | V$FILESTAT / redo log write pressure indicators |
| 9 | Statement Wait Events | AWR Top Wait Events (performance_schema waits) |
| 10 | Lock Wait and Deadlock Counters | V$LOCK, lock wait and deadlock event counts |
| 11 | Active Sessions (ASH Analogue) | ASH — in-flight non-idle sessions with state/SQL |
| 12 | Active Lock Wait Chains | Blocking analysis (waiting trx → blocking trx) |
| 13 | Long-Running Transactions | Long-running open transactions with row lock depth |
| 14 | Top SQL by Total Time | AWR Top SQL by elapsed time |
| 15 | Top SQL by Execution Count | AWR Top SQL by executions |
| 16 | Top SQL by Rows Examined | AWR Top SQL by buffer gets / rows processed |
| 17 | Top SQL by Temp Disk Tables | Temp-space heavy SQL (sort/hash spill equivalent) |
| 18 | Top SQL by Errors and Warnings | SQL with error or warning accumulation |
| 19 | Table IO Latency | AWR Segment IO — per-table read/write latency |
| 20 | User and Host Activity Summary | Session activity grouped by user and host |
| 21 | Schema Size and Top Tables | Tablespace / object storage breakdown |
| 22 | Binary Log and GTID Status | Redo log / archive log status + GTID mode |
| 23 | Replication Status (MySQL 8+) | Data Guard / redo apply status (SHOW REPLICA STATUS) |
| 24 | Replication Status (MySQL 5.7 Legacy) | Legacy SHOW SLAVE STATUS (5.7 compat) |
| 25 | InnoDB Engine Status | Full InnoDB internal diagnostics (SHOW ENGINE INNODB STATUS) |

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
