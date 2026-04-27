#!/usr/bin/env bash
set -euo pipefail

# Installs practical client tooling used by CPF_Observability validators/runners in WSL.
# Run after WSL is fully enabled and a distro is initialized.

if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

log() {
  echo "[cpf-install] $*"
}

install_apt_packages() {
  $SUDO apt-get update
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    python3 \
    python3-pip \
    mysql-client \
    postgresql-client \
    redis-tools
}

install_clickhouse_client() {
  if command -v clickhouse-client >/dev/null 2>&1; then
    return
  fi
  log "Installing ClickHouse client"
  curl https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml >/dev/null 2>&1 || true
  curl -fsSL https://packages.clickhouse.com/deb/key.gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | $SUDO tee /etc/apt/sources.list.d/clickhouse.list >/dev/null
  $SUDO apt-get update
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-client
}

install_sqlcmd() {
  if command -v sqlcmd >/dev/null 2>&1; then
    return
  fi
  log "Installing Microsoft sqlcmd"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" | $SUDO tee /etc/apt/sources.list.d/mssql-release.list >/dev/null
  $SUDO apt-get update
  ACCEPT_EULA=Y $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y mssql-tools18 unixodbc-dev
  if ! grep -q '/opt/mssql-tools18/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
  fi
  export PATH="$PATH:/opt/mssql-tools18/bin"
}

install_mongosh() {
  if command -v mongosh >/dev/null 2>&1; then
    return
  fi
  log "Installing mongosh"
  curl -fsSL https://pgp.mongodb.com/server-7.0.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg
  echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | $SUDO tee /etc/apt/sources.list.d/mongodb-org-7.0.list >/dev/null
  $SUDO apt-get update
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-mongosh
}

install_azure_cli() {
  if command -v az >/dev/null 2>&1; then
    return
  fi
  log "Installing Azure CLI"
  curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash
}

install_cqlsh() {
  if command -v cqlsh >/dev/null 2>&1; then
    return
  fi
  log "Installing cqlsh via pip"
  python3 -m pip install --user cqlsh
  if ! grep -q '$HOME/.local/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  fi
  export PATH="$HOME/.local/bin:$PATH"
}

print_manual_steps() {
  cat <<'EOF'

Manual follow-up still required for some engines:
1. Oracle sqlplus
   - Install Oracle Instant Client and sqlplus manually due Oracle distribution/licensing constraints.
   - https://www.oracle.com/database/technologies/instant-client.html

2. Cassandra nodetool
   - nodetool is typically shipped with the Cassandra server or full tools package.
   - If running validation from a Cassandra node, nodetool is usually already present.
   - If not, install the matching Cassandra tools package for your distro/version.

3. Optional improvements
   - mysqlsh if you want MySQL Shell in addition to mysql client
   - graphviz/pandoc if you later want richer report rendering/export
EOF
}

main() {
  log "Installing common client tools for CPF_Observability"
  install_apt_packages
  install_clickhouse_client
  install_sqlcmd
  install_mongosh
  install_azure_cli
  install_cqlsh
  log "Installation attempts complete"
  print_manual_steps
}

main "$@"
