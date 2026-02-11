# Daily Maintenance System

Automated Linux workstation maintenance for an Arch Linux system with ZFS,
WireGuard VPN, and cloud synchronization. Built on the BUMP (Bash Utility
Management Package) library for standardized error handling.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Execution Flow](#execution-flow)
- [Log Files](#log-files)
- [Sanoid Snapshot Management](#sanoid-snapshot-management)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Related Documentation](#related-documentation)

## Overview

`daily.sh` runs a sequence of maintenance tasks:

1. Verify firewall and network connectivity
2. Ensure WireGuard VPN is connected
3. Check system health (ZFS, services, journal, temperatures)
4. Update packages and clean caches
5. Run ZFS backups to local external drives
6. Replicate ZFS datasets to a remote host via syncoid
7. Back up root filesystem via rsync
8. Synchronize directories to Google Drive via rclone bisync

The script uses file locking to prevent concurrent execution and handles
signals for graceful shutdown. Individual failures (e.g., a disconnected
backup drive) are logged but do not prevent subsequent tasks from running.

## Architecture

```
daily.sh                    Main orchestrator
├── env.sh                  Machine-specific environment variables (gitignored)
├── env.sh.example          Template for env.sh
├── bump/                   BUMP utility library (git submodule)
│   ├── bump.sh             Logging, validation, cleanup, signal handling
│   └── return_codes.sh     Standardized exit codes (60-119)
├── settings.sh             All configuration: targets, thresholds, arrays
├── network.sh              Firewall, interface selection, WireGuard VPN, DNS
├── system.sh               Systemd units, ZFS health, scrub, journal, thermal
├── package.sh              pacman updates, cache cleaning, AUR, database archive
├── backup.sh               zbackup (local ZFS), syncoid (remote), rbackup (root)
├── zbackup.sh              ZFS send/receive to external backup drives
├── rbackup.sh              Root filesystem rsync to /mnt/root
├── backup-configs/         Configuration files for zbackup (gitignored)
│   └── *.conf.example      Example config templates
├── sensitive.sh            Sensitive file detection, rclone exclusion generation
├── cloud.sh                rclone bisync/sync/copy with exclusions
├── sanoid/                 Sanoid configs with install script
│   ├── sanoid.conf.example         Main pool snapshot policy template
│   ├── sanoid-external.conf.example  External pool snapshot policy template
│   └── install.sh          Installs configs to /etc/sanoid/
├── logrotate/              Logrotate configs with install script
│   ├── zfs-backup          Rotation for /var/log/zfs-backup-*.log
│   ├── daily-maintenance   Rotation for /var/log/daily-maintenance.log
│   └── install.sh          Installs configs to /etc/logrotate.d/
└── tests/                  Bats test suite
```

## Requirements

### System

- Arch Linux (or compatible)
- Bash 4.0+
- systemd
- ZFS
- sudo access

### Packages

```bash
sudo pacman -S ufw wireguard-tools zfs-utils sanoid rsync rclone lm_sensors
```

Optional: `yay` for AUR updates, `tlp` and `thinkfan` for thermal management.

### Custom Scripts

These must be in PATH:

- **`vpn`** -- WireGuard management (`vpn up` / `vpn down`)

`zbackup` and `rbackup` are included in this repository. Create symlinks
so they are available in PATH:

```bash
ln -sf ../../src/daily/zbackup.sh ~/opt/bin/zbackup
ln -sf ../../src/daily/rbackup.sh ~/opt/bin/rbackup
```

## Installation

1. Clone and initialize:
```bash
git clone <repository-url>
cd daily
git submodule update --init
chmod +x daily.sh zbackup.sh rbackup.sh
```

2. Create machine-specific configuration:
```bash
cp env.sh.example env.sh
# Edit env.sh with your interface names, pool names, backup targets, etc.
```

3. Create backup configuration files:
```bash
cd backup-configs
cp example-external-drive.conf.example mypool.conf
# Edit mypool.conf with your pool name, datasets, and drive ID
```

4. Create sanoid configuration:
```bash
cd sanoid
cp sanoid.conf.example sanoid.conf
# Edit sanoid.conf with your pool and dataset names
sudo ./install.sh
```

5. Create symlinks for backup scripts:
```bash
ln -sf ../../src/daily/zbackup.sh ~/opt/bin/zbackup
ln -sf ../../src/daily/rbackup.sh ~/opt/bin/rbackup
```

6. Install logrotate configuration:
```bash
cd logrotate && sudo ./install.sh
```

7. Configure sudo access (see [Sudo Configuration](#sudo-configuration) below).

## Configuration

Machine-specific values go in `env.sh` (see `env.sh.example` for the full list).
Policy settings and thresholds are in `settings.sh`.

### env.sh Variables

```bash
# Network interfaces (find yours with: ip link show)
export MAIN_WIRED="enp0s25"
export MAIN_WIRELESS="wlan0"

# VPN DNS server
export VPN_DNS="10.0.0.1"

# ZFS pool name
export ZFS_POOL="tank"

# Syncoid remote replication
export SYNCOID_REMOTE_HOST="remote-host"
export SYNCOID_REMOTE_POOL="remote-pool"
export SYNCOID_DATASETS="user/src user/cloud"

# ZFS backup target config names (space-delimited)
export ZFS_BACKUP_TARGETS="mypool"

# Cloud sync
export CLOUD_SYNCS="${HOME}/cloud/:google:"

# Root filesystem backup
export ROOT_BACKUP_POOL="mypool"
export ROOT_BACKUP_CONFIG="mypool"
export ROOT_BACKUP_DATASET="mypool/source/root"
```

### settings.sh Thresholds

```bash
WAIT=5.0              # Seconds between retries
ATTEMPTS=10           # Retry count for network checks
SSH_TIMEOUT=5         # SSH connection timeout (seconds)
WIREGUARD_INTERFACE="wg0"
SCRUB_WARN_DAYS=30
POOL_CAPACITY_WARN=80
JOURNAL_WARN_SIZE="1G"
TEMP_WARN_THRESHOLD=85
TEMP_CRIT_THRESHOLD=95
```

### Security Exclusions

```bash
SECRET_FOLDERS=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )
SECRET_FILES=( "*.asc" "*.key" "*.pem" "id_rsa*" "id_dsa*" "id_ed25519*" ".env" )
SENSITIVE_FOLDERS=( '.git' '.stfolder' '.stversions' '.local'
                    '*venv*' 'node_modules' '__pycache__' '.cache' )
```

These patterns are automatically excluded from cloud sync operations.

### Sudo Configuration

Add to `/etc/sudoers` via `visudo`:

```sudoers
username ALL=(ALL) NOPASSWD: /usr/bin/ufw
username ALL=(ALL) NOPASSWD: /usr/bin/wg
username ALL=(ALL) NOPASSWD: /usr/bin/zpool
username ALL=(ALL) NOPASSWD: /usr/bin/zfs
username ALL=(ALL) NOPASSWD: /usr/bin/systemctl
username ALL=(ALL) NOPASSWD: /usr/bin/rfkill
username ALL=(ALL) NOPASSWD: /usr/bin/sanoid
username ALL=(ALL) NOPASSWD: /usr/bin/journalctl
username ALL=(ALL) NOPASSWD: /usr/bin/pacman
username ALL=(ALL) NOPASSWD: /usr/bin/find
```

## Usage

### Run manually

```bash
./daily.sh
```

### Dry-run mode

Preview what would happen without making changes:

```bash
./daily.sh --dry-run
```

### Scheduled execution

Add to crontab:

```bash
# Run at 3 AM daily, log stdout and stderr to a file
0 3 * * * /path/to/daily.sh >> /var/log/daily-maintenance.log 2>&1
```

The log file is rotated by the logrotate config installed from `logrotate/`.

### Run individual functions

```bash
source bump/bump.sh
source env.sh
source settings.sh
source network.sh

set_stamp
check_wireguard
```

## Execution Flow

| Step | Module | Function | What it does |
|------|--------|----------|-------------|
| 0 | backup.sh | `prepare_root_mount` | Import backup pool and mount /mnt/root if possible |
| 1 | network.sh | `network_check` | Verify firewall, select interface, start VPN, check DNS |
| 2 | system.sh | `system_check` | Ensure UNITS_TO_CHECK are active |
| 3 | system.sh | `run_all_health_checks` | ZFS health, scrub, failed services, journal, pacnew, orphans, thermal |
| 4 | package.sh | `run_package_maintenance` | Update packages, clean cache, archive database (skipped in dry-run) |
| 5 | backup.sh | `run_all_backups` | Root backup, local ZFS backups, syncoid replication |
| 6 | cloud.sh | `run_all_cloud_syncs` | rclone bisync to cloud with sensitive file exclusions |
| 7 | bump.sh | `cleanup` | Run registered cleanup functions and exit |

## Log Files

| File | Source | Content |
|------|--------|---------|
| `/var/log/zfs-backup-*.log` | zbackup | One log per backup pool |
| `/var/log/daily-maintenance.log` | daily.sh (if cron redirects) | Full stdout/stderr from the run |
| `journalctl -u sanoid.service` | systemd | Sanoid snapshot activity |

All log files under `/var/log/` are rotated monthly by the logrotate configs
in `logrotate/`. Install them with `cd logrotate && sudo ./install.sh`.

## Sanoid Snapshot Management

Sanoid configuration is stored in `sanoid/` and installed to `/etc/sanoid/`.

### Automatic snapshots (main pool)

The systemd `sanoid.timer` runs periodically and uses `/etc/sanoid/sanoid.conf`
to manage snapshots for the main pool. This happens automatically.

### Manual snapshots (external pools)

When an external pool is imported, manually run:

```bash
sudo sanoid --configdir=/etc/sanoid/<pool-name> --cron
```

The `--cron` flag tells sanoid to take and prune snapshots according to its
config. Despite the name, this does not set up a cron job -- it is simply
sanoid's standard operating mode for snapshot management.

To reinstall or update sanoid configs:

```bash
cd sanoid && sudo ./install.sh
```

## Security

### Network

- UFW firewall must be active (deny-by-default)
- WireGuard VPN is verified before network operations
- DNS is checked to confirm routing through VPN (detects DNS leaks)

### Process Isolation

- Uses `pkill -u $USER` patterns (not `killall`) to avoid affecting other users

### Sensitive Data Protection

Before cloud sync, `sensitive.sh` generates rclone `--exclude` patterns for
all files and folders listed in `SECRET_FOLDERS`, `SECRET_FILES`, and
`SENSITIVE_FOLDERS` in `settings.sh`. These are applied automatically to
every rclone operation.

### File Locking

A lock file at `$XDG_RUNTIME_DIR/daily-maintenance.lock` (or `/tmp/` as
fallback) prevents concurrent execution.

## Troubleshooting

### "Another instance is already running"

The lock file prevents concurrent runs. Check whether another instance is
actually running:

```bash
ps aux | grep daily.sh
```

If no other instance exists, the lock file is stale. It will be released
automatically when you run `daily.sh` again -- `flock` uses file descriptor
locking, not the file's existence.

### WireGuard VPN not connecting

```bash
# Check interface status
ip link show wg0
sudo wg show wg0

# Check systemd-networkd
networkctl status wg0

# Manual connect/disconnect
vpn up
vpn down
```

### ZFS health warnings

```bash
# Pool status
zpool status <pool>

# Run scrub if overdue
sudo zpool scrub <pool>

# Check capacity
zpool list <pool>
```

### Syncoid replication failing

```bash
# Test SSH connectivity to remote host
ssh <remote-host> true

# Ensure SSH agent has keys loaded
ssh-add -l

# Manual syncoid test
syncoid --quiet <pool>/<dataset> <remote-host>:<remote-pool>/<pool>/<dataset>
```

The SSH agent must have keys loaded when `daily.sh` runs. If running from
cron, ensure `SSH_AUTH_SOCK` is available.

### Sanoid errors for external pool

If sanoid reports errors about external datasets when the pool is not imported:

```bash
# Reinstall the main-pool-only config
cd sanoid && sudo ./install.sh
```

This ensures `/etc/sanoid/sanoid.conf` only references the main pool datasets.

### Debug mode

```bash
bash -x ./daily.sh
```

## Testing

```bash
# Run all tests
bats tests/

# Run tests for a specific module
bats tests/test_network.bats
bats tests/test_backup.bats
bats tests/test_system.bats
bats tests/test_cloud.bats
bats tests/test_sensitive.bats

# Shell script linting
shellcheck *.sh
```

## Related Documentation

- **REMOTE-REPLICATION.md** -- Setup instructions for configuring a remote host as a syncoid replication target
- **CLAUDE.md** -- Developer guidance for working with Claude Code on this project
