# CPF_Observability - PostgreSQL

## Purpose
Run an AWR-style PostgreSQL diagnostic report with a consistent structure:
- identity and configuration baseline
- throughput, wait, and session pressure
- blocking and long transaction diagnostics
- top SQL dimensions (when `pg_stat_statements` is enabled)
- storage, vacuum, lock, and replication posture

## Artifacts
- Snapshot file: `data/snapshots/snapshot_<timestamp>.txt`
- Detailed text report: `data/reports/report_<timestamp>.txt`
- Structured HTML report: `data/reports/report_<timestamp>.html`
- Runtime log: `logs/cpf.log`

## Scripts
### Linux
- One-off: `scripts/run_oneoff.sh`
- Schedule helper: `scripts/schedule_30m.sh`
- Retention cleanup: `scripts/cleanup_retention.sh`

### Windows
- One-off: `scripts/run_oneoff.ps1`
- Schedule helper: `scripts/schedule_30m.ps1`
- Retention cleanup: `scripts/cleanup_retention.ps1`

## Prerequisites
### Required
- `psql` client must be installed and available on `PATH`
- Network reachability to target host and port
- Credentials with access to PostgreSQL catalog stats views

### Recommended
- Role membership: `pg_read_all_stats`
- Extension: `pg_stat_statements`
- Read access to replication/slot views for HA sections

## Quick Start
### Linux
1. Edit `config/default.env`.
2. Normalize line endings if needed:
     - `sed -i 's/\r$//' config/default.env scripts/*.sh`
3. Set permissions:
     - `chmod 750 scripts/*.sh`
4. Run report:
     - `cd scripts && ./run_oneoff.sh`

### Windows
1. Edit `config/default.env`.
2. Ensure `psql` resolves:
     - `where psql`
3. Run report:
     - `powershell -ExecutionPolicy Bypass -File scripts/run_oneoff.ps1`

## Configuration
Use `config/default.env` with at least:
- `DB_HOST`
- `DB_PORT` (default `5432`)
- `DB_USER`
- `DB_PASSWORD`
- `DB_NAME`

## Section Coverage (21 sections)
| # | Section | Dependency |
|---|---------|------------|
| 1 | Instance Identity and Version | Base catalog access |
| 2 | Server Configuration Key Parameters | `pg_settings` |
| 3 | Database Inventory and Size | `pg_database`, `pg_stat_database` |
| 4 | Connection Pressure and Session Mix | `pg_stat_activity` |
| 5 | Workload Throughput and Transaction Counters | `pg_stat_database` |
| 6 | Temporary Objects and Sort Pressure | `pg_stat_database` |
| 7 | Buffer Cache and IO Hit Ratios | `pg_stat_database` |
| 8 | WAL and Checkpoint Pressure | `pg_stat_bgwriter`, `pg_stat_wal` |
| 9 | Wait Event Profile | `pg_stat_activity` |
| 10 | Active Sessions (ASH Analogue) | `pg_stat_activity` |
| 11 | Blocking Chains | `pg_blocking_pids`, `pg_stat_activity` |
| 12 | Long-Running Transactions | `pg_stat_activity` |
| 13 | Top SQL by Total Time | `pg_stat_statements` extension |
| 14 | Top SQL by Execution Count | `pg_stat_statements` extension |
| 15 | Top SQL by Shared Block Reads | `pg_stat_statements` extension |
| 16 | Top SQL by Temp Blocks | `pg_stat_statements` extension |
| 17 | Table IO and Heap/Index Access | `pg_stat_user_tables` |
| 18 | Index Usage and Bloat Indicators | `pg_stat_user_indexes` |
| 19 | Vacuum and Analyze Health | `pg_stat_user_tables`, `pg_stat_progress_vacuum` |
| 20 | Lock Inventory and Contention | `pg_locks` |
| 21 | Replication and Slot Health | `pg_stat_replication`, `pg_replication_slots` |

## Interpreting "Section unavailable"
This message can indicate one of the following:
- missing client command (`psql` not found)
- feature not enabled (most commonly `pg_stat_statements`)
- permissions/view exposure constraints
- version/view schema differences

Always check `logs/cpf.log` for the precise SQL error.

## pg_stat_statements Setup
If Top SQL sections are unavailable with `relation "pg_stat_statements" does not exist`, enable it:

1. Ensure server config includes:
     - `shared_preload_libraries = 'pg_stat_statements'`
2. Restart PostgreSQL.
3. In the target database:
     - `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`

## Troubleshooting
- `psql` not found:
  - Add PostgreSQL `bin` directory to `PATH`.
- Authentication failure:
  - Verify `DB_USER`, `DB_PASSWORD`, `pg_hba.conf`, and network ACLs.
- Replication sections unavailable:
  - Validate replica role and permissions on replication views.

## Readiness Validator
Run validator before scheduled deployment:
- Linux: `cd scripts && ./validate_environment.sh`
- Windows: `powershell -ExecutionPolicy Bypass -File scripts/validate_environment.ps1`

