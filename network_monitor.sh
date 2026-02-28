#!/bin/bash

########################################
# CONFIGURATION
########################################
LOGDIR="$HOME/network_monitor"
LOGFILE="$LOGDIR/ping_monitor_log.csv"
ERRFILE="$LOGDIR/ping_monitor_errors.log"

# Ping Targets
LAN_IP="192.168.0.1"
WAN1_IP="1.1.1.1"   # Cloudflare
WAN2_IP="8.8.8.8"   # Google DNS

PINGBIN="/sbin/ping"
SAMPLES=5
TIMEOUT=2

# MTU payload size for DOCSIS on Virgin Media
MTU_SIZE=1472

mkdir -p "$LOGDIR"

########################################
# CSV Header
########################################
if [ ! -f "$LOGFILE" ]; then
    echo "timestamp,lan_loss_pct,lan_avg_ms,lan_jitter_ms,wan1_loss_pct,wan1_avg_ms,wan1_jitter_ms,wan2_loss_pct,wan2_avg_ms,wan2_jitter_ms,mtu_loss_pct,mtu_avg_ms,mtu_jitter_ms,fault_class,severity" > "$LOGFILE"
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
    for ((i=1; i<n; i++)); do
        diff=$(echo "${arr[$i]} - ${arr[$i-1]}" | bc -l)
        abs=$(echo "${diff#-}" | bc -l)
        sum=$(echo "$sum + $abs" | bc -l)
    done
    echo "scale=3; $sum/($n-1)" | bc -l
}

########################################
# Ping Test Function
########################################
run_ping_test() {
    local target="$1"
    local extra_args="$2"

    result="$($PINGBIN -c $SAMPLES -t $TIMEOUT $extra_args $target 2>>"$ERRFILE")"

    local times=()
    while IFS= read -r line; do times+=("$line"); done \
        < <(echo "$result" | grep 'time=' | awk -F'time=' '{print $2}' | sed 's/ ms//')

    local loss_pct
    loss_pct=$(echo "$result" | grep -oE '[0-9]+% packet loss' | awk '{print $1}' | sed 's/%//')
    [ -z "$loss_pct" ] && loss_pct=100

    local avg jitter
    avg=$(calc_avg "${times[@]}")
    jitter=$(calc_jitter "${times[@]}")

    echo "$loss_pct,$avg,$jitter"
}

########################################
# Collect all metrics
########################################
lan_stats=$(run_ping_test "$LAN_IP")
wan1_stats=$(run_ping_test "$WAN1_IP")
wan2_stats=$(run_ping_test "$WAN2_IP")
mtu_stats=$(run_ping_test "$WAN1_IP" "-s $MTU_SIZE")

########################################
# Classification (per-host view, neutral wording)
########################################
lan_loss=$(echo "$lan_stats" | cut -d',' -f1)
wan1_loss=$(echo "$wan1_stats" | cut -d',' -f1)

fault="OK"
severity="0"

if (( $(echo "$lan_loss > 10" | bc -l) )); then
    fault="LAN Fault"           # Local network from this host's POV
    severity="2"
elif (( $(echo "$wan1_loss > 5" | bc -l) )); then
    fault="WAN Fault"           # This host sees a major WAN issue
    severity="2"
elif (( $(echo "$wan1_loss > 0" | bc -l) )); then
    fault="Minor WAN Fault"     # This host sees a small WAN issue
    severity="1"
fi

########################################
# Write output
########################################
echo "$timestamp,$lan_stats,$wan1_stats,$wan2_stats,$mtu_stats,$fault,$severity" >> "$LOGFILE"