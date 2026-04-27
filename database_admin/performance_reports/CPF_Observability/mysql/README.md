# CPF_Observability - mysql

## Purpose
Generate AWR-style HTML performance insights for **mysql** with default **30-minute snapshots** and **7-day retention**.

## Paths
- Config: `database_admin/performance_reports/CPF_Observability/mysql/config/default.env`
- Snapshot collectors: `database_admin/performance_reports/CPF_Observability/mysql/snapshots/`
- Report datasets: `database_admin/performance_reports/CPF_Observability/mysql/reports/`
- Scripts: `database_admin/performance_reports/CPF_Observability/mysql/scripts/`
- Snapshot storage: `database_admin/performance_reports/CPF_Observability/mysql/data/snapshots/`
- HTML output: `database_admin/performance_reports/CPF_Observability/mysql/data/reports/`
- Logs: `database_admin/performance_reports/CPF_Observability/mysql/logs/`

## Quick start (junior DBA)
1. Edit `config/default.env` (connection/profile values).
2. Ensure scripts are executable: `chmod 750 scripts/*.sh`.
3. Ensure Linux line endings if files were copied from Windows: `sed -i 's/\r$//' scripts/*.sh`.
4. Run one-off: `cd .../mysql/scripts && ./run_oneoff.sh`.
5. Schedule every 30 minutes via cron/Task Scheduler using `schedule_30m.sh` guidance.
6. Run retention cleanup daily via `cleanup_retention.sh`.

## Troubleshooting

- Symptom: `No such file or directory` when running `./run_oneoff.sh`
	- Likely cause: CRLF line endings on Linux shell scripts.
	- Fix: `sed -i 's/\r$//' scripts/*.sh config/*.env`
- Symptom: `Permission denied`
	- Likely cause: execute bit not set.
	- Fix: `chmod 750 scripts/*.sh`
- Symptom: `: command not found .../config/default.env: line N`
	- Likely cause: `default.env` has CRLF or hidden BOM characters.
	- Fix: `sed -i 's/\r$//' config/default.env`

## Modes
- Scheduled mode: `RUN_MODE=scheduled` (default)
- One-off mode: `RUN_MODE=oneoff`

## How target MySQL instance is selected

`run_oneoff.sh` reads connection values from `config/default.env`:

- `MYSQL_LOGIN_PATH` (preferred, secure)
- `MYSQL_HOST`
- `MYSQL_PORT`
- `MYSQL_USER`
- `MYSQL_DATABASE`
- `MYSQL_PASSWORD` (optional, avoid plain text when possible)

Selection logic:

1. If `MYSQL_LOGIN_PATH` is set, script connects using `mysql --login-path=<value>`.
2. Otherwise, script uses host/port/user/database from `default.env`.
3. Environment variables override `default.env` values, so you can run one-off against another instance without editing files.

Examples:

- Use login-path:
	- `MYSQL_LOGIN_PATH=prod_obsv ./run_oneoff.sh`
- Use direct host override:
	- `MYSQL_HOST=10.20.30.40 MYSQL_PORT=3306 MYSQL_USER=cpf_reader MYSQL_DATABASE=performance_schema ./run_oneoff.sh`

## Required report sections
- Workload summary, top SQL/ops, waits, blocking/deadlocks, long-running workload, resource pressure, and recommendations.
