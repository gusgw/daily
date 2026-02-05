# Remote ZFS Replication Target Setup

Instructions to configure a remote host as a ZFS replication target using syncoid.

## Overview

The source machine uses `syncoid` to replicate ZFS datasets to a remote host over SSH. This requires:
1. ZFS pool available on the remote host
2. SSH key authentication from source
3. Appropriate ZFS permissions for receiving datasets
4. Optionally, sanoid for snapshot pruning on the remote host

## Prerequisites

- Arch Linux (or similar) on the remote host
- ZFS pool already created
- SSH server running
- Network connectivity between source and remote

---

## Step 1: Install Required Packages

```bash
sudo pacman -S sanoid lzop mbuffer
```

This installs:
- sanoid/syncoid - snapshot management and replication
- lzop - compression for faster transfers
- mbuffer - buffering for smoother replication

---

## Step 2: Create Receiving Dataset Structure

Create the parent dataset that will hold backups:

```bash
sudo zfs create <remote-pool>/<source-pool>
sudo zfs create <remote-pool>/<source-pool>/<user>
```

Child datasets will be created automatically by syncoid on first replication.

---

## Step 3: SSH Key Authentication

### On the source machine:

Check if SSH key exists, or generate one:
```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "source-to-remote"
```

Copy the public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

### On the remote host:

Add the key to authorized_keys for the receiving user:
```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "PASTE_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Test connection from source:
```bash
ssh <remote-host> "echo 'SSH connection works'"
```

---

## Step 4: Configure ZFS Permissions

There are two approaches: using sudo or delegating ZFS permissions.

### Option A: Sudo with NOPASSWD (Simpler)

Add to `/etc/sudoers.d/syncoid` on the remote host:
```bash
sudo visudo -f /etc/sudoers.d/syncoid
```

Add this line (replace `username` with the receiving user):
```
username ALL=(ALL) NOPASSWD: /usr/bin/zfs
```

This allows passwordless sudo for zfs commands, which syncoid uses by default.

### Option B: ZFS Permission Delegation (More Secure)

Delegate specific permissions to the receiving user:
```bash
# Allow user to receive, create, mount, and manage snapshots
sudo zfs allow -u username create,mount,receive,destroy,hold,release,snapshot,send <remote-pool>/<source-pool>

# Verify permissions
zfs allow <remote-pool>/<source-pool>
```

If using delegation, the source must call syncoid with `--no-privilege-elevation`:
```bash
syncoid --no-privilege-elevation <source-pool>/<dataset> <remote-host>:<remote-pool>/<source-pool>/<dataset>
```

---

## Step 5: Configure Sanoid for Snapshot Pruning (Recommended)

Replicated snapshots will accumulate on the remote host. Configure sanoid to prune them.

Create or edit `/etc/sanoid/sanoid.conf`:

```ini
# Backup datasets received from source
[remote-pool/source-pool/user/data]
    use_template = backup
    recursive = zfs

[remote-pool/source-pool/user/cloud]
    use_template = backup
    recursive = zfs

#############################
# templates below this line #
#############################

[template_backup]
    # Don't create new snapshots - these are replicated from source
    autosnap = no

    # Prune old snapshots
    autoprune = yes

    # Retention policy for replicated snapshots
    frequently = 0
    hourly = 48
    daily = 90
    monthly = 12
    yearly = 10

    # Warn if snapshots are stale (replication not running)
    hourly_warn = 90
    hourly_crit = 360
    daily_warn = 28
    daily_crit = 32
```

Enable and start the sanoid timer:
```bash
sudo systemctl enable --now sanoid.timer
```

---

## Step 6: Test Replication

### From the source machine, test a single dataset:

```bash
syncoid <source-pool>/<dataset> <remote-host>:<remote-pool>/<source-pool>/<dataset>
```

Note: syncoid does not have a dry-run option.

### On the remote host, verify:
```bash
zfs list -t all <remote-pool>/<source-pool>
```

You should see the dataset and its snapshots.

---

## Step 7: Firewall Configuration (if applicable)

If the remote host has a firewall, ensure SSH is allowed:

```bash
# If using ufw, allow from local network
sudo ufw allow from 192.168.0.0/24 to any port 22
```

---

## Step 8: Configure env.sh

Set these variables in `env.sh` on the source machine:

```bash
export SYNCOID_REMOTE_HOST="<remote-host>"
export SYNCOID_REMOTE_POOL="<remote-pool>"
export SYNCOID_DATASETS="<user>/src <user>/cloud <user>/encrypted"
```

---

## Verification Checklist

Run these checks to verify setup is complete:

```bash
# 1. ZFS pool exists on remote
zpool status <remote-pool>

# 2. Parent dataset exists on remote
zfs list <remote-pool>/<source-pool>

# 3. SSH works from source
ssh <remote-host> "zfs list <remote-pool>/<source-pool>"

# 4. ZFS permissions work from source
ssh <remote-host> "sudo zfs list"   # Option A
# OR
ssh <remote-host> "zfs list"        # Option B (delegation)

# 5. Sanoid timer is running on remote
systemctl status sanoid.timer

# 6. Test syncoid from source
syncoid <source-pool>/<dataset> <remote-host>:<remote-pool>/<source-pool>/<dataset>
```

---

## Troubleshooting

### "cannot receive: permission denied"
- Check ZFS permissions: `zfs allow <remote-pool>/<source-pool>`
- Or verify sudoers entry: `sudo cat /etc/sudoers.d/syncoid`

### "cannot create: parent does not exist"
- Create parent dataset: `sudo zfs create -p <remote-pool>/<source-pool>/<user>`

### "ssh: connect to host: Connection refused"
- Verify SSH is running: `systemctl status sshd`
- Check firewall: `sudo ufw status`

### "syncoid: command not found"
- Install sanoid package: `sudo pacman -S sanoid`

### Replication is slow
- Consider adding `--compress=lz4` to syncoid for WAN links
- For local network, mbuffer can help: `syncoid --mbuffer-size=1G ...`

---

## Summary

After completing these steps, the source can replicate ZFS datasets to the remote host with:

```bash
syncoid <source-pool>/<dataset> <remote-host>:<remote-pool>/<source-pool>/<dataset>
```

Additional datasets can be added via `SYNCOID_DATASETS` in `env.sh`.
These commands are automated by `daily.sh`.
