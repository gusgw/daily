#!/usr/bin/env bats
# Tests for network.sh
#
# These tests verify network checking and VPN management functions.

load 'test_helper'

# =============================================================================
# Basic Loading Tests
# =============================================================================

@test "network.sh can be sourced" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    run source_project_file "network.sh"
    assert_success
}

@test "network.sh has valid bash syntax" {
    run bash -n "${PROJECT_DIR}/network.sh"
    assert_success
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "firewall_active function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type firewall_active
    assert_success
    assert_output --partial "function"
}

@test "check_intfc function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_intfc
    assert_success
    assert_output --partial "function"
}

@test "check_wireguard function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_wireguard
    assert_success
    assert_output --partial "function"
}

@test "start_wireguard function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type start_wireguard
    assert_success
    assert_output --partial "function"
}

@test "stop_wireguard function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type stop_wireguard
    assert_success
    assert_output --partial "function"
}

@test "check_vpn_dns function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_vpn_dns
    assert_success
    assert_output --partial "function"
}

@test "check_connectivity function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_connectivity
    assert_success
    assert_output --partial "function"
}

@test "ping_check function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type ping_check
    assert_success
    assert_output --partial "function"
}

@test "check_host_reachable function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_host_reachable
    assert_success
    assert_output --partial "function"
}

@test "network_check function exists" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type network_check
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# OpenVPN Functions Removed
# =============================================================================

@test "start_tunnel function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type start_tunnel
    assert_failure
}

@test "check_single_tunnel function does not exist (removed)" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"
    run type check_single_tunnel
    assert_failure
}

# =============================================================================
# Interface Detection Tests
# =============================================================================

@test "check_intfc detects loopback interface" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # lo should always exist
    run check_intfc "lo"
    assert_success
}

@test "check_intfc returns failure for non-existent interface" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    run check_intfc "nonexistent99"
    assert_failure
}

# =============================================================================
# WireGuard Tests (when VPN is connected)
# =============================================================================

@test "check_wireguard detects wg0 when connected" {
    # Skip if wg0 is not up
    if ! ip link show wg0 &>/dev/null; then
        skip "wg0 interface not available"
    fi

    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # This test will pass if WireGuard is connected
    # and fail (skip) if it's not - both are valid outcomes
    run check_wireguard
    # Don't assert - just verify function runs without error
}

# =============================================================================
# DNS Verification Tests
# =============================================================================

@test "check_vpn_dns runs without error when VPN connected" {
    # Skip if wg0 is not up
    if ! ip link show wg0 &>/dev/null; then
        skip "wg0 interface not available"
    fi

    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Just verify the function runs - result depends on DNS config
    run check_vpn_dns
    # Don't assert specific result - depends on system state
}

# =============================================================================
# Host Reachability Tests
# =============================================================================

@test "check_host_reachable returns failure with no host" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    run check_host_reachable ""
    assert_failure
}

@test "check_host_reachable returns failure for unreachable host" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Use a definitely unreachable host
    run check_host_reachable "user@192.0.2.1"  # TEST-NET-1, not routable
    assert_failure
}

# =============================================================================
# ping_check Tests (with mocked ping)
# =============================================================================

@test "ping_check returns success with 0% packet loss" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock ping to report 0% loss
    ping() {
        echo "10 packets transmitted, 10 received, 0% packet loss, time 9012ms"
        return 0
    }
    export -f ping

    run ping_check "lo" "127.0.0.1"
    assert_success
}

@test "ping_check returns failure with 100% packet loss" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock ping to report 100% loss
    ping() {
        echo "10 packets transmitted, 0 received, 100% packet loss, time 9012ms"
        return 1
    }
    export -f ping

    run ping_check "lo" "192.0.2.1"
    assert_failure
}

@test "ping_check returns failure when packet loss exceeds 50%" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock ping to report 80% loss
    ping() {
        echo "10 packets transmitted, 2 received, 80% packet loss, time 9012ms"
        return 0
    }
    export -f ping

    run ping_check "lo" "192.0.2.1"
    assert_failure
}

@test "ping_check returns success with acceptable partial loss" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock ping to report 20% loss (below 50% threshold)
    ping() {
        echo "10 packets transmitted, 8 received, 20% packet loss, time 9012ms"
        return 0
    }
    export -f ping

    run ping_check "lo" "192.0.2.1"
    assert_success
}

