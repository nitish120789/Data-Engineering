# RHEL Database Installation And Tuning Playbooks

This directory provides generic DBA-ready Ansible playbooks for installing and configuring Oracle, PostgreSQL, MySQL, and MongoDB on RHEL 9+.

## What Is Included

- RHEL baseline hardening and performance role (kernel, limits, THP, tuned profile, NTP)
- PostgreSQL installation and tuning using PGDG repository
- MySQL installation and tuning using MySQL community repository
- MongoDB installation and tuning using official MongoDB repository
- Oracle installation prerequisites and optional Oracle Database Free 23ai installation

## Directory Layout

- ansible.cfg
- inventory/hosts.ini
- group_vars/all.yml
- playbooks/site.yml
- playbooks/rhel_baseline.yml
- playbooks/postgresql_rhel.yml
- playbooks/mysql_rhel.yml
- playbooks/mongodb_rhel.yml
- playbooks/oracle_rhel.yml
- playbooks/oracle19c_rhel9.yml
- roles/

## Usage

1. Update inventory groups in `inventory/hosts.ini`.
2. Override defaults in `group_vars/all.yml` as needed.
3. Install Ansible and required collections:

```bash
# Example on control host
python3 -m pip install --user ansible
ansible --version
```

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

4. Validate host connectivity:

```bash
ansible all -m ping
```

5. Run a dry-run first (recommended):

```bash
ansible-playbook playbooks/postgresql_rhel.yml --check --diff
```

6. Run a single engine playbook or run all:

```bash
ansible-playbook playbooks/postgresql_rhel.yml
ansible-playbook playbooks/mysql_rhel.yml
ansible-playbook playbooks/mongodb_rhel.yml
ansible-playbook playbooks/oracle_rhel.yml
ansible-playbook playbooks/oracle19c_rhel9.yml
ansible-playbook playbooks/site.yml
```

7. Run against specific hosts only (optional):

```bash
ansible-playbook playbooks/mysql_rhel.yml --limit mysql-db-01
```

8. Run with explicit privilege escalation user (optional):

```bash
ansible-playbook playbooks/site.yml -u ansible --become
```

## What Each Playbook Will Do

### playbooks/rhel_baseline.yml

- Applies common DB host baseline to `db_all` group.
- Installs OS utilities and performance tooling (`tuned`, `chrony`, `sysstat`, etc.).
- Sets timezone, sysctl values, OS limits, and disables THP if enabled in vars.

### playbooks/postgresql_rhel.yml

- Applies baseline role, then PostgreSQL role on `postgresql` hosts.
- Adds PGDG repository, disables default RHEL PostgreSQL module stream.
- Installs PostgreSQL server packages and initializes cluster if needed.
- Renders `postgresql.conf` and `pg_hba.conf`, then restarts service if changed.

### playbooks/mysql_rhel.yml

- Applies baseline role, then MySQL role on `mysql` hosts.
- Adds MySQL 8.4 community repo and installs `mysql-community-server`.
- Renders tuned `/etc/my.cnf` and restarts `mysqld` if configuration changes.

### playbooks/mongodb_rhel.yml

- Applies baseline role, then MongoDB role on `mongodb` hosts.
- Adds official MongoDB repository and installs `mongodb-org`.
- Renders tuned `/etc/mongod.conf` and restarts `mongod` if configuration changes.

### playbooks/oracle_rhel.yml

- Applies baseline role, then Oracle role on `oracle` hosts.
- Installs Oracle preinstall package, users/groups, and directories.
- Applies Oracle kernel parameters from `/etc/sysctl.d/98-oracle-rdbms.conf`.
- Optionally installs and starts Oracle Database Free 23ai when `oracle_install_mode=free23ai`.

### playbooks/oracle19c_rhel9.yml

- Applies a dedicated Oracle 19c enterprise install flow on `oracle` hosts running RHEL 9.
- Validates OS/architecture and installer media path before host mutation.
- Installs Oracle prerequisites (preinstall package or manual package/sysctl/limits path).
- Runs silent software-only install, root scripts, DBCA CDB/PDB creation, and systemd autostart setup.
- Supports secure password injection via Ansible Vault variables for SYS/SYSTEM/PDBADMIN.

### playbooks/site.yml

- Runs all of the above in sequence:
	- `rhel_baseline.yml`
	- `postgresql_rhel.yml`
	- `mysql_rhel.yml`
	- `mongodb_rhel.yml`
	- `oracle_rhel.yml`

## Expected Host Changes

- Packages and repositories are installed/updated for selected engines.
- Service units are enabled and started for target databases.
- Database configuration files are overwritten from role templates.
- Kernel/sysctl and limits settings are persisted and may affect host behavior.

Use `--check --diff` in change windows to preview impact before applying.

## Rollback Guidance

These playbooks are configuration-management driven and do not provide a one-click full rollback. Use this operational rollback pattern:

