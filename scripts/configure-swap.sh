#! /bin/bash
# Adds a swap file sized at 100% of installed RAM (Ubuntu / Debian).
# Based on https://www.digitalocean.com/community/tutorials/how-to-add-swap-space-on-ubuntu-22-04
# Usage: ./configure-swap.sh   (override with SWAP_FILE=/path SWAP_PERCENT=100)

set -euo pipefail

SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_PERCENT="${SWAP_PERCENT:-100}"

# Check current swap state
echo
echo "Current swap:"
sudo swapon --show
if [ -n "$(swapon --show --noheadings)" ]; then
  echo "Swap is already active. Remove it first if you want to resize. Aborting."
  exit 1
fi

# Read RAM (kB) and compute the swap size in MiB
mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
swap_mb=$(( mem_kb * SWAP_PERCENT / 100 / 1024 ))
echo "RAM: $(( mem_kb / 1024 )) MiB -> swap: ${swap_mb} MiB (${SWAP_PERCENT}%)"

# Make sure the disk has room (keep 1 GiB spare)
avail_mb=$(df -Pm "$(dirname "$SWAP_FILE")" | awk 'NR==2 {print $4}')
if [ "$avail_mb" -lt $(( swap_mb + 1024 )) ]; then
  echo "Not enough free disk space: ${avail_mb} MiB available, need ${swap_mb} MiB plus 1 GiB spare."
  exit 1
fi

# Create the swap file (fallocate, falling back to dd)
echo
sudo fallocate -l "${swap_mb}M" "$SWAP_FILE" \
  || sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$swap_mb" status=progress

# Lock down permissions, format and enable
sudo chmod 600 "$SWAP_FILE"
sudo mkswap "$SWAP_FILE"
sudo swapon "$SWAP_FILE"

# Persist across reboots
echo
if ! grep -qs "^${SWAP_FILE} " /etc/fstab; then
  sudo cp /etc/fstab /etc/fstab.bak
  echo "${SWAP_FILE} none swap sw 0 0" | sudo tee -a /etc/fstab
fi

# Tune: prefer RAM, keep inode/dentry cache longer (per DigitalOcean guide)
sudo tee /etc/sysctl.d/99-swap.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sudo sysctl --system > /dev/null

# Verify
echo
sudo swapon --show
# Display
echo
free -h
