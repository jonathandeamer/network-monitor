## Network Analysis Summary

### 1. Dataset

| Machine | Connection | Samples | Period |
|---|---|---|---|
| Ethernet - old Mac | Wired | 10,761 | Mar 2 – Mar 10 (before 8am) |
| Wifi - personal secondary | WiFi | 7,434 | Mar 2 – Mar 10 |
| Wifi - personal main | WiFi | 6,299 | Mar 2 – Mar 10 (travel gap removed) |
| Wifi - work | WiFi | 2,021 | Mar 2 – Mar 10 (travel gap removed) |

### 2. Overall Performance

| Metric | Ethernet | secondary (WiFi) | Main (WiFi) | Work (WiFi) |
|---|---|---|---|---|
| **LAN latency** | **0.9ms** | 5.5ms | 6.5ms | 6.8ms |
| **LAN jitter** | **0.1ms** | 3.1ms | 2.4ms | 5.5ms |
| **LAN loss events** | 0.0% | 0.4% | 0.2% | 1.1% |
| **WAN1 (1.1.1.1) loss events** | 4.9% | 3.4% | 7.2% | 3.4% |
| **WAN2 (8.8.8.8) loss events** | 0.1% | 0.5% | 0.4% | 3.3% |
| **WAN1 avg latency** | 18.5ms | 23.3ms | 23.7ms | 34.2ms |
| **WAN2 avg latency** | 19.2ms | 24.3ms | 24.0ms | 39.4ms |
| **DNS** | 11.4ms | 15.6ms | 14.3ms | 32.7ms |

### 3. Key Findings

**WiFi is adding ~5ms latency and significant jitter, but it's not the main problem.** The WiFi machines consistently add 4-6ms of LAN latency on top of Ethernet's rock-solid 0.9ms, and WiFi jitter is 20-55x higher. But this is within normal WiFi overhead. The "Wifi - work" machine performs worst on WiFi (highest jitter, highest LAN loss), which may indicate it's further from the access point or using a weaker radio.

**The real problem is WAN1 (Cloudflare 1.1.1.1) — and it's upstream, not local.** WAN1 loss is the dominant issue, and critically:
- It hits the **Ethernet** machine just as hard (4.9% of samples) — so it has nothing to do with WiFi
- 62% of WAN1 loss events are **correlated across 2+ machines simultaneously**, confirming the problem is beyond the router
- WAN2 (Google 8.8.8.8) is virtually unaffected (0.1% on Ethernet) during the same periods

**WAN1 loss is highly asymmetric — it targets Cloudflare only.** Across all 26,515 samples:
- 4.8% show WAN1-only loss
- Only 0.1% show both WAN1+WAN2 loss together
- 0.5% show WAN2-only loss

This rules out a general upstream bandwidth or routing problem. Something specific to the path to `1.1.1.1` is failing.

**March 8 was the worst day by far — a sustained 10-hour WAN1 outage.** From ~13:00 to ~22:00 on March 8, all machines experienced 20-40% WAN1 packet loss every single hour, while WAN2 stayed at 0%. This affected Ethernet and WiFi equally. March 5 had a similar but shorter WAN1-only event from ~20:30–22:00, again hitting Ethernet and WiFi together.

**No time-of-day pattern for LAN.** Ethernet stays flat at 0.9ms regardless of hour. WiFi machines fluctuate mildly (4-15ms) with no strong pattern, suggesting there's no systematic congestion at specific times — the WiFi variation is just normal environmental noise.

### 4. Diagnosis

| Layer | Verdict |
|---|---|
| **LAN (WiFi)** | Working normally. ~5ms overhead and occasional jitter spikes are typical for residential WiFi. "Work" machine has the most jitter — may be worth checking placement. |
| **LAN (Ethernet)** | Excellent. Consistent sub-1ms, zero loss. |
| **WAN to 8.8.8.8** | Healthy. Near-zero loss across all machines. |
| **WAN to 1.1.1.1** | **Problematic.** Intermittent loss affecting all machines equally, with a major sustained event on March 8. This is an ISP routing issue on the path to Cloudflare, or Cloudflare deprioritising ICMP from your ISP's IP range. |

### 5. Recommendations

- **If you're using 1.1.1.1 as your DNS resolver**, consider switching to 8.8.8.8 or a different provider. The packet loss to Cloudflare may also affect DNS queries routed to them.
- **The "Wifi - work" machine** consistently shows 2x the WAN latency and jitter of the other WiFi machines (34ms vs ~23ms WAN, 5.5ms vs 2-3ms LAN jitter). This suggests a weaker WiFi connection — possibly distance, interference, or an older WiFi adapter.
- **The network itself is fine.** Your router's LAN side and your ISP's path to Google are both solid. The issue is narrowly scoped to the Cloudflare route.
