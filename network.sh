##  Check network is available and configured

##  Settings
#   STAMP               should be set by a call to set_stamp in useful.sh.
#   ATTEMPTS            number of tries
#   WAIT                seconds between tries

##  Dependencies
#   return_codes.sh
#   settings.sh
#   useful.sh

##  Notes
#   Routines here expect that a VPN is running and will
#   start one if necessary. Note that arguments passed to
#   network_check specify network interfaces and
#   default VPN.

function firewall_active {
    # Check the firewall is up
    not_empty "date stamp" "$STAMP"

    >&2 echo "${STAMP}: firewall_active"

    if sudo ufw status | grep -qs "Status: inactive"; then
        sudo ufw enable || report $? "enable firewall"
        if sudo ufw status | grep -qs "Status: inactive"; then
            >&2 echo "${STAMP}: failed to activate firewall"
            return "$SECURITY_FAILURE"
        fi
    fi
    sudo ufw status numbered || report $? "state firewall rules"
    return 0
}

function ping_router {
    # Make sure we can ping the local router

    ##########################################################
    # The number of seconds to wait is globally set as $WAIT #
    ##########################################################

    local pr_intfc=$1
    log_setting "interface for router ping" "$pr_intfc"
    local pr_rc=1
    local pr_count=0
    while  [ "$pr_rc" -gt 0 ] && [ "$pr_count" -lt "$ATTEMPTS" ]; do
        sleep ${WAIT}
        ping -q -w 1 -c 1 `ip route |\
                           grep default |\
                           grep "$pr_intfc" |\
                           cut -d ' ' -f 3`
        pr_rc=$?
        pr_count=$((pr_count+1))
    done
    if [ "$pr_rc" -gt 0 ]; then
        report "$pr_rc" "ping to local router via $pr_intfc" "no network so stop"
    fi
    return 0
}

function ping_check {
    # Check ping via given interface to given url
    local pc_intfc=$1
    local pc_tgt=$2
    not_empty "date stamp" "$STAMP"
    log_setting "interface to check with ping" "$pc_intfc"
    log_setting "url for ping" "$pc_tgt"

    # Max lost packet percentage
    local pc_max_loss=50
    local pc_packet_count=10
    local pc_timeout=20
    local pc_packets_lost=$(ping -W $pc_timeout -c $pc_packet_count -I $pc_intfc $pc_tgt |\
                            grep % |\
                            awk '{print $6}')
    if ! [ -n "$pc_packets_lost" ] || [ "$pc_packets_lost" == "100%" ]; then
        cleanup $NETWORK_ERROR
        >&2 echo "${STAMP}: all packets lost from ${pc_tgt} via ${pc_intfc}"
    else
        if [ "${pc_packets_lost}" == "0%" ]; then
            return 0
        else
            # Packet loss rate between 0 and 100%
            >&2 echo "${STAMP}: $pc_packets_lost packets \
                      lost from ${pc_tgt} via ${pc_intfc}"
            local pc_real_loss=$(echo $pc_packets_lost | sed 's/.$//')
            if [[ ${pc_real_loss} -gt ${pc_max_loss} ]]; then
                cleanup $NETWORK_ERROR
            else
                return 0
            fi
        fi
    fi
}

function check_intfc {
    # Check an interface is available
    local ci_intfc=$1
    log_setting "interface to check" "$ci_intfc"
    local ci_intfc_list=$(ip link |\
                          sed -n  '/^[0-9]*:/p' | grep UP | grep -v DOWN |\
                          sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/')
    for i in $ci_intfc_list; do
        if [ "$i" == "$ci_intfc" ]; then
            return 0
        fi
    done
    return 1
}

function check_single_tunnel {
    # Make sure there is only a single tunnel set up

    >&2 echo "${STAMP}: check_single_tunnel"

    local cst_count=$(ip link |\
                      sed -n  '/^[0-9]*:/p' |\
                      sed 's/^[0-9]*: \([0-9a-z]*\):.*/\1/' |\
                      grep tun |\
                      wc -l)
    if [ "$cst_count" -eq 0 ]; then
        >&2 echo "${STAMP}: tunnel not found"
        return 1
    else
        if [ "$cst_count" -gt 1 ]; then
            >&2 echo "${STAMP}: too many tunnels found"
            cleanup "$NETWORK_ERROR"
        else
            return 0
        fi
    fi
}

function start_tunnel {
    # Start the OpenVPN encrypted tunnel

    >&2 echo "${STAMP}: start_tunnel"

    local st_ovpn=$1
    log_setting "OpenVPN configuration to start" "$st_ovpn"
    killall openvpn || report $? "stopping any tunnel"
    slow openvpn
    sudo openvpn --daemon --config "$st_ovpn"
    while ! check_single_tunnel; do
        sleep "$WAIT"
    done
    return 0
}

function network_check {

    >&2 echo "${STAMP}: network_check"

    local nc_wired=$1
    local nc_wireless=$2
    local nc_tunnel=$3
    local nc_default_ovpn=$4

    # Make source network connection is as expected
    log_setting "usual wired interface" "$nc_wired"
    log_setting "usual wireless interface" "$nc_wireless"
    log_setting "tunnel interface" "$nc_tunnel"
    log_setting "default VPN configuration" "$nc_default_ovpn"

    firewall_active
    if check_intfc "$nc_wired"; then
        sudo rfkill block wlan
        ping_router "$nc_wired"
    else
        sudo rfkill unblock wlan
        ping_router "$nc_wireless"
    fi
    if ! (check_intfc "$nc_tunnel" &&\
          ping_check "$nc_tunnel" wiki.archlinux.org); then
        start_tunnel $nc_default_ovpn
    fi
    return 0
}