#!/bin/bash
##  Re-establish rclone bisync tracking state
#
#   Usage:
#     resync [--dry-run] [--help] [TARGET]
#
#   rclone bisync requires an initial --resync to establish its tracking
#   state, and occasionally needs --resync again when it detects too many
#   changes. This script runs the resync with the same exclusion patterns
#   used by daily.sh, so you don't have to assemble them by hand.
#
#   TARGET matches the remote name in CLOUD_SYNCS entries (e.g. "toby",
#   "google"). If omitted, lists available targets.
#
#   For non-bisync modes (sync, copy), --resync is not applicable so a
#   normal sync/copy is run instead.

set -uo pipefail

# Resolve the actual script location, following symbolic links
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# Source machine-specific environment variables if env.sh exists
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/env.sh"
fi

# Source BUMP library
# shellcheck source=bump/bump.sh
source "${SCRIPT_DIR}/bump/bump.sh"

# Source settings and modules
# shellcheck source=settings.sh
source "${SCRIPT_DIR}/settings.sh"
# shellcheck source=sensitive.sh
source "${SCRIPT_DIR}/sensitive.sh"
# shellcheck source=network.sh
source "${SCRIPT_DIR}/network.sh"
# shellcheck source=cloud.sh
source "${SCRIPT_DIR}/cloud.sh"

# Print usage and available targets
show_usage() {
    echo "Usage: $0 [--dry-run] [--help] TARGET"
    echo ""
    echo "Re-establish rclone bisync tracking state by running --resync."
    echo ""
    echo "Options:"
    echo "  --dry-run    Preview changes without modifying anything"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "TARGET matches the remote name in CLOUD_SYNCS entries."
    echo ""
    echo "Available targets:"
    if [ ${#CLOUD_SYNCS[@]} -eq 0 ]; then
        echo "  (none configured — set CLOUD_SYNCS in env.sh)"
    else
        for entry in "${CLOUD_SYNCS[@]}"; do
            local cs_local cs_remote_name cs_remote_path cs_mode
            IFS=':' read -r cs_local cs_remote_name cs_remote_path cs_mode <<< "$entry"
            cs_mode="${cs_mode:-bisync}"
            echo "  ${cs_remote_name}  (${cs_local} <-> ${cs_remote_name}:${cs_remote_path}  mode=${cs_mode})"
        done
    fi
}

# Find the CLOUD_SYNCS entry matching a target remote name
find_sync_entry() {
    local target=$1
    for entry in "${CLOUD_SYNCS[@]}"; do
        local cs_remote_name
        IFS=':' read -r _ cs_remote_name _ _ <<< "$entry"
        if [ "$cs_remote_name" = "$target" ]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

# Run the resync for a given CLOUD_SYNCS entry
run_resync() {
    local entry=$1
    local dry_run=$2

    # Parse the entry (same format as run_cloud_sync)
    local rr_local rr_remote_name rr_remote_path rr_mode
    IFS=':' read -r rr_local rr_remote_name rr_remote_path rr_mode <<< "$entry"

    if [ -z "$rr_local" ] || [ -z "$rr_remote_name" ]; then
        log_message "invalid sync config: ${entry}"
        return 1
    fi

    # Build remote string
    local rr_remote="${rr_remote_name}:"
    if [ -n "$rr_remote_path" ]; then
        rr_remote="${rr_remote}${rr_remote_path}"
    fi

    rr_mode="${rr_mode:-bisync}"

    log_setting "resync local" "$rr_local"
    log_setting "resync remote" "$rr_remote"
    log_setting "resync mode" "$rr_mode"

    # For SFTP remotes, check host reachability
    local rr_remote_type
    rr_remote_type=$(rclone config show "$rr_remote_name" 2>/dev/null | grep '^type' | cut -d' ' -f3)
    if [ "$rr_remote_type" = "sftp" ]; then
        log_message "SFTP remote detected, checking host reachability: ${rr_remote_name}"
        if ! check_host_reachable "$rr_remote_name"; then
            log_message "${rr_remote_name} is not reachable — cannot resync"
            cleanup "$NETWORK_ERROR"
        fi
    fi

    # Check local path exists
    if [ ! -d "$rr_local" ]; then
        log_message "local path does not exist: ${rr_local}"
        cleanup "$MISSING_FOLDER"
    fi

    # Build exclusion arguments
    local -a rr_excludes
    mapfile -t rr_excludes < <(get_rclone_exclude_array)

    # For bisync mode, run with --resync
    # For sync/copy modes, --resync is not applicable — run normally
    case "$rr_mode" in
        bisync)
            local -a rr_cmd=(rclone bisync)
            rr_cmd+=(--resync)
            rr_cmd+=(--copy-links)
            rr_cmd+=(--progress)
            rr_cmd+=(--transfers "${SIMULTANEOUS_TRANSFERS:-4}")
            rr_cmd+=("${rr_excludes[@]}")

            if [ "$dry_run" = "yes" ]; then
                rr_cmd+=(--dry-run)
                log_message "DRY RUN — no changes will be made"
            fi

            rr_cmd+=("$rr_remote" "$rr_local")

            log_message "Running: ${rr_cmd[*]}"
            "${rr_cmd[@]}"
            ;;
        sync)
            log_message "mode is sync — --resync not applicable, running normal sync"
            run_rclone_sync "$rr_local" "$rr_remote" "${dry_run/yes/dry-run}"
            ;;
        copy)
            log_message "mode is copy — --resync not applicable, running normal copy"
            run_rclone_copy "$rr_local" "$rr_remote" "${dry_run/yes/dry-run}"
            ;;
        *)
            log_message "unknown sync mode: ${rr_mode}"
            return 1
            ;;
    esac
}

main() {
    set_stamp

    # Parse arguments
    local dry_run="no"
    local target=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="yes"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                log_message "Unknown option: $1"
                log_message "Use --help for usage information"
                cleanup "$BAD_CONFIGURATION"
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    # If no target specified, show usage with available targets
    if [ -z "$target" ]; then
        show_usage
        exit 0
    fi

    # Find matching CLOUD_SYNCS entry
    local entry
    if ! entry=$(find_sync_entry "$target") || [ -z "$entry" ]; then
        log_message "No cloud sync target matching '${target}'"
        log_message ""
        log_message "Available targets:"
        for e in "${CLOUD_SYNCS[@]}"; do
            local e_remote_name
            IFS=':' read -r _ e_remote_name _ _ <<< "$e"
            log_message "  ${e_remote_name}"
        done
        cleanup "$BAD_CONFIGURATION"
    fi

    log_message "resync: target=${target} dry_run=${dry_run}"

    # Register signal handling
    trap handle_signal 1 2 3 6 15

    # Run the resync
    run_resync "$entry" "$dry_run"
    local rc=$?

    if [ "$rc" -eq 0 ]; then
        log_message "resync completed successfully for ${target}"
    else
        log_message "resync failed for ${target} (exit code ${rc})"
    fi

    cleanup "$rc"
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
