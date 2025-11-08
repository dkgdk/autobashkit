#!/bin/bash

echo "=== Mailutils SMTP Setup (with msmtp) ==="

# Ask for SMTP info
read -p "Enter your SMTP server (e.g., smtp.gmail.com): " SMTP_SERVER
read -p "Enter SMTP port (e.g., 587): " SMTP_PORT
read -p "Enter your email address (SMTP username): " SMTP_USER
read -s -p "Enter your SMTP password: " SMTP_PASS
echo

echo
echo "Installing mailutils and msmtp..."
sudo apt update -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y mailutils msmtp msmtp-mta ca-certificates

echo
echo "Configuring msmtp..."

sudo bash -c "cat > /etc/msmtprc" <<EOF
# msmtp configuration
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile /var/log/msmtp.log

account default
host $SMTP_SERVER
port $SMTP_PORT
from $SMTP_USER
user $SMTP_USER
password $SMTP_PASS
EOF

sudo chmod 777 /etc/msmtprc

echo
echo "Testing configuration..."
echo "This is a test mail from $(hostname)" | mail -s "Mailutils Test via msmtp" "$SMTP_USER"

echo
echo "✅ Mailutils + msmtp setup complete!"
echo "Test email sent to: $SMTP_USER"
echo
echo "You can now send mail using:"
echo "echo 'hello world' | mail -s 'subject' someone@example.com"
