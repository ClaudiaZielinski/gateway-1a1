# gateway-1a1

Identifies the default route gateway IP address by parsing the routing tables produced by `ip route`, `route -n`, and `netstat -rn`. Zero third-party dependencies.

## Usage

```bash
source gateway_1a1.sh

gateway="$(gateway_1a1_detect)" && echo "gateway: $gateway"
```

The exported functions are:

- `gateway_1a1_detect` — runs the three parsers in order (`ip route`, then `route -n`, then `netstat -rn`) and prints the first gateway found. Returns exit code 0 if a gateway was found, 1 otherwise.
- `gateway_1a1_parse_ip_route` — takes the text output of `ip route` as a single argument and prints the gateway from the first `default` line.
- `gateway_1a1_parse_route_n` — takes the text output of `route -n` as a single argument and prints the gateway whose destination is `0.0.0.0` or `default`.
- `gateway_1a1_parse_netstat_rn` — takes the text output of `netstat -rn` as a single argument and prints the gateway whose destination is `default` or `0.0.0.0`.

The three `_parse_*` functions are exported because they are useful on their own when you already have the routing table text and do not want to re-run the command.

## Why this exists

Scripts that need to know the local gateway usually call `ip route` directly and grep for `default`. That works on Linux but not on BSD or macOS, where the routing table comes from `netstat -rn` and the column layout is different. This library wraps all three formats behind one call so the same script works across operating systems.

The trade-off: the parsers are line-oriented and rely on the destination column being the first whitespace-delimited field. They do not understand the full grammar of any routing table format. This is deliberate — a full parser would be larger and more fragile than the format itself, and the default route is consistently the line whose destination is `default` or `0.0.0.0`.

## Edge cases

On BSD/macOS, VPN clients commonly add `0/1` and `128.0/1` routes alongside the default route to force traffic through a tunnel. This library does **not** match those: only lines whose destination is literally `default` or `0.0.0.0` are treated as the default route. If your VPN rewrites the `default` line itself, this library will report the VPN gateway — which is usually what you want, since that is where your traffic actually goes.

If a routing-table command is missing or fails, the detector falls through to the next parser silently rather than aborting. Gateway detection is best-effort.
