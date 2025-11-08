#!/bin/bash
# =====================================================================
# auto_container_watch_send_mail.sh
# Monitors Docker containers and Kubernetes port-forwards.
# Sends alerts only when state changes and restarts stopped ones.
# Handles Minikube via `minikube start --force`.
# =====================================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
LOGFILE="$LOG_DIR/container_watch.log"
CONFIG_FILE="$BASE_DIR/container_watch.conf"
STATE_FILE="$LOG_DIR/state.db"
PORT_STATE_FILE="$LOG_DIR/port-state.db"

mkdir -p "$LOG_DIR"

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------
send_mail() {
    SUBJECT="$1"
    BODY="$2"
    for EMAIL in $ALERT_EMAILS; do
        echo "$BODY" | mail -s "$SUBJECT" "$EMAIL"
    done
}

log_msg() {
    local LEVEL="$1"
    local MSG="$2"
    echo "$(date '+%F %T') [$LEVEL] $MSG" | tee -a "$LOGFILE"
}

setup_configuration() {
    echo "=== ⚙️  Initial Setup ==="
    read -p "Enter Docker container names or IDs (space separated): " CONTAINERS
    read -p "Enter alert email addresses (space separated): " ALERT_EMAILS
    echo
    echo "=== ⚙️  Kubernetes Setup ==="
    echo "🔍 Available services:"
    kubectl get svc -A
    echo
    echo "👉 Enter Kubernetes port-forward rules (space separated):"
    echo "Format: <namespace> <service-name> <port-mapping> ..."
    echo
    read -p "Enter Kubernetes forwarding configuration (or leave empty): " -a K8S_CONFIG

    {
        echo "CONTAINERS=\"$CONTAINERS\""
        echo "ALERT_EMAILS=\"$ALERT_EMAILS\""
        echo -n "K8S_CONFIG=("
        for i in "${K8S_CONFIG[@]}"; do echo -n "\"$i\" "; done
        echo ")"
    } > "$CONFIG_FILE"

    chmod 600 "$CONFIG_FILE"

    for EMAIL in $ALERT_EMAILS; do
        echo "✅ Container & Kubernetes Watch setup complete on host: $(hostname)" | \
        mail -s "✅ Watch Setup Complete" "$EMAIL"
    done

    log_msg "INFO" "Configuration saved to $CONFIG_FILE"
}

kubectl proxy --address=0.0.0.0 --accept-hosts='.*' &

# -------------------------------------------------------------------
# AUTO CONFIG CHECK
# -------------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    setup_configuration
fi
source "$CONFIG_FILE"

# -------------------------------------------------------------------
# MONITOR DOCKER CONTAINERS (Improved)
# -------------------------------------------------------------------
if command -v docker &>/dev/null; then
    touch "$STATE_FILE"
    declare -A LAST_STATE
    while read -r line; do
        [[ -z "$line" ]] && continue
        cname=$(echo "$line" | cut -d':' -f1)
        cstate=$(echo "$line" | cut -d':' -f2)
        LAST_STATE["$cname"]="$cstate"
    done < "$STATE_FILE"

    TMP_STATE=$(mktemp)
    for CONTAINER in $CONTAINERS; do
        ACTUAL_NAME=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep -E "^$CONTAINER| $CONTAINER$" | awk '{print $2}')
        [[ -z "$ACTUAL_NAME" ]] && ACTUAL_NAME="$CONTAINER"

        if ! docker ps -a --format '{{.Names}}' | grep -w "$ACTUAL_NAME" &>/dev/null; then
            MSG="❌ Container '$ACTUAL_NAME' not found."
            log_msg "ERROR" "$MSG"
            send_mail "❌ Missing Container" "$MSG"
            echo "$ACTUAL_NAME:missing" >> "$TMP_STATE"
            continue
        fi

        CURRENT_STATE=$(docker inspect -f '{{.State.Status}}' "$ACTUAL_NAME" 2>/dev/null)
        PREV_STATE="${LAST_STATE[$ACTUAL_NAME]}"

        if [[ "$CURRENT_STATE" != "$PREV_STATE" ]]; then
            MSG="⚙️ Container '$ACTUAL_NAME' state changed: $PREV_STATE ➜ $CURRENT_STATE"
            log_msg "INFO" "$MSG"
            send_mail "⚙️ Container State Changed" "$MSG"

            if [[ "$CURRENT_STATE" =~ (exited|dead|stopped) ]]; then
                if [[ "$ACTUAL_NAME" == "minikube" ]]; then
                    log_msg "WARN" "Minikube stopped. Restarting via minikube start --force"
                    send_mail "⚠️ Minikube Restarting" "Minikube stopped on $(hostname). Restarting..."
                    sudo rm -rf /tmp/juju-* >/dev/null 2>&1
                    minikube start --force >> "$LOGFILE" 2>&1
                else
                    log_msg "WARN" "Restarting container '$ACTUAL_NAME'"
                    docker start "$ACTUAL_NAME" >> "$LOGFILE" 2>&1
                    sleep 5
                    if docker ps --format '{{.Names}}' | grep -w "$ACTUAL_NAME" &>/dev/null; then
                        log_msg "OK" "✅ Container '$ACTUAL_NAME' restarted successfully"
                        send_mail "✅ Container Restarted" "Container '$ACTUAL_NAME' restarted successfully on $(hostname)."
                        CURRENT_STATE="running"
                    else
                        log_msg "FAIL" "❌ Failed to restart container '$ACTUAL_NAME'"
                        send_mail "❌ Container Restart Failed" "Failed to restart container '$ACTUAL_NAME' on $(hostname)."
                        CURRENT_STATE="failed"
                    fi
                fi
            fi
        fi

        echo "$ACTUAL_NAME:$CURRENT_STATE" >> "$TMP_STATE"
    done
    mv "$TMP_STATE" "$STATE_FILE"
