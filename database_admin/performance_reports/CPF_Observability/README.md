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
