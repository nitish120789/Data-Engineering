# CPF_Observability (Cross-Platform Forensics)

CPF_Observability provides a unified, AWR-style diagnostic workflow across database engines. Each engine folder now ships Linux and Windows runners that generate both detailed TXT and HTML reports per execution window.

## Default behavior
- Snapshot interval: 30 minutes
- Retention: 7 days
- Modes: one-off and scheduled
- Outputs per run:
  - `data/snapshots/snapshot_<timestamp>.txt`
  - `data/reports/report_<timestamp>.txt`
  - `data/reports/report_<timestamp>.html`

## Supported engines
- Oracle
- SQL Server
- PostgreSQL
- MySQL
- MongoDB
- Azure Cosmos DB
- Azure SQL DB
- Aurora PostgreSQL
- Aurora MySQL
- AWS RDS
- Cassandra
- Redis
- ClickHouse

## Folder model
Each engine folder includes:
- `config/default.env` for connectivity and runtime configuration
- `scripts/run_oneoff.sh` and `scripts/run_oneoff.ps1`
- `scripts/schedule_30m.sh` and `scripts/schedule_30m.ps1`
- `scripts/cleanup_retention.sh` and `scripts/cleanup_retention.ps1`
- `snapshots/` and `reports/` query artifacts for engine-specific extensions

Shared runtime implementation is centralized in:
- `common/run_oneoff_engine.sh`
- `common/run_oneoff_engine.ps1`
- `common/cleanup_retention_engine.sh`
- `common/cleanup_retention_engine.ps1`
- `common/report_builder_stub.py`

## AWR-style report sections
Reports include as much detail as available based on engine and granted privileges. Section set is designed so one run is often enough for first-pass RCA:

- Instance identity, version, and uptime
- Connection and throughput pressure
- Wait/resource bottlenecks
- Top workload statements/operations
- Blocking and deadlock signals
- IO/cache/log pressure indicators
- Replication or cluster health (where applicable)
- Engine-specific health data (for example InnoDB status, SQL Server waits, Redis INFO, Mongo serverStatus)

Sections unavailable due to permissions or engine/version feature gaps are marked explicitly in report output.

## Linux quick start
1. Edit `<engine>/config/default.env`
2. Convert line endings if copied from Windows:
	- `sed -i 's/\r$//' <engine>/config/default.env <engine>/scripts/*.sh`
3. Set execute permissions:
	- `chmod 750 <engine>/scripts/*.sh`
4. Run one-off:
	- `cd <engine>/scripts && ./run_oneoff.sh`

## Windows quick start
1. Edit `<engine>/config/default.env`
2. Run one-off:
	- `powershell -ExecutionPolicy Bypass -File <engine>\scripts\run_oneoff.ps1`
3. Print scheduler guidance:
	- `powershell -ExecutionPolicy Bypass -File <engine>\scripts\schedule_30m.ps1`

## Readiness Validator (Dry Run)
Run this before one-off or scheduling to validate tools, config, and connectivity across engines.

- Linux/Bash:
	- `database_admin/performance_reports/CPF_Observability/common/validate_environment.sh`
- Windows/PowerShell:
	- `powershell -ExecutionPolicy Bypass -File database_admin\\performance_reports\\CPF_Observability\\common\\validate_environment.ps1`

The validator prints an engine matrix with `TOOLS`, `CONFIG`, `CONNECTIVITY`, `READY`, and `NOTES`.

## Notes on validation
The framework and scripts are fully integrated in the repository. Runtime accuracy depends on:
- engine-native CLI tools being installed on the execution host
- valid credentials/connectivity in `default.env`
- required performance views/extensions enabled (for example `pg_stat_statements`)

Use the generated TXT report as the canonical raw diagnostic artifact and HTML for quick triage navigation.

## WSL client installation helper
If you plan to run the Linux/Bash workflow from WSL, install client tooling after WSL is active:

- Linux installer script:
	- `database_admin/performance_reports/CPF_Observability/common/install_client_tools_wsl.sh`
- Windows helper that prints the exact WSL command:
	- `powershell -ExecutionPolicy Bypass -File database_admin\\performance_reports\\CPF_Observability\\common\\install_client_tools_wsl.ps1`

