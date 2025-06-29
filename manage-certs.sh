#!/bin/bash

# ==== LETSENCRYPT WILDCARD SSL CERTIFICATE MANAGER ====
# This script obtains and automatically renews wildcard SSL certificates
# using Let's Encrypt and Podman containers with DNS challenge validation.
#
# PREREQUISITES:
# 1. Domain configured in .env file
# 2. DNS provider configuration (GCP or AWS)
# 3. Podman installed
# 4. dns-hooks.sh script in the same directory
#
# SETUP:
# 1. Configure your .env file with DOMAIN and DNS provider settings
# 2. Ensure dns-hooks.sh is executable: chmod +x dns-hooks.sh
# 3. Run this script: sudo ./manage-certs.sh

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNS_HOOKS_SCRIPT="$SCRIPT_DIR/dns-hooks.sh"

# Load domain from .env
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE!"
    exit 1
fi

# Check if DOMAIN is set
if [[ -z "$DOMAIN" ]]; then
    echo "Error: DOMAIN not set in .env!"
    exit 1
fi

# Check if DNS hooks script exists
if [[ ! -f "$DNS_HOOKS_SCRIPT" ]]; then
    echo "Error: DNS hooks script not found at $DNS_HOOKS_SCRIPT!"
    exit 1
fi

# Make DNS hooks script executable
chmod +x "$DNS_HOOKS_SCRIPT"

echo "Starting Let's Encrypt wildcard certificate management for domain: $DOMAIN"

# Ensure necessary directories exist
for dir in "/etc/letsencrypt" "/var/lib/letsencrypt"; do
    if [[ ! -d "$dir" ]]; then
        echo "Creating directory $dir"
        sudo mkdir -p "$dir"
        sudo chown $USER:$(id -gn $USER) "$dir"
    fi
    
    # Ensure correct SELinux context
    sudo chcon -R system_u:object_r:etc_t:s0 "$dir"
    sudo restorecon -Rv "$dir"

    # Ensure correct permissions
    sudo chmod 755 "$dir"

done

# Pull the Certbot container image
echo "Pulling Certbot container image..."
podman pull docker.io/certbot/certbot

# Create wrapper scripts for DNS hooks that can be called from the container
cat > /tmp/dns-auth-wrapper.sh << 'EOF'
#!/bin/bash
export CERTBOT_DOMAIN="$CERTBOT_DOMAIN"
export CERTBOT_VALIDATION="$CERTBOT_VALIDATION"
/dns-hooks/dns-hooks.sh auth "$CERTBOT_DOMAIN" "$CERTBOT_VALIDATION"
EOF

cat > /tmp/dns-cleanup-wrapper.sh << 'EOF'
#!/bin/bash
export CERTBOT_DOMAIN="$CERTBOT_DOMAIN"
export CERTBOT_VALIDATION="$CERTBOT_VALIDATION"
/dns-hooks/dns-hooks.sh cleanup "$CERTBOT_DOMAIN" "$CERTBOT_VALIDATION"
EOF

chmod +x /tmp/dns-auth-wrapper.sh /tmp/dns-cleanup-wrapper.sh

echo "Obtaining wildcard certificate for *.$DOMAIN using DNS challenge..."

# Obtain wildcard certificate using DNS challenge
podman run --rm --name certbot \
  -v "/etc/letsencrypt:/etc/letsencrypt:Z" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt:Z" \
  -v "$SCRIPT_DIR:/dns-hooks:Z" \
  -v "/tmp/dns-auth-wrapper.sh:/usr/local/bin/dns-auth-wrapper.sh:Z" \
  -v "/tmp/dns-cleanup-wrapper.sh:/usr/local/bin/dns-cleanup-wrapper.sh:Z" \
  --env-file="$ENV_FILE" \
  certbot/certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d "*.$DOMAIN" \
  --agree-tos \
  --manual-public-ip-logging-ok \
  --register-unsafely-without-email \
  --manual-auth-hook "/usr/local/bin/dns-auth-wrapper.sh" \
  --manual-cleanup-hook "/usr/local/bin/dns-cleanup-wrapper.sh"

echo "Certificate obtained successfully!"

# Define paths for copying certificates
LE_CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
TARGET_CERT_DIR="/etc/ssl/certs"
TARGET_KEY_DIR="/etc/ssl/private"

# Ensure target directories exist
sudo mkdir -p "$TARGET_CERT_DIR" "$TARGET_KEY_DIR"

# Copy Let's Encrypt certificates to standard locations
if [ -d "$LE_CERT_DIR" ]; then
    echo "Copying Let's Encrypt certificates to standard locations..."
    sudo cp "$LE_CERT_DIR/fullchain.pem" "$TARGET_CERT_DIR/httpd.crt"
    sudo cp "$LE_CERT_DIR/privkey.pem" "$TARGET_KEY_DIR/httpd.key"
    
    # Set proper permissions
    sudo chmod 644 "$TARGET_CERT_DIR/httpd.crt"
    sudo chmod 600 "$TARGET_KEY_DIR/httpd.key"
    sudo chown root:root "$TARGET_CERT_DIR/httpd.crt" "$TARGET_KEY_DIR/httpd.key"
    
    echo "Certificates copied and permissions set successfully!"
else
    echo "Warning: Let's Encrypt certificate directory not found at $LE_CERT_DIR"
fi

# Create certificate copy script for renewals
CERT_COPY_SCRIPT="/usr/local/bin/copy-letsencrypt-certs.sh"
sudo tee "$CERT_COPY_SCRIPT" > /dev/null << EOF
#!/bin/bash
# Script to copy Let's Encrypt certificates to standard locations
DOMAIN="$DOMAIN"
LE_CERT_DIR="/etc/letsencrypt/live/\$DOMAIN"
TARGET_CERT_DIR="/etc/ssl/certs"
TARGET_KEY_DIR="/etc/ssl/private"

if [ -d "\$LE_CERT_DIR" ]; then
    cp "\$LE_CERT_DIR/fullchain.pem" "\$TARGET_CERT_DIR/httpd.crt"
    cp "\$LE_CERT_DIR/privkey.pem" "\$TARGET_KEY_DIR/httpd.key"
    chmod 644 "\$TARGET_CERT_DIR/httpd.crt"
    chmod 600 "\$TARGET_KEY_DIR/httpd.key"
    chown root:root "\$TARGET_CERT_DIR/httpd.crt" "\$TARGET_KEY_DIR/httpd.key"
    systemctl reload httpd
fi
EOF

sudo chmod +x "$CERT_COPY_SCRIPT"

# Create cron job for certificate renewal with certificate copying
CRON_JOB="0 0 * * 0 podman run --rm --name certbot-renew -v /etc/letsencrypt:/etc/letsencrypt:Z -v /var/lib/letsencrypt:/var/lib/letsencrypt:Z certbot/certbot renew --quiet --renew-hook '$CERT_COPY_SCRIPT'"
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "Wildcard certificate for *.$DOMAIN obtained, copied to standard locations, and renewal job added to cron."
