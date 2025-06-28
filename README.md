# DevSecOps Lab - Service Configuration Scripts

This repository contains automated scripts for configuring essential services (DNS, NTP, NFS, HTTPD) and managing SSL certificates in a DevSecOps lab environment.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Scripts](#scripts)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [SSL Certificate Management](#ssl-certificate-management)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)

## 🔍 Overview

The lab includes three main scripts:

1. **`configure-services.sh`** - Automated configuration for DNS, NTP, NFS, and HTTPD services
2. **`manage-certs.sh`** - Let's Encrypt wildcard SSL certificate management using Podman
3. **`dns-hooks.sh`** - DNS challenge automation for GCP Cloud DNS and AWS Route53

## 🛠️ Prerequisites

### System Requirements
- **OS**: Fedora Linux / RHEL 9+ / CentOS Stream 9+
- **User**: Root privileges (sudo access)
- **Network**: Internet connectivity for package installation

### Software Dependencies
- `podman` (for SSL certificate management)
- `gcloud` CLI (for GCP DNS) or `awscli` (for AWS DNS)
- Standard system packages: `bind`, `chrony`, `nfs-utils`, `httpd`, `mod_ssl`

### DNS Provider Setup

#### For GCP Cloud DNS:
```bash
# Install Google Cloud CLI
sudo dnf install -y google-cloud-cli

# Authenticate and configure
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

#### For AWS Route53:
```bash
# Install AWS CLI
sudo dnf install -y awscli

# Configure credentials
aws configure
```

## 📜 Scripts

### 1. configure-services.sh

Comprehensive service configuration script that automates:
- **DNS Server**: BIND9 with forward and reverse zones
- **NTP Server**: Chrony time synchronization
- **NFS Server**: Network file sharing with SELinux context
- **HTTPD Server**: Apache web server with optional SSL support
- **Firewall**: Automatic rule configuration
- **Network**: Auto-detection of IP, CIDR, and gateway

### 2. manage-certs.sh

SSL certificate management using Let's Encrypt:
- Obtains wildcard certificates (`*.domain.com`)
- Uses DNS challenge validation (supports GCP and AWS)
- Runs in Podman containers for isolation
- Automatic renewal via cron (weekly check)
- Integrates with your `.env` configuration

### 3. dns-hooks.sh

DNS challenge automation for certificate validation:
- **GCP Cloud DNS**: Uses `gcloud` CLI
- **AWS Route53**: Uses `aws` CLI
- Automatic DNS record creation/deletion
- Built-in DNS propagation delays
- Error handling and logging

## 🚀 Quick Start

### 1. Configure Environment

Create and customize your `.env` file:

```bash
# Copy example configuration
cp .env.example .env

# Edit configuration
vim .env
```

Sample `.env` configuration:
```bash
# Basic Configuration
HOSTNAME=bastion-vm
DOMAIN=rhlab.kh
TIMEZONE=Asia/Phnom_Penh

# Service Selection
DNS_ENABLED=true
NTP_ENABLED=true
NFS_ENABLED=true
HTTPD_ENABLED=true

# DNS Provider (for SSL certificates)
DNS_PROVIDER=gcp
GCP_PROJECT_ID=my-project
GCP_ZONE_NAME=rhlab-kh

# Or for AWS
# DNS_PROVIDER=aws
# AWS_HOSTED_ZONE_ID=Z1234567890ABC
```

### 2. Configure All Services

```bash
# Configure all services with defaults
sudo ./configure-services.sh --services all

# Configure all services with SSL enabled
sudo ./configure-services.sh --services all --enable-ssl
```

### 3. Set Up SSL Certificates (Optional)

```bash
# Obtain wildcard SSL certificate
sudo ./manage-certs.sh
```

## ⚙️ Configuration

### Environment Variables (.env)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `HOSTNAME` | System hostname | `bastion-vm` | Yes |
| `DOMAIN` | Domain name | `rhlab.kh` | Yes |
| `TIMEZONE` | System timezone | `Asia/Phnom_Penh` | No |
| `DNS_ENABLED` | Enable DNS service | `false` | No |
| `NTP_ENABLED` | Enable NTP service | `false` | No |
| `NFS_ENABLED` | Enable NFS service | `false` | No |
| `HTTPD_ENABLED` | Enable HTTPD service | `false` | No |

### DNS Provider Configuration

#### GCP Cloud DNS:
```bash
DNS_PROVIDER=gcp
GCP_PROJECT_ID=your-project-id
GCP_ZONE_NAME=your-dns-zone-name
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

#### AWS Route53:
```bash
DNS_PROVIDER=aws
AWS_HOSTED_ZONE_ID=your-zone-id
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_DEFAULT_REGION=us-east-1
```

## 🔐 SSL Certificate Management

### Automatic Wildcard Certificate Setup

The `manage-certs.sh` script automatically:

1. **Obtains wildcard certificates** for `*.yourdomain.com`
2. **Uses DNS challenge** (required for wildcard certificates)
3. **Runs in Podman containers** for security and isolation
4. **Sets up automatic renewal** via cron job (weekly check)
5. **Integrates with Apache** (automatic reload on renewal)

### Manual Certificate Management

```bash
# Obtain new certificate
sudo ./manage-certs.sh

# Check certificate status
sudo podman run --rm -v /etc/letsencrypt:/etc/letsencrypt:Z certbot/certbot certificates

# Force renewal (for testing)
sudo podman run --rm -v /etc/letsencrypt:/etc/letsencrypt:Z certbot/certbot renew --force-renewal
```

### Certificate Files Location

- **Certificates**: `/etc/letsencrypt/live/yourdomain.com/`
- **Private Key**: `/etc/letsencrypt/live/yourdomain.com/privkey.pem`
- **Full Chain**: `/etc/letsencrypt/live/yourdomain.com/fullchain.pem`

## 📋 Usage Examples

### Configure Individual Services

```bash
# DNS only
sudo ./configure-services.sh --enable-dns

# NTP and NFS
sudo ./configure-services.sh --services ntp,nfs

# HTTPD with SSL
sudo ./configure-services.sh --enable-httpd --enable-ssl
```

### Custom Configuration

```bash
# Custom domain and timezone
sudo ./configure-services.sh --services all --domain mylab.local --timezone UTC

# Custom NFS export path
sudo ./configure-services.sh --enable-nfs --nfs-export-path /shared

# Custom HTTPD configuration
sudo ./configure-services.sh --enable-httpd --httpd-port 8080 --httpd-document-root /var/www/mysite
```

### Dry Run Testing

```bash
# Test configuration without making changes
sudo ./configure-services.sh --dry-run --services all

# Test SSL certificate setup
sudo ./manage-certs.sh --dry-run
```

### SSL Certificate with Custom Provider

```bash
# Using GCP Cloud DNS
export DNS_PROVIDER=gcp
export GCP_PROJECT_ID=my-project
export GCP_ZONE_NAME=my-zone
sudo ./manage-certs.sh

# Using AWS Route53
export DNS_PROVIDER=aws
export AWS_HOSTED_ZONE_ID=Z1234567890ABC
sudo ./manage-certs.sh
```

## 🔧 Service Management

### Check Service Status

```bash
# Check all configured services
sudo systemctl status named chronyd nfs-server httpd

# Check firewall rules
sudo firewall-cmd --list-all

# Check SSL certificate
sudo openssl x509 -in /etc/letsencrypt/live/yourdomain.com/cert.pem -text -noout
```

### Manual Service Operations

```bash
# Restart services
sudo systemctl restart named chronyd nfs-server httpd

# Reload configurations
sudo systemctl reload named chronyd httpd

# Check logs
sudo journalctl -u named -f
sudo journalctl -u httpd -f
```

## 🐛 Troubleshooting

### Common Issues

#### 1. SSL Certificate DNS Challenge Fails
```bash
# Check DNS provider configuration
./dns-hooks.sh auth yourdomain.com test123

# Verify DNS propagation
dig _acme-challenge.yourdomain.com TXT

# Check provider credentials
gcloud auth list  # For GCP
aws sts get-caller-identity  # For AWS
```

#### 2. Service Configuration Fails
```bash
# Check dry run first
sudo ./configure-services.sh --dry-run --services all

# Verify network detection
ip route get 8.8.8.8

# Check firewall status
sudo firewall-cmd --state
```

#### 3. Podman Container Issues
```bash
# Check Podman status
podman version

# Clean up containers
podman system prune -f

# Check SELinux contexts
ls -Z /etc/letsencrypt/
```

### Log Files

- **Script logs**: Output to stdout/stderr with timestamps
- **System logs**: `journalctl -u service-name`
- **Apache logs**: `/var/log/httpd/error_log`, `/var/log/httpd/access_log`
- **DNS logs**: `/var/log/messages` or `journalctl -u named`

### Network Issues

```bash
# Test network connectivity
ping 8.8.8.8

# Check auto-detected network settings
ip route show default
ip addr show

# Verify DNS resolution
nslookup yourdomain.com
```

## 📚 Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Apache HTTP Server Documentation](https://httpd.apache.org/docs/)
- [BIND9 DNS Server Documentation](https://bind9.readthedocs.io/)
- [Chrony NTP Documentation](https://chrony.tuxfamily.org/documentation.html)
- [Podman Documentation](https://docs.podman.io/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Note**: This is a lab environment setup. For production use, ensure proper security reviews and testing.
