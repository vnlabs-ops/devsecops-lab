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

# Create cron job for certificate renewal
CRON_JOB="0 0 * * 0 podman run --rm --name certbot-renew -v /etc/letsencrypt:/etc/letsencrypt:Z -v /var/lib/letsencrypt:/var/lib/letsencrypt:Z certbot/certbot renew --quiet --renew-hook 'systemctl reload httpd'"
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "Wildcard certificate for *.$DOMAIN obtained and renewal job added to cron."