else
    send_mail "⚠️ Docker Missing" "Docker not found on $(hostname)"
fi

# -------------------------------------------------------------------
# MONITOR KUBERNETES PORT-FORWARDS (Improved)
# -------------------------------------------------------------------
touch "$PORT_STATE_FILE"
declare -A LAST_PORT_STATE
while read -r line; do
    [[ -z "$line" ]] && continue
    key=$(echo "$line" | cut -d':' -f1)
    state=$(echo "$line" | cut -d':' -f2)
    LAST_PORT_STATE["$key"]="$state"
done < "$PORT_STATE_FILE"

TMP_PORT_STATE=$(mktemp)
COUNT=${#K8S_CONFIG[@]}

if (( COUNT % 3 == 0 && COUNT > 0 )); then
    for ((i=0; i<COUNT; i+=3)); do
        NS="${K8S_CONFIG[i]}"
        SVC="${K8S_CONFIG[i+1]}"
        PORTS="${K8S_CONFIG[i+2]}"
        KEY="${NS}_${SVC}_${PORTS}"

        if pgrep -f "kubectl port-forward.*$SVC.*$PORTS" >/dev/null; then
            CURRENT_STATE="active"
        else
            CURRENT_STATE="stopped"
        fi

        PREV_STATE="${LAST_PORT_STATE[$KEY]}"
        [[ -z "$PREV_STATE" ]] && PREV_STATE="unknown"

        if [[ "$CURRENT_STATE" != "$PREV_STATE" ]]; then
            log_msg "INFO" "🔄 Port-forward for $SVC ($NS) changed: $PREV_STATE ➜ $CURRENT_STATE"

            if [[ "$CURRENT_STATE" == "stopped" ]]; then
                log_msg "WARN" "Attempting to restart port-forward for $SVC ($NS) $PORTS"
                nohup kubectl port-forward --address 127.0.0.1 -n "$NS" svc/"$SVC" "$PORTS" >> "$LOGFILE" 2>&1 &
                sleep 5
                if pgrep -f "kubectl port-forward.*$SVC.*$PORTS" >/dev/null; then
                    log_msg "OK" "✅ Port-forward restarted for $SVC ($NS) $PORTS"
                    send_mail "✅ Port-forward Restarted" "Port-forward for $SVC ($NS) restarted successfully."
                    CURRENT_STATE="active"
                else
                    log_msg "FAIL" "❌ Failed to restart port-forward for $SVC ($NS) $PORTS"
                    send_mail "❌ Port-forward Restart Failed" "Restart for $SVC ($NS) failed."
                    CURRENT_STATE="failed"
                fi
            elif [[ "$PREV_STATE" =~ (stopped|failed) && "$CURRENT_STATE" == "active" ]]; then
                send_mail "✅ Port-forward Active Again" "Port-forward for $SVC ($NS) $PORTS is active again."
            fi
        fi

        echo "$KEY:$CURRENT_STATE" >> "$TMP_PORT_STATE"
    done
    mv "$TMP_PORT_STATE" "$PORT_STATE_FILE"
else
    log_msg "WARN" "No valid K8S_CONFIG found or incorrect format."
fi

log_msg "OK" "✅ Container and port-forward check completed."