1. Stop further rollout by limiting scope to healthy hosts only.
2. Restore previous configuration files from backup/source control:
	- PostgreSQL: `/var/lib/pgsql/<version>/data/postgresql.conf`, `pg_hba.conf`
	- MySQL: `/etc/my.cnf`
	- MongoDB: `/etc/mongod.conf`
	- Oracle: `/etc/sysctl.d/98-oracle-rdbms.conf` and Oracle-specific parameter files
3. Re-apply known-good values in `group_vars/all.yml` and rerun the relevant playbook.
4. Restart only affected services and validate health before wider rollout.

Recommended pre-change backup commands:

```bash
sudo cp -a /etc/my.cnf /etc/my.cnf.bak.$(date +%Y%m%d%H%M%S)
sudo cp -a /etc/mongod.conf /etc/mongod.conf.bak.$(date +%Y%m%d%H%M%S)
sudo cp -a /var/lib/pgsql/17/data/postgresql.conf /var/lib/pgsql/17/data/postgresql.conf.bak.$(date +%Y%m%d%H%M%S)
sudo cp -a /var/lib/pgsql/17/data/pg_hba.conf /var/lib/pgsql/17/data/pg_hba.conf.bak.$(date +%Y%m%d%H%M%S)
```

## Post-Run Verification

Run these checks after each playbook execution:

```bash
ansible postgresql -m shell -a "systemctl is-active postgresql-17"
ansible mysql -m shell -a "systemctl is-active mysqld"
ansible mongodb -m shell -a "systemctl is-active mongod"
ansible oracle -m shell -a "systemctl is-active oracle-free-23ai || true"
```

Database connectivity smoke checks:

```bash
ansible postgresql -m shell -a "sudo -u postgres psql -c 'select version();'"
ansible mysql -m shell -a "mysql -Nse 'select version();'"
ansible mongodb -m shell -a "mongosh --quiet --eval 'db.version()'"
```

Host-level performance baseline checks:

```bash
ansible db_all -m shell -a "sysctl vm.swappiness fs.file-max net.core.somaxconn"
ansible db_all -m shell -a "ulimit -n; tuned-adm active"
```

## Semaphore UI Runbook

Use this section to create and run a Semaphore task that executes a simple Python-based mounted-disk inventory on `uk1lakehouse01.iongroup.net`.

### Files Used By Semaphore

- Playbook: `infrastructure/ansible/playbooks/semaphore_linux_disk_mounts.yml`
- Script: `infrastructure/ansible/scripts/disk_mount_report.py`

### What The Semaphore Task Will Do

- Connects to the target Linux host using the selected Semaphore inventory and key store.
- Ensures `python3` is installed on the host.
- Copies `disk_mount_report.py` to `/tmp/disk_mount_report.py`.
- Runs the script to collect mounted filesystem details using `findmnt`.
- Writes JSON output to `/tmp/disk_mount_report.json` on the server.
- Prints the JSON report into the Semaphore task log.

### Semaphore Objects To Create

Create these objects in the `Lakehouse` project:

1. Inventory

```ini
uk1lakehouse01.iongroup.net ansible_user=root ansible_python_interpreter=/usr/bin/python3
```

Use key store: `root for UK1 Dev`

2. Variable group

Name suggestion: `uk1lakehouse01-dev`

JSON variables:

```json
{
	"TARGET_HOST": "uk1lakehouse01.iongroup.net",
	"COLLECTION_NAME": "disk_mount_report",
	"REMOTE_OUTPUT_PATH": "/tmp/disk_mount_report.json"
}
```

3. Repository

Point Semaphore to this repository and the branch you want to run:

```text
https://github.com/Nitish-Anand-Srivastava/database-reliability-engineering.git
```

4. Task template

- App: `ansible`
- Playbook: `infrastructure/ansible/playbooks/semaphore_linux_disk_mounts.yml`
- Inventory: the new `uk1lakehouse01` inventory
- Environment: `uk1lakehouse01-dev`
- Repository: `database-reliability-engineering`

### How To Run It

1. Sync the repository in Semaphore so the new playbook/script are available.
2. Open the task template.
3. Launch the task.
4. Review the task log for the JSON payload.
5. Optionally verify on the target host:

```bash
cat /tmp/disk_mount_report.json
```

### Expected Output Shape

The task log and `/tmp/disk_mount_report.json` will contain JSON like this:

```json
{
	"host": "uk1lakehouse01.iongroup.net",
	"platform": "Linux-...",
	"generated_at_utc": "2026-05-01T12:00:00+00:00",
	"mounts": [
		{
			"target": "/",
			"source": "/dev/mapper/rhel-root",
			"fstype": "xfs",
			"size": "100G",
			"used": "40G",
			"avail": "60G",
			"use%": "40%",
			"options": "rw,relatime,seclabel,..."
		}
	]
}
```

## Notes

- Oracle enterprise media handling is environment-specific and license-controlled.
- Oracle role includes OS prerequisites and optional Database Free install path.
- Validate kernel settings with your platform and sizing standards before production rollout.