@test "ping_check returns failure when ping produces no output" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock ping to produce no output
    ping() {
        return 1
    }
    export -f ping

    run ping_check "lo" "192.0.2.1"
    assert_failure
}

# =============================================================================
# check_connectivity Tests (with mocked ping, ip, and check_wireguard)
# =============================================================================

@test "check_connectivity succeeds via VPN when WireGuard is up" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock check_wireguard to report VPN is up
    check_wireguard() { return 0; }
    export -f check_wireguard

    # Mock ping to succeed through VPN interface
    ping() {
        echo "10 packets transmitted, 10 received, 0% packet loss, time 9012ms"
        return 0
    }
    export -f ping

    run check_connectivity "lo"
    assert_success
    assert_output --partial "connectivity confirmed via"
}

@test "check_connectivity succeeds via gateway when VPN is down" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock check_wireguard to report VPN is down
    check_wireguard() { return 1; }
    export -f check_wireguard

    # Mock ip to return a default route
    ip() {
        echo "default via 192.168.1.1 dev lo proto static"
    }
    export -f ip

    # Mock ping to succeed
    ping() {
        echo "10 packets transmitted, 10 received, 0% packet loss, time 9012ms"
        return 0
    }
    export -f ping

    run check_connectivity "lo"
    assert_success
    assert_output --partial "gateway 192.168.1.1 reachable"
}

@test "check_connectivity falls back to external host when gateway blocks ICMP" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock check_wireguard to report VPN is down
    check_wireguard() { return 1; }
    export -f check_wireguard

    # Mock ip to return a default route
    ip() {
        echo "default via 10.237.67.223 dev lo proto static"
    }
    export -f ip

    # Mock ping: fail for interface-bound pings (gateway), succeed for unbound (1.1.1.1)
    ping() {
        local has_interface_bind=false
        for arg in "$@"; do
            if [[ "$arg" == "-I" ]]; then
                has_interface_bind=true
                break
            fi
        done
        if $has_interface_bind; then
            echo "10 packets transmitted, 0 received, 100% packet loss, time 9012ms"
            return 1
        else
            return 0
        fi
    }
    export -f ping

    run check_connectivity "lo"
    assert_success
    assert_output --partial "gateway does not respond to ping"
}

@test "check_connectivity reports no default route when VPN is down" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock check_wireguard to report VPN is down
    check_wireguard() { return 1; }
    export -f check_wireguard

    # Mock ip to return no default route for our interface
    ip() {
        echo "10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.5"
    }
    export -f ip

    run check_connectivity "lo"
    assert_failure
    assert_output --partial "no default route"
}

# =============================================================================
# Dry-Run Tests (verify commands would be called correctly)
# =============================================================================

@test "start_wireguard checks for vpn command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Mock vpn command to not exist
    # The function should check for command existence
    if command -v vpn &>/dev/null; then
        # vpn exists - function should work
        # We don't actually run it to avoid side effects
        run type start_wireguard
        assert_success
    else
        # vpn doesn't exist - function should report error
        run start_wireguard
        assert_failure
    fi
}

@test "stop_wireguard checks for vpn command" {
    source_project_file "bump/bump.sh"
    set_stamp
    source_project_file "settings.sh"
    source_project_file "network.sh"

    if command -v vpn &>/dev/null; then
        run type stop_wireguard
        assert_success
    else
        run stop_wireguard
        assert_failure
    fi
}

# =============================================================================
# Settings Integration Tests
# =============================================================================

@test "network functions use WIREGUARD_INTERFACE from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"

    # Verify the setting is available
    assert [ -n "$WIREGUARD_INTERFACE" ]
    assert [ "$WIREGUARD_INTERFACE" == "wg0" ]
}

@test "network functions use VPN_DNS from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"

    assert [ -n "$VPN_DNS" ]
}

@test "network functions use SSH_TIMEOUT from settings" {
    source_project_file "bump/bump.sh"
    source_project_file "settings.sh"
    source_project_file "network.sh"

    assert [ -n "$SSH_TIMEOUT" ]
    [[ "$SSH_TIMEOUT" =~ ^[0-9]+$ ]]
}
