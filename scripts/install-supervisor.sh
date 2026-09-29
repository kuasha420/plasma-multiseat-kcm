#!/bin/bash
# Install and enable the Multiseat Supervisor Daemon
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installing Multiseat Supervisor and Control Utility..."
sudo install -m 755 "$SCRIPT_DIR/multiseat-supervisor.sh" /usr/local/bin/multiseat-supervisor
sudo install -m 755 "$SCRIPT_DIR/multiseat-ctl" /usr/local/bin/multiseat-ctl
sudo install -m 644 "$REPO_DIR/systemd/multiseat-supervisor.service" /etc/systemd/system/multiseat-supervisor.service

# Configure sudoers rule so any desktop user on either seat can invoke multiseat-ctl without password prompt
echo "ALL ALL=(ALL) NOPASSWD: /usr/local/bin/multiseat-ctl" | sudo tee /etc/sudoers.d/multiseat-ctl >/dev/null
sudo chmod 440 /etc/sudoers.d/multiseat-ctl

# If legacy seat1-specific service exists, stop and disable it
if systemctl is-active --quiet multiseat-seat1-supervisor.service 2>/dev/null; then
    echo "Migrating from legacy multiseat-seat1-supervisor.service..."
    sudo systemctl stop multiseat-seat1-supervisor.service
    sudo systemctl disable multiseat-seat1-supervisor.service
    sudo rm -f /etc/systemd/system/multiseat-seat1-supervisor.service /usr/local/bin/multiseat-seat1-supervisor
fi

sudo systemctl daemon-reload
sudo systemctl enable --now multiseat-supervisor.service

echo "Multiseat Supervisor successfully installed and active!"
systemctl status multiseat-supervisor.service --no-pager
