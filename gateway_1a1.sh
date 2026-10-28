#!/usr/bin/env bash
# gateway_1a1.sh — Network Gateway Detector
#
# Identifies the default route gateway IP address by parsing routing tables.
# Works on Linux (ip route and route output) and BSD/macOS (netstat -rn output).
# Zero third-party dependencies: bash builtins + coreutils only.

set -euo pipefail

# Print the default route gateway IP to stdout, or nothing if no gateway is found.
# Returns exit code 0 if a gateway was found, 1 otherwise.
#
# We deliberately read from a *command* rather than accepting parsed table text
# as a parameter. This keeps the calling convention simple (just call the
# function) and matches how gateway detection is actually used in scripts.
#
# The function tries three parsers in order, one per table format:
#   1. "ip route" (Linux, modern) — the first non-comment, non-empty line
#      whose first field is exactly "default".
#   2. "route -n" (Linux, legacy) — a line whose Destination column is
#      "0.0.0.0" or "default".
#   3. "netstat -rn" (BSD, macOS) — a line whose Destination is "default" or
#      "0.0.0.0".
#
# Parsers return the first matching gateway they find. If a parser command is
# missing or fails, we silently fall through to the next parser rather than
# aborting — gateway detection is best-effort.
gateway_1a1_detect() {
    local out line gw

    # 1) ip route (Linux, modern)
    out="$(ip route 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
        gw="$(gateway_1a1_parse_ip_route "$out")"
        if [[ -n "$gw" ]]; then
            printf '%s\n' "$gw"
            return 0
        fi
    fi

    # 2) route -n (Linux, legacy)
    out="$(route -n 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
        gw="$(gateway_1a1_parse_route_n "$out")"
        if [[ -n "$gw" ]]; then
            printf '%s\n' "$gw"
            return 0
        fi
    fi

    # 3) netstat -rn (BSD, macOS)
    out="$(netstat -rn 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
        gw="$(gateway_1a1_parse_netstat_rn "$out")"
        if [[ -n "$gw" ]]; then
            printf '%s\n' "$gw"
            return 0
        fi
    fi

    return 1
}

# Parse the output of "ip route" (e.g. "default via 10.0.2.2 dev eth0").
# Echoes the gateway IP, or empty if not found.
#
# This format is the simplest of the three because every column is
# keyword-prefixed: the default route line begins with the literal token
# "default" and the gateway follows the keyword "via".
gateway_1a1_parse_ip_route() {
    local table="$1"
    local line

    # Read the first non-empty line that begins with "default".
    while IFS= read -r line; do
        # Trim leading whitespace.
        line="${line##"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue
        [[ "$line" != "default"* ]] && continue

        # First matching line wins.
        local -a tokens
        read -r -a tokens <<< "$line"
        local i
        for ((i = 0; i < ${#tokens[@]}; i++)); do
            if [[ "${tokens[i]}" == "via" ]]; then
                if ((i + 1 < ${#tokens[@]})); then
                    printf '%s\n' "${tokens[i + 1]}"
                    return 0
                fi
            fi
        done
        return 1
    done <<< "$table"

    return 1
}

# Parse the output of "route -n". Echoes the gateway IP, or empty if not found.
#
# The legacy "route -n" table on Linux looks like:
#
#   Kernel IP routing table
#   Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
#   0.0.0.0         10.0.2.2        0.0.0.0         UG    100    0        0 eth0
#
# We look for a data line whose Destination is "0.0.0.0" or "default",
# then take the second field as the gateway.
#
# "default" appears as a destination on some older route implementations,
# so we honour both forms rather than insisting on one.
gateway_1a1_parse_route_n() {
    local table="$1"
    local line

    while IFS= read -r line; do
        # Trim leading whitespace.
        line="${line##"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue

        local -a fields
        read -r -a fields <<< "$line"
        [[ ${#fields[@]} -lt 2 ]] && continue

        case "${fields[0]}" in
            0.0.0.0|default)
                printf '%s\n' "${fields[1]}"
                return 0
                ;;
        esac
    done <<< "$table"

    return 1
}

# Parse the output of "netstat -rn". Echoes the gateway IP, or empty if not found.
#
# On BSD and macOS, "netstat -rn" produces lines like:
#
#   default       192.168.1.1      UGS    igb0
#   0/1           192.168.1.1      UGS    igb0
#   128.0/1       192.168.1.1      UGS    igb0
#
# The first field is the destination; the second is the gateway. We accept
# "default" and "0.0.0.0" as default-route destinations and pick the first
# matching line.
#
# On BSD/macOS, "0/1" and "128.0/1" are often set up alongside the default
# route by VPN clients. We deliberately do NOT match those — the spec asks
# for the *default route* gateway, and the default route is the one whose
# destination is literally "default" or "0.0.0.0". Matching 0/1 and 128.0/1
# would sometimes return a VPN gateway even when the default route points
# elsewhere.
gateway_1a1_parse_netstat_rn() {
    local table="$1"
    local line

    while IFS= read -r line; do
        # Trim leading whitespace.
        line="${line##"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue

        local -a fields
        read -r -a fields <<< "$line"
        [[ ${#fields[@]} -lt 2 ]] && continue

        case "${fields[0]}" in
            default|0.0.0.0)
                printf '%s\n' "${fields[1]}"
                return 0
                ;;
        esac
    done <<< "$table"

    return 1
}
