#! /bin/bash

# Nothing to configure if ufw isn't installed (Debian doesn't ship it by default)
if ! which ufw > /dev/null 2>&1; then
  echo "WARNING: ufw is not installed - skipping host firewall configuration." >&2
  echo "         Install it (sudo apt install ufw) and re-run, or use your own firewall." >&2
  exit 0
fi

# Auto-load the environment, including .env.local
set -a
[ -f "$(dirname "$0")/../.env.local" ] && source "$(dirname "$0")/../.env.local"
source "$(dirname "$0")/../.env"
set +a

# Backup current UFW rules
echo "Saving UFW state:"
UFW_BACKUP_FILENAME=$(dirname "$0")/../ufw-backup-$(date +%s).tar.gz
sudo tar -cvzf $UFW_BACKUP_FILENAME /etc/ufw || exit 1
sudo chmod 600 $UFW_BACKUP_FILENAME

# Announce current state
echo "Current UFW state, backed up:"
sudo ufw status

# HOST-LEVEL SSH **NEVER DISABLE THIS RULE UNDER NORMAL CIRCUMSTANCES - EVEN IN PRODUCTION**
# https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/network-access
# (If sshd listens on a port other than 22, allow that port here instead BEFORE enabling the firewall)
sudo ufw allow 22/tcp || exit 1

###############
### TRAEFIK
# Public ports
sudo ufw allow 80/tcp || exit 1
sudo ufw allow 443/tcp || exit 1
# Private ports
# See README for why this will not protect your Traefik/Docker workloads
# This is a hole-punch in UFW to declare the port, not protect traffic
sudo ufw allow ${PRIVATE_HTTPS_PORT:?"Set PRIVATE_HTTPS_PORT for Traefik"}/tcp || exit 1
# sudo ufw allow 1025/tcp || exit 1 # Debug/Mailslurper

###############
### DEFAULT POLICY
# Block everything inbound that isn't allowed above; leave outbound open (ACME, image pulls)
sudo ufw default deny incoming || exit 1
sudo ufw default allow outgoing || exit 1

###############
### ENABLE ENFORCEMENT
# Turn the firewall on (--force skips the interactive SSH-disruption prompt)
sudo ufw --force enable || exit 1
sudo ufw status verbose
