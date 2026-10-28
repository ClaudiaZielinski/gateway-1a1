#!/usr/bin/env bash
# test_gateway_1a1.sh — tests for gateway_1a1.sh
#
# Run with: bash test_gateway_1a1.sh

set -euo pipefail

# Locate the script directory robustly, so the test can be run from anywhere.
# $0 may be a relative path; resolve it against $PWD before reading its real path.
script_dir="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=gateway_1a1.sh
source "$script_dir/gateway_1a1.sh"

# Counter for TAP-style output.
_test_count=0
_failures=0

# Compare expected vs actual and emit TAP-style output.
# Exits the script on first failure so partial output is visible.
assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    _test_count=$((_test_count + 1))

    if [[ "$expected" == "$actual" ]]; then
        printf 'ok %d - %s\n' "$_test_count" "$label"
    else
        printf 'not ok %d - %s\n' "$_test_count" "$label"
        printf '  ---\n' >&2
        printf '  expected: <%s>\n' "$expected" >&2
        printf '  actual:   <%s>\n' "$actual" >&2
        printf '  ...\n' >&2
        _failures=$((_failures + 1))
        exit 1
    fi
}

# Test 1: "ip route" output, modern default route line.
actual="$(gateway_1a1_parse_ip_route "default via 10.0.2.2 dev eth0" 2>/dev/null || true)"
assert_eq "10.0.2.2" "$actual" "ip_route_default_line"

# Test 2: "ip route" output with a specific-route line preceding the default.
actual="$(gateway_1a1_parse_ip_route \
    $'10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.5\ndefault via 192.168.1.1 dev wlan0' \
    2>/dev/null || true)"
assert_eq "192.168.1.1" "$actual" "ip_route_skips_specific_routes"

# Test 3: "ip route" output with no default route → empty result, exit 1.
actual=""
if gateway_1a1_parse_ip_route "10.0.0.0/24 dev eth0 proto kernel scope link" >/dev/null 2>&1; then
    actual="unexpected"
fi
assert_eq "" "$actual" "ip_route_no_default_returns_empty"

# Test 4: "route -n" output, default route as 0.0.0.0.
actual="$(gateway_1a1_parse_route_n \
    $'Kernel IP routing table\nDestination     Gateway         Genmask         Flags Metric Ref    Use Iface\n0.0.0.0         10.0.2.2        0.0.0.0         UG    100    0        0 eth0' \
    2>/dev/null || true)"
assert_eq "10.0.2.2" "$actual" "route_n_default_0000"

# Test 5: "route -n" output with "default" as the destination keyword.
actual="$(gateway_1a1_parse_route_n \
    $'Destination     Gateway         Genmask         Flags Metric Ref    Use Iface\ndefault         192.168.1.1      0.0.0.0         UG    0      0        0 eth0' \
    2>/dev/null || true)"
assert_eq "192.168.1.1" "$actual" "route_n_default_keyword"

# Test 6: "route -n" output with no default route → empty result.
actual=""
if gateway_1a1_parse_route_n \
    $'Kernel IP routing table\nDestination     Gateway         Genmask         Flags Metric Ref    Use Iface\n10.0.0.0       0.0.0.0         255.255.255.0   U     0      0        0 eth0' \
    >/dev/null 2>&1; then
    actual="unexpected"
fi
assert_eq "" "$actual" "route_n_no_default_returns_empty"

# Test 7: "netstat -rn" output, BSD/macOS default route.
actual="$(gateway_1a1_parse_netstat_rn \
    $'Routing tables\n\nInternet:\nDestination        Gateway            Flags      Netif Expire\ndefault            192.168.1.1        UGS        igb0' \
    2>/dev/null || true)"
assert_eq "192.168.1.1" "$actual" "netstat_rn_default"

# Test 8: "netstat -rn" output ignores 0/1 and 128.0/1 VPN-style routes.
actual="$(gateway_1a1_parse_netstat_rn \
    $'Internet:\nDestination        Gateway            Flags      Netif Expire\n0/1                10.0.0.1           UGS        tun0\n128.0/1            10.0.0.1           UGS        tun0\ndefault            192.168.1.1        UGS        igb0' \
    2>/dev/null || true)"
assert_eq "192.168.1.1" "$actual" "netstat_rn_ignores_vpn_split_routes"

# Test 9: "netstat -rn" output with 0.0.0.0 as the destination.
actual="$(gateway_1a1_parse_netstat_rn \
    $'Internet:\nDestination        Gateway            Flags      Netif Expire\n0.0.0.0            172.16.0.1         UGS        em0' \
    2>/dev/null || true)"
assert_eq "172.16.0.1" "$actual" "netstat_rn_default_0000"

# Test 10: "netstat -rn" output with no default route → empty result.
actual=""
if gateway_1a1_parse_netstat_rn \
    $'Internet:\nDestination        Gateway            Flags      Netif Expire\n10.0.0/24          link#1             UC         igb0' \
    >/dev/null 2>&1; then
    actual="unexpected"
fi
assert_eq "" "$actual" "netstat_rn_no_default_returns_empty"

# Test 11: "ip route" with blank lines and comments interleaved.
actual="$(gateway_1a1_parse_ip_route \
    $'\n# comment\n10.0.0.0/24 dev eth0 proto kernel\n\ndefault via 10.1.1.1 dev eth0' \
    2>/dev/null || true)"
assert_eq "10.1.1.1" "$actual" "ip_route_skips_blank_and_comment_lines"

# Test 12: "route -n" header row containing the word "Gateway" must not match.
# The header's first field is "Destination", so it should be skipped, but this
# guards against any future change that loosens the matcher.
actual=""
if gateway_1a1_parse_route_n \
    $'Destination     Gateway         Genmask\n0.0.0.0         10.0.2.2        0.0.0.0' \
    >/dev/null 2>&1; then
    actual="$(gateway_1a1_parse_route_n \
        $'Destination     Gateway         Genmask\n0.0.0.0         10.0.2.2        0.0.0.0' \
        2>/dev/null || true)"
fi
assert_eq "10.0.2.2" "$actual" "route_n_header_row_not_matched"

printf '\n%d..%d\n' 1 "$_test_count"
printf '# %d passed, 0 failed\n' "$_test_count"

exit 0
