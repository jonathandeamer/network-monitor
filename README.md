# Network Monitor

A simple bash script that logs network performance metrics to CSV. Run it on multiple machines (WiFi and Ethernet) via cron to figure out whether connectivity problems are WiFi, your router, or your ISP.

## What It Measures

Each run pings three targets and does one DNS lookup:

| Metric | Default Target | Why |
|---|---|---|
| LAN ping | `192.168.1.1` (gateway) | Local network / WiFi health |
| WAN ping 1 | `1.1.1.1` (Cloudflare) | Upstream path A |
| WAN ping 2 | `8.8.8.8` (Google) | Upstream path B |
| DNS resolution | `dig` via gateway | DNS latency |

For each ping target it records packet loss %, average latency, and jitter. Everything gets appended as one CSV row with a timestamp and machine label.

## Requirements

- `bash`, `/sbin/ping`, `dig`, `bc` — all pre-installed on macOS and most Linux distros.

## Setup

```bash
cp monitor.conf.example monitor.conf
```

Edit `monitor.conf`:

```bash
# Required — identifies this machine in the CSV
MACHINE_LABEL="Wifi - living room"

# Optional overrides
# LAN_IP="192.168.1.1"
# WAN1_IP="1.1.1.1"
# WAN2_IP="8.8.8.8"
# DNS_QUERY="google.com"
# SAMPLES=5
# TIMEOUT_MS=2000
```

Set up a cron job to sample every minute:

```
* * * * * /bin/bash /path/to/network-monitor/network_monitor.sh
```

Or just run it manually: `bash network_monitor.sh`

### Multi-machine setup

The real utility of this script is running it on multiple machines at once. Clone the repo on each machine with a different `MACHINE_LABEL`. Include at least one wired Ethernet machine as a control — if a problem shows up on Ethernet too, you know it's not WiFi.

## Output

**`ping_monitor_log.csv`** — one row per sample:

```
timestamp,machine,lan_loss_pct,lan_avg_ms,lan_jitter_ms,wan1_loss_pct,wan1_avg_ms,wan1_jitter_ms,wan2_loss_pct,wan2_avg_ms,wan2_jitter_ms,dns_ms
2026-03-02 17:49:00,Wifi - living room,0.0,2.620,.801,0.0,19.418,2.717,0.0,21.123,4.499,14
```

**`ping_monitor_errors.log`** — stderr from `ping` and `dig` (e.g. "No route to host").

At one sample per minute you get ~1,440 rows per machine per day.

## Analysing the Data

The CSV is designed to be fed into an analysis tool rather than eyeballed. An LLM like Claude works well for this — it can correlate patterns across machines, spot time-based events, and separate local problems from upstream ones.

### Combining logs from multiple machines

Collect the CSVs into one directory and merge them:

```bash
{
  head -1 machine1.csv
  for f in machine*.csv; do tail -n +2 "$f"; done
} | { read -r header; echo "$header"; sort -t',' -k1,1 } > combined_log.csv
```

### Analysing with Claude

Upload or paste the combined CSV into [Claude](https://claude.ai) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and ask it to analyse. Something like:

> Here's a combined CSV of network monitor data from 4 machines on my LAN (1 Ethernet, 3 WiFi) collected over 8 days. Analyse the data and tell me what's going on with my network.

It'll typically compute per-machine averages, break things down by day, correlate outages across machines, and compare WiFi vs Ethernet and WAN1 vs WAN2.

The basic diagnostic logic:

```
Is there packet loss or high latency?
├── LAN only (gateway ping)?
│   ├── WiFi machines only → WiFi / router problem
│   └── Ethernet too → Router or gateway hardware issue
├── WAN only?
│   ├── Both WAN targets → ISP / general upstream problem
│   └── One WAN target only → Route-specific / peering issue
├── Both LAN and WAN?
│   └── Total connectivity loss — check physical link / ISP outage
└── DNS only (pings fine but DNS slow)?
    └── DNS resolver problem — try a different provider
```

### Example analysis

See [example-claude-analysis.md](example-claude-analysis.md) for a real analysis from 8 days of data across 4 machines. The short version: WiFi was fine, the actual problem was intermittent packet loss on the ISP's route to Cloudflare (`1.1.1.1`), confirmed because the wired Ethernet machine showed the same pattern while Google (`8.8.8.8`) was unaffected.

## Tips

- **Always include an Ethernet machine.** Without a wired control, you can't tell WiFi problems apart from upstream ones.
- **Use descriptive labels** like `Wifi - bedroom` rather than hostnames — they show up in every row and in the analysis.
- **Let it run a few days** before analysing. Some issues are intermittent and won't show up in a few hours.
- **Clean your data.** If a laptop was on a different network (e.g. travelling), remove those rows before combining.
- **Two WAN targets matter.** If both fail together it's your ISP. If only one fails it's a routing/peering issue with that specific destination.

## Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `MACHINE_LABEL` | *(required)* | Label for this machine in the CSV |
| `LAN_IP` | `192.168.1.1` | Default gateway IP |
| `WAN1_IP` | `1.1.1.1` | First upstream ping target |
| `WAN2_IP` | `8.8.8.8` | Second upstream ping target |
| `DNS_QUERY` | `google.com` | Domain for DNS timing |
| `SAMPLES` | `5` | Pings per target per run |
| `TIMEOUT_MS` | `2000` | Ping timeout (ms) |

## Platform Note

The script uses `/sbin/ping -W` with millisecond values (macOS convention). On Linux, `-W` expects seconds — adjust `TIMEOUT_MS` or modify the ping call accordingly.
