## Run bugwarrior

##  Settings
#   CONDASH      is the path to the script that sets up conda so that
#                environments can be used in a script.

##  Dependencies
#   return_codes.sh
#   useful.sh

function bug {
    not_empty "conda script to source" "$CONDASH"

    eval "$(conda shell.bash hook)"
    source "$CONDASH"
    conda activate bug
    bugwarrior-pull 2>&1 || report $? "pulling issues"
    conda deactivate

    return $rc
}
