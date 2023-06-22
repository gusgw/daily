# Daily tasks

I keep here scripts that run routine maintenance tasks
daily on my Arch Linux workstation. They are particular
to my set up and I do not know if they are useful for
others.

The script(s) here assume that `ssh` access has been
setup using `.ssh/config` with no passphrase necessary.
Use keys with no passphrase only with care.

It also assumes that for the commands executed in this
script `sudo` does not require a password. Note that
this can be done for specific commands only.


Set a key file to decrypt the backup disk in the
environment variable KEY_FILE.

Make sure the backup disk is set in the environment
variable BACKUP_DISK.

Make sure the backup name is set in the environment
variable BACKUP_NAME. This will be used as the device
name for the unlocked

A path to a remote backup should be in $REMOTE_BACKUP,
and a second in $REMOTE_BACKUP_EXTRA.

Running system updates without confirmation is also
something that some advise against. I find it is not
a problem for me, perhaps because I do get updates
from Arch often.
