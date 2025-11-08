#!/bin/bash
# =====================================================================
# ssl_manager.sh
# Smart Certbot + Nginx SSL Management Script
# =====================================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$BASE_DIR/.ssl_manager.conf"
LOG_FILE="$BASE_DIR/ssl_manager.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------
# Load existing config
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    EMAIL=""
    DOMAINS=""
fi

# ---------------------------------------------------------------------
# CRON mode (non-interactive)
if [ -n "$CRON_RUN" ]; then
    log "Running automatic Certbot dry-run renewal..."
    certbot renew --dry-run >> "$LOG_FILE" 2>&1
    echo "SSL certificate added" | mail -s "SSL certificate added" durgeshgupt.dg@gmail.com
    exit 0
fi

# ---------------------------------------------------------------------
# Manual mode
echo "=============================="
echo "     SSL Manager Utility"
echo "=============================="

if [ -n "$EMAIL" ] && [ -n "$DOMAINS" ]; then
    echo "Loaded config:"
    echo "  Email:   $EMAIL"
    echo "  Domains: $DOMAINS"
    echo
    log "Running certbot renew (dry-run)..."
    certbot renew --dry-run | tee -a "$LOG_FILE"

    echo
    read -rp "Do you want to configure or add more domains? (y/n): " CONFIGURE
    if [[ "$CONFIGURE" != "y" ]]; then
        echo "Done. No changes made."
        exit 0
    fi
fi

# ---------------------------------------------------------------------
# Configuration prompt
echo
read -rp "Enter email for SSL registration [${EMAIL:-none}]: " NEW_EMAIL
EMAIL=${NEW_EMAIL:-$EMAIL}

# Domains setup
echo
read -rp "Enter domain(s) (space-separated) [${DOMAINS:-none}]: " NEW_DOMAINS
DOMAINS=${NEW_DOMAINS:-$DOMAINS}

# Save config
cat <<EOF > "$CONF_FILE"
EMAIL="$EMAIL"
DOMAINS="$DOMAINS"
EOF

# ---------------------------------------------------------------------
# Build domain args
DOMAIN_ARGS=""
for D in $DOMAINS; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $D"
done

# ---------------------------------------------------------------------
# Issue/Renew certificate
echo
read -rp "Do you want to issue/renew SSL for these domains now? (y/n): " ISSUE
if [[ "$ISSUE" == "y" ]]; then
    log "Issuing/Renewing SSL for: $DOMAINS"
    certbot certonly --nginx --agree-tos -m "$EMAIL" $DOMAIN_ARGS
else
    log "Skipped issuing SSL."
fi

# ---------------------------------------------------------------------
# Suggest nginx config
echo
echo "=============================="
echo " Suggested NGINX Server Block "
echo "=============================="
for D in $DOMAINS; do
cat <<EOF
server {
    listen 443 ssl;
    server_name $D;

    ssl_certificate /etc/letsencrypt/live/$D/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$D/privkey.pem;

    root /var/www/html;
    index index.html index.htm;
}
EOF
done

log "Configuration complete."

echo
echo "To automate renewal, add this to crontab:"
echo "0 3 * * * CRON_RUN=1 $BASE_DIR/ssl_manager.sh >> $LOG_FILE 2>&1"
echo
