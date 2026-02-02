#!/bin/bash
# Install logrotate configurations for daily maintenance system
#
# This installs rotation configs for:
#   - /var/log/zfs-backup-*.log (written by zbackup)
#   - /var/log/daily-maintenance.log (written when daily.sh output is redirected)
#
# Run as root or with sudo

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

echo "Installing logrotate configurations..."

# Backup and install zfs-backup config
if [ -f /etc/logrotate.d/zfs-backup ]; then
    BACKUP="/etc/logrotate.d/zfs-backup.backup.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing zfs-backup config to $BACKUP"
    cp /etc/logrotate.d/zfs-backup "$BACKUP"
fi

echo "Installing zfs-backup logrotate config..."
cp "$SCRIPT_DIR/zfs-backup" /etc/logrotate.d/zfs-backup

# Backup and install daily-maintenance config
if [ -f /etc/logrotate.d/daily-maintenance ]; then
    BACKUP="/etc/logrotate.d/daily-maintenance.backup.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing daily-maintenance config to $BACKUP"
    cp /etc/logrotate.d/daily-maintenance "$BACKUP"
fi

echo "Installing daily-maintenance logrotate config..."
cp "$SCRIPT_DIR/daily-maintenance" /etc/logrotate.d/daily-maintenance

echo ""
echo "Installation complete!"
echo ""
echo "Log files rotated:"
echo "  /var/log/zfs-backup-*.log    (monthly, keep 3, compress)"
echo "  /var/log/daily-maintenance.log (monthly, keep 3, compress)"
echo ""
echo "To verify:"
echo "  sudo logrotate --debug /etc/logrotate.d/zfs-backup"
echo "  sudo logrotate --debug /etc/logrotate.d/daily-maintenance"
