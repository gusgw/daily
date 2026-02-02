#!/bin/bash
# Install sanoid configurations
#
# This installs sanoid.conf to /etc/sanoid/ for the main pool.
# If a subdirectory exists with a sanoid.conf (e.g., external/sanoid.conf),
# it is installed to /etc/sanoid/<subdirectory>/.
#
# Before running, copy *.conf.example files and adjust for your setup.
# Run as root or with sudo.

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Check that user-created configs exist
if [ ! -f "$SCRIPT_DIR/sanoid.conf" ]; then
    echo "ERROR: sanoid.conf not found in $SCRIPT_DIR" >&2
    echo "Copy sanoid.conf.example to sanoid.conf and adjust for your setup." >&2
    exit 1
fi

echo "Installing sanoid configurations..."

# Backup existing config
if [ -f /etc/sanoid/sanoid.conf ]; then
    BACKUP="/etc/sanoid/sanoid.conf.backup.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing config to $BACKUP"
    cp /etc/sanoid/sanoid.conf "$BACKUP"
fi

# Install main pool config
echo "Installing sanoid.conf..."
cp "$SCRIPT_DIR/sanoid.conf" /etc/sanoid/sanoid.conf

# Install configs from any subdirectories that contain a sanoid.conf
for subdir in "$SCRIPT_DIR"/*/; do
    [ -d "$subdir" ] || continue
    if [ -f "$subdir/sanoid.conf" ]; then
        dirname="$(basename "$subdir")"
        echo "Creating /etc/sanoid/${dirname}/..."
        mkdir -p "/etc/sanoid/${dirname}"
        echo "Installing ${dirname}/sanoid.conf..."
        cp "$subdir/sanoid.conf" "/etc/sanoid/${dirname}/"
        # Copy defaults file (required by sanoid)
        if [ -f /etc/sanoid/sanoid.defaults.conf ]; then
            echo "Copying defaults to ${dirname} directory..."
            cp /etc/sanoid/sanoid.defaults.conf "/etc/sanoid/${dirname}/"
        fi
    fi
done

echo ""
echo "Installation complete!"
echo ""
echo "The sanoid timer will process datasets listed in /etc/sanoid/sanoid.conf."
echo ""
echo "For external pools with separate configs, run manually when imported:"
echo "  sudo sanoid --configdir=/etc/sanoid/<pool> --cron"
echo ""
echo "To verify, check the journal after the next sanoid run:"
echo "  journalctl -u sanoid.service --since '5 minutes ago'"