The installer covers practical packages such as `mysql`, `psql`, `sqlcmd`, `redis-cli`, `mongosh`, `clickhouse-client`, `az`, and `cqlsh`. Oracle `sqlplus` and some Cassandra tooling still require manual vendor-specific installation.

## Configuration: config/default.env

Each engine's `config/default.env` file contains connectivity and runtime parameters. Variables follow these conventions:

### Generic connection variables (engine-agnostic fallback)
- `DB_HOST` - Database server hostname or IP
- `DB_PORT` - Database port
- `DB_USER` - Database user
- `DB_PASSWORD` - Database password (handle securely; avoid storing in version control)
- `DB_NAME` - Default database/schema/service name
- `DB_SSL_MODE` - SSL mode (where applicable: `disable`, `require`, `verify-ca`, `verify-full`)

### Engine-specific overrides
Engine-specific variables take precedence and allow parallel configuration of multiple engines:
- PostgreSQL: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
- MySQL: `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_LOGIN_PATH`
- Oracle: `ORACLE_HOST`, `ORACLE_PORT`, `ORACLE_SERVICE`, `ORACLE_USER`, `ORACLE_PASSWORD`, `ORACLE_CONNECT_STRING`
- SQL Server: `SQLSERVER_HOST`, `SQLSERVER_PORT`, `SQLSERVER_USER`, `SQLSERVER_PASSWORD`, `SQLSERVER_DATABASE`, `SQLSERVER_TRUST_CERT`
- Other engines: Redis, Cassandra, MongoDB, ClickHouse, Azure Cosmos DB, and Azure SQL DB follow similar patterns

### Example: Configuring PostgreSQL

```bash
# Minimal config for local development PostgreSQL
cat > postgresql/config/default.env << 'EOF'
DB_ENGINE=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_password_here
DB_NAME=postgres
PGHOST=localhost
PGPORT=5432
PGUSER=postgres
PGPASSWORD=your_password_here
PGDATABASE=postgres
EOF
```

```bash
# Production PostgreSQL with SSL
cat > postgresql/config/default.env << 'EOF'
DB_ENGINE=postgresql
DB_HOST=prod-db-1.example.com
DB_PORT=5432
DB_USER=monitoring
DB_PASSWORD=secure_monitoring_pwd
DB_NAME=postgres
DB_SSL_MODE=require
PGHOST=prod-db-1.example.com
PGPORT=5432
PGUSER=monitoring
PGPASSWORD=secure_monitoring_pwd
PGDATABASE=postgres
EOF
```

## Example: One-Off PostgreSQL Report

### On Linux/WSL
```bash
cd database_admin/performance_reports/CPF_Observability/postgresql
chmod 750 scripts/*.sh
./scripts/run_oneoff.sh
```

Output:
```
Running one-off snapshot at 20260430T142530Z
Target: monitoring@prod-db-1.example.com:5432/postgres
Snapshot written: data/snapshots/snapshot_20260430T142530Z.txt
Detailed TXT report: data/reports/report_20260430T142530Z.txt
Detailed HTML report: data/reports/report_20260430T142530Z.html
```

### On Windows/PowerShell
```powershell
cd 'database_admin\performance_reports\CPF_Observability\postgresql'
powershell -ExecutionPolicy Bypass -File scripts\run_oneoff.ps1
```

Reports are saved to `data/reports/` and `data/snapshots/` with ISO 8601 timestamp filenames.

### View PostgreSQL report
- TXT: Open `data/reports/report_<timestamp>.txt` in any text editor
- HTML: Open `data/reports/report_<timestamp>.html` in a web browser

TXT format is canonical for archival and scripted processing. HTML format provides interactive navigation across ~21 sections including version, configuration, connection pressure, wait events, top SQL by duration/CPU/reads, table IO, replication health, and vacuum/autovacuum status.

## PostgreSQL prerequisites

To collect all available sections, ensure:
1. **pg_stat_statements extension** is enabled (required for Top SQL sections):
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   SELECT pg_stat_statements_reset();
   ```
2. **Appropriate role privileges**: Monitoring user should have:
   ```sql
   GRANT pg_monitor TO monitoring;  -- PostgreSQL 10+
   ```
   Or manually grant required permissions on `pg_stat_*` views.
3. **PostgreSQL 10+** recommended (tested on 10, 12, 14, 16, 18).
