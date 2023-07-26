# Daily tasks

I keep here shell functions that run routine maintenance
tasks daily on my Arch Linux workstation. They are particular
to my set up and I do not know if they are useful for
others.

## Security

The script(s) here assume that [`ssh` access has been
setup using `.ssh/config`](https://linuxhandbook.com/ssh-config-file/)
with no passphrase necessary.
[Use keys with no passphrase only with care.](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)

It also assumes that for the commands executed in this
script `sudo` does not require a password. Note that
this can be configured to work for specific commands only:

* [Run only Specific Commands with sudo in Linux](https://kifarunix.com/run-only-specific-commands-with-sudo-in-linux/)

* [How to run a specific program as root without a password prompt?](https://unix.stackexchange.com/questions/18830/how-to-run-a-specific-program-as-root-without-a-password-prompt)

Note the lists of files and folders that are excluded
from remote or insecure backups:

* `SECRET_FOLDERS`

* `SECRET_FILES`

* `SENSITIVE_FOLDERS`

## Delays

When repeated attempts at a task are necessry the delay
is `$WAIT` seconds.

## Parallel work

GNU `parallel` is used with `$MAX_SUBPROCESSES` processes.

Simultaneous transfers *via* `rclone` are permitted up to
`$SIMULTANEOUS_TRANSFERS`.

## System check

This just checks that units listed in `${UNITS_TO_CHECK[@]}`
are active, and if not attempts to start them.

## Local backup

Set a key file to decrypt the backup disk in the
environment variable `KEY_FILE`.

Make sure the backup device is set in the environment
variable `BACKUP_DISK`.

Make sure the backup name is set in the environment
variable `BACKUP_NAME`. This will be used as the device
name for the unlocked drive.

Files to be excluded from the local backup are listed
in `~/.exclude_local`, which is passed to `rsync`.

# Remote backups

A path to a remote backup should be in `$REMOTE_BACKUP`.

The remote backup routine is applied to the home folder,
and so includes a check that `${SECRET_FOLDERS[@]}` are
included in the `~/.exclude_remote` list, which is
passed to `rsync`.

# Shared files

The shared preparation routine sets up a copy of
the folder tree with sensitive or secret files and
folders removed so that it can be uploaded to
a cloud file sharing system.

# Archives

Remote archives are copies files and folders to S3
style object storage, as opposed to disk storage.
Folders archived are encrypted and sent via `rclone`.

# Package management

Running system updates without confirmation is also
something that should be done with caution, though I
find it is not a problem perhaps because I do check the
Arch website for news and advice fairly often.
