#!/bin/bash
#
# Usage: bash network_monitor.sh
# Cron:  * * * * * /bin/bash /path/to/network_monitor.sh

########################################
# CONFIGURATION
########################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/monitor.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: $CONF_FILE not found." >&2
    echo "Copy monitor.conf.example to monitor.conf and edit it for this machine." >&2
    exit 1
fi

source "$CONF_FILE"

if [ -z "$MACHINE_LABEL" ]; then
    echo "Error: MACHINE_LABEL must be set in $CONF_FILE" >&2
    exit 1
fi

# Defaults (overridable in monitor.conf)
LAN_IP="${LAN_IP:-192.168.1.1}"
WAN1_IP="${WAN1_IP:-1.1.1.1}"
WAN2_IP="${WAN2_IP:-8.8.8.8}"
DNS_QUERY="${DNS_QUERY:-google.com}"
SAMPLES="${SAMPLES:-5}"
TIMEOUT_MS="${TIMEOUT_MS:-2000}"

LOGFILE="$SCRIPT_DIR/ping_monitor_log.csv"
ERRFILE="$SCRIPT_DIR/ping_monitor_errors.log"

########################################
# CSV Header
########################################
if [ ! -f "$LOGFILE" ]; then
    echo "timestamp,machine,lan_loss_pct,lan_avg_ms,lan_jitter_ms,wan1_loss_pct,wan1_avg_ms,wan1_jitter_ms,wan2_loss_pct,wan2_avg_ms,wan2_jitter_ms,dns_ms" > "$LOGFILE"
fi

timestamp=$(date +"%Y-%m-%d %H:%M:%S")

########################################
# Math helpers
########################################
calc_avg() {
    local arr=("$@")
    local n="${#arr[@]}"
    [ "$n" -eq 0 ] && echo "timeout" && return
    local sum=0
    for x in "${arr[@]}"; do sum=$(echo "$sum + $x" | bc -l); done
    echo "scale=3; $sum/$n" | bc -l
}

calc_jitter() {
    local arr=("$@")
    local n="${#arr[@]}"
    [ "$n" -le 1 ] && echo "NA" && return
    local sum=0
    local diff abs
    for ((i=1; i<n; i++)); do
        diff=$(echo "${arr[$i]} - ${arr[$i-1]}" | bc -l)
        abs=$(echo "if ($diff < 0) -1 * $diff else $diff" | bc -l)
        sum=$(echo "$sum + $abs" | bc -l)
    done
    echo "scale=3; $sum/($n-1)" | bc -l
}

########################################
# Ping Test Function
########################################
run_ping_test() {
    local target="$1"

    local result
    result="$(/sbin/ping -c "$SAMPLES" -W "$TIMEOUT_MS" "$target" 2>>"$ERRFILE")"

    local times=()
    while IFS= read -r line; do times+=("$line"); done \
        < <(echo "$result" | grep 'time=' | awk -F'time=' '{print $2}' | sed 's/ ms//')

    local loss_pct
    loss_pct=$(echo "$result" | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    [ -z "$loss_pct" ] && loss_pct=100

    local avg jitter
    avg=$(calc_avg "${times[@]}")
    jitter=$(calc_jitter "${times[@]}")

    echo "$loss_pct,$avg,$jitter"
}

########################################
# DNS Resolution Timing
########################################
run_dns_test() {
    local dns_output
    dns_output=$(dig "@$LAN_IP" "$DNS_QUERY" 2>>"$ERRFILE")

    local dns_ms
    dns_ms=$(echo "$dns_output" | grep -oE 'Query time: [0-9]+' | grep -oE '[0-9]+')
    [ -z "$dns_ms" ] && dns_ms="timeout"

    echo "$dns_ms"
}

########################################
# Collect all metrics
########################################
lan_stats=$(run_ping_test "$LAN_IP")
wan1_stats=$(run_ping_test "$WAN1_IP")
wan2_stats=$(run_ping_test "$WAN2_IP")
dns_ms=$(run_dns_test)

########################################
# Write output
########################################
echo "$timestamp,$MACHINE_LABEL,$lan_stats,$wan1_stats,$wan2_stats,$dns_ms" >> "$LOGFILE"
