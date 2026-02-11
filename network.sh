#!/bin/bash
##  Check network is available and configured

##  Settings
#   STAMP               should be set by a call to set_stamp in bump.sh
#   ATTEMPTS            number of tries
#   WAIT                seconds between tries
#   WIREGUARD_INTERFACE WireGuard interface name (default: wg0)
#   VPN_DNS             Expected DNS server when VPN connected
#   SSH_TIMEOUT         Timeout for SSH connectivity checks

##  Dependencies
#   return_codes.sh
#   settings.sh
#   bump.sh

##  Notes
#   Routines here expect that a VPN is running and will
#   start one if necessary. WireGuard VPN is managed via
#   systemd-networkd and the vpn script.

# =============================================================================
#   FIREWALL FUNCTIONS
# =============================================================================

function firewall_active {
    # Check the firewall is up
    not_empty "date stamp" "$STAMP"

    log_message "firewall_active"

    if sudo ufw status | grep -qs "Status: inactive"; then
        sudo ufw enable || report $? "enable firewall"
        if sudo ufw status | grep -qs "Status: inactive"; then
            log_message "failed to activate firewall"
            return "$SECURITY_FAILURE"
        fi
    fi
    sudo ufw status numbered || report $? "state firewall rules"
    return 0
}

# =============================================================================
#   INTERFACE FUNCTIONS
# =============================================================================

function check_intfc {
    # Check an interface is available and UP
    local ci_intfc=$1
    log_setting "interface to check" "$ci_intfc"
    local ci_intfc_list
    ci_intfc_list=$(ip link | \
                    sed -n '/^[0-9]*:/p' | grep UP | grep -v DOWN | \
                    sed 's/^[0-9]*: \([0-9a-zA-Z]*\):.*/\1/')
    for i in $ci_intfc_list; do
        if [ "$i" == "$ci_intfc" ]; then
            return 0
        fi
    done
    return 1
}

# =============================================================================
#   WIREGUARD VPN FUNCTIONS
# =============================================================================

function check_wireguard {
    # Check if WireGuard interface is up and has a valid connection
    local cw_interface="${WIREGUARD_INTERFACE:-wg0}"

    log_message "check_wireguard (interface: ${cw_interface})"

    # Check interface exists and is UP
    if ! check_intfc "$cw_interface"; then
        log_message "WireGuard interface ${cw_interface} not up"
        return 1
    fi

    # Check WireGuard has an active handshake (connected to peer)
    if ! sudo wg show "$cw_interface" latest-handshakes 2>/dev/null | grep -q '[0-9]'; then
        log_message "WireGuard has no active peer connection"
        return 1
    fi

    return 0
}

function start_wireguard {
    # Start the WireGuard VPN using the vpn script

    log_message "start_wireguard"

    # Start VPN
    vpn up || report $? "starting WireGuard VPN"

    # Wait for interface to come up
    local sw_count=0
    while ! check_wireguard && [ "$sw_count" -lt "$ATTEMPTS" ]; do
        sleep "$WAIT"
        sw_count=$((sw_count + 1))
    done

    if ! check_wireguard; then
        log_message "failed to start WireGuard after ${ATTEMPTS} attempts"
        return "$NETWORK_ERROR"
    fi

    return 0
}

function stop_wireguard {
    # Stop the WireGuard VPN using the vpn script

    log_message "stop_wireguard"

    vpn down || report $? "stopping WireGuard VPN"
    return 0
}

# =============================================================================
#   DNS VERIFICATION
# =============================================================================

function check_vpn_dns {
    # Verify DNS is routing through VPN
    local cd_interface="${WIREGUARD_INTERFACE:-wg0}"
    local cd_expected_dns="${VPN_DNS}"

    log_message "check_vpn_dns (expected: ${cd_expected_dns})"

    # Check resolvectl status for the WireGuard interface
    local cd_current_dns
    cd_current_dns=$(resolvectl status "$cd_interface" 2>/dev/null | \
                     grep "DNS Servers" | \
                     awk '{print $3}')

    if [ -z "$cd_current_dns" ]; then
        log_message "WARNING: No DNS configured for ${cd_interface}"
        return 1
    fi

    if [ "$cd_current_dns" != "$cd_expected_dns" ]; then
        log_message "WARNING: DNS mismatch - expected ${cd_expected_dns}, got ${cd_current_dns}"
        return 1
    fi

    log_message "DNS correctly configured: ${cd_current_dns}"
    return 0
}

