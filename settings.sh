##  Settings for daily.sh

##  Default
#   USER

#   Limits for parallel work
MAX_SUBPROCESSES=16
SIMULTANEOUS_TRANSFERS=32

#   Set a wait time in seconds
#   for any task that is attempted
#   repeatedly
WAIT=5.0

#   Number of attempts for checks
#   that repeat on fail
ATTEMPTS=10

#   Make sure these units are active
UNITS_TO_CHECK=( "syncthing@${USER}.service" \
                 'sshd.service' \
                 'apparmor.service')

#   Automatically ensure that these folders and files
#   are not copied to remote backups etc.
SECRET_FOLDERS=( '.ssh' '.gnupg' '.cert' '.pki' '.password-store' )
SECRET_FILES=( "*.asc" "*.key" "*.pem" "id_rsa*" "id_dsa*" "id_ed25519*" )

#   Also keep these from being sent to cloud storage
SENSITIVE_FOLDERS=( '.git' '.stfolder' '.stversions' '.local' )

#   Symbols to separate output sections
RULE="***"
