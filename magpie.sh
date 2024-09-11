## Run magpie organisational script

##  Settings
#   CONDASH      is the path to the script that sets up conda so that
#                environments can be used in a script.
#   MAIL_SERVER  is the name of the process to check
#                for before running the magpie
#                script that expects a local IMAP
#                to be accessible.
#   mailpassword The IMAP password needed by offlineimap during magpie.

##  Default
#   HOME

##  Dependencies
#   return_codes.sh
#   useful.sh

##  Notes
#   - The magpie script should be in the path.
#   - A cleanup routine should be defined by the script
#     that sources this file. That routine is called by
#     not_empty on error.

function magpie {
    not_empty "mail server" "$MAIL_SERVER"
    not_empty "conda script to source" "$CONDASH"
    server=$(pgrep "${MAIL_SERVER}")
    rc=$?
    if [ "$rc" -eq 0 ]; then
        eval "$(conda shell.bash hook)"
        source "$CONDASH"
        conda activate magpie
        ${HOME}/magpie sync 2>&1
        conda deactivate
    else
        report "$rc" "no mail server"
    fi
    return $rc
}