# =============================================================================
#   CONNECTIVITY CHECKS
# =============================================================================

function ping_check {
    # Test network connectivity by pinging a target through a specific interface.
    # Sends ping packets and evaluates packet loss.
    #
    # Arguments:
    #   $1 - Network interface to use (e.g., "eth0", "wg0")
    #   $2 - Target hostname or IP to ping
    #
    # Returns:
    #   0 - Success (packet loss at or below 50%)
    #   1 - Failure (packet loss above 50% or 100%)

    local pc_intfc=$1
    local pc_tgt=$2
    not_empty "ping check interface" "$pc_intfc"
    not_empty "ping check target" "$pc_tgt"
    not_empty "date stamp" "$STAMP"
    log_setting "interface to check with ping" "$pc_intfc"
    log_setting "target for ping" "$pc_tgt"

    local pc_max_loss=50
    local pc_packet_count=10
    local pc_timeout=20
    local pc_packets_lost
    # Use || true to prevent set -e from exiting on ping failure
    # Use -4 to force IPv4 (VPN may not route IPv6)
    pc_packets_lost=$(ping -4 -W "$pc_timeout" -c "$pc_packet_count" -I "$pc_intfc" "$pc_tgt" 2>/dev/null | \
                      grep -E '[0-9]+%' | \
                      awk '{print $6}') || true

    if [ -z "$pc_packets_lost" ] || [ "$pc_packets_lost" == "100%" ]; then
        log_message "all packets lost from ${pc_tgt} via ${pc_intfc}"
        return 1
    fi

    if [ "${pc_packets_lost}" == "0%" ]; then
        log_message "no packet loss from ${pc_tgt} via ${pc_intfc}"
        return 0
    fi

    # Partial packet loss
    log_message "${pc_packets_lost} packets lost from ${pc_tgt} via ${pc_intfc}"
    local pc_real_loss="${pc_packets_lost%\%}"
    if [[ ${pc_real_loss} -gt ${pc_max_loss} ]]; then
        return 1
    fi
    return 0
}

function check_connectivity {
    # Verify network connectivity, VPN-aware.
    #
    # If WireGuard is already up, tests connectivity through the VPN
    # interface (physical interface traffic is blocked by the firewall).
    # Otherwise tests the physical interface: first the default gateway,
    # then an external host as fallback (for gateways that block ICMP,
    # e.g. mobile hotspots).
    #
    # Arguments:
    #   $1 - Physical network interface (e.g. "wlan0", "enp0s31f6")
    #
    # Returns:
    #   0 - Network is reachable
    #   Calls report with exit message if unreachable (fatal)

    local cc_intfc=$1
    local cc_wg_interface="${WIREGUARD_INTERFACE:-wg0}"
    not_empty "interface for connectivity check" "$cc_intfc"

    # If VPN is already up, test through VPN — firewall blocks non-VPN traffic
    if check_wireguard; then
        log_message "VPN is up, testing connectivity via $cc_wg_interface"
        if ping_check "$cc_wg_interface" "1.1.1.1"; then
            log_message "connectivity confirmed via $cc_wg_interface"
            return 0
        fi
        report 1 "VPN is up but no connectivity via $cc_wg_interface" \
                 "no network so stop"
    fi

    # VPN not up — test the physical interface
    log_message "VPN is not up, testing connectivity via $cc_intfc"
    local cc_router
    cc_router=$(ip route | grep default | grep "$cc_intfc" | head -1 | cut -d ' ' -f 3)

    if [ -z "${cc_router}" ]; then
        report 1 "no default route on $cc_intfc" || return $?
    fi

    # Try gateway
    if ping_check "$cc_intfc" "$cc_router"; then
        log_message "gateway ${cc_router} reachable via $cc_intfc"
        return 0
    fi

    # Gateway didn't respond — try external host without interface binding
    # (some gateways block ICMP, and firewall rules may interfere with -I)
    log_message "gateway ${cc_router} not responding on $cc_intfc, trying external host"
    if ping -4 -W 5 -c 3 1.1.1.1 &>/dev/null; then
        log_message "external host reachable (gateway does not respond to ping)"
        return 0
    fi

    report 1 "no connectivity via $cc_intfc (gateway ${cc_router} and 1.1.1.1 both unreachable)" \
             "no network so stop"
}

