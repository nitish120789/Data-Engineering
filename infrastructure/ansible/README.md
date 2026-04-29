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
- roles/

## Usage

1. Update inventory groups in `inventory/hosts.ini`.
2. Override defaults in `group_vars/all.yml` as needed.
3. Install required collections:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

4. Run a single engine playbook or run all:

```bash
ansible-playbook playbooks/postgresql_rhel.yml
ansible-playbook playbooks/mysql_rhel.yml
ansible-playbook playbooks/mongodb_rhel.yml
ansible-playbook playbooks/oracle_rhel.yml
ansible-playbook playbooks/site.yml
```

## Notes

- Oracle enterprise media handling is environment-specific and license-controlled.
- Oracle role includes OS prerequisites and optional Database Free install path.
- Validate kernel settings with your platform and sizing standards before production rollout.