function check_host_reachable {
    # Check if a remote host is reachable via SSH
    # Uses SSH_TIMEOUT setting for connection timeout
    #
    # Arguments:
    #   $1 - Host to check (user@host or just host)
    #
    # Returns:
    #   0 - Host is reachable
    #   1 - Host is not reachable

    local chr_host=$1
    local chr_timeout="${SSH_TIMEOUT:-5}"

    not_empty "host to check reachability" "$chr_host"
    log_message "check_host_reachable ${chr_host}"

    # Use ssh with connection timeout to check reachability
    # BatchMode=yes prevents password prompts
    # StrictHostKeyChecking=accept-new allows new hosts
    if ssh -o BatchMode=yes \
           -o ConnectTimeout="$chr_timeout" \
           -o StrictHostKeyChecking=accept-new \
           "$chr_host" true 2>/dev/null; then
        log_message "${chr_host} is reachable"
        return 0
    else
        log_message "${chr_host} is not reachable"
        return 1
    fi
}

# =============================================================================
#   MAIN NETWORK CHECK
# =============================================================================

function network_check {
    # Main network check function
    # Verifies firewall, network connectivity, and VPN status
    #
    # Arguments:
    #   $1 - Wired interface name
    #   $2 - Wireless interface name
    #   $3 - (optional) "dry-run" to skip changes

    local nc_wired=$1
    local nc_wireless=$2
    local nc_dry_run="${3:-}"
    local nc_wg_interface="${WIREGUARD_INTERFACE:-wg0}"

    not_empty "wired interface" "$nc_wired"
    not_empty "wireless interface" "$nc_wireless"
    log_message "network_check${nc_dry_run:+ (dry-run)}"

    # Log settings
    log_setting "usual wired interface" "$nc_wired"
    log_setting "usual wireless interface" "$nc_wireless"
    log_setting "WireGuard interface" "$nc_wg_interface"

    # Check firewall is active
    if [ "$nc_dry_run" = "dry-run" ]; then
        log_message "[DRY-RUN] would check/enable firewall"
    else
        firewall_active
    fi

    # Select physical interface (prefer wired over wireless)
    local nc_phys_intfc=""
    if check_intfc "$nc_wired"; then
        nc_phys_intfc="$nc_wired"
        if [ "$nc_dry_run" = "dry-run" ]; then
            log_message "[DRY-RUN] would block wlan, using $nc_wired"
        else
            sudo rfkill block wlan
        fi
    else
        nc_phys_intfc="$nc_wireless"
        if [ "$nc_dry_run" = "dry-run" ]; then
            log_message "[DRY-RUN] would unblock wlan, using $nc_wireless"
        else
            sudo rfkill unblock wlan
        fi
    fi

    # Check connectivity — if VPN is already up, tests through VPN;
    # otherwise tests the physical interface
    if [ "$nc_dry_run" = "dry-run" ]; then
        log_message "[DRY-RUN] would check connectivity via $nc_phys_intfc"
    else
        check_connectivity "$nc_phys_intfc"
    fi

    # Start WireGuard if not already up
    if ! check_wireguard; then
        if [ "$nc_dry_run" = "dry-run" ]; then
            log_message "[DRY-RUN] would start WireGuard"
        else
            log_message "WireGuard not connected, attempting to start"
            start_wireguard
        fi
    fi

    # Verify VPN DNS (non-fatal)
    if check_wireguard; then
        check_vpn_dns
    else
        log_message "WARNING: VPN is not connected"
    fi

    return 0
}
