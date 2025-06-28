## ABA workshop - Script to configure requested services on bastion host
# Service Configuration Script

![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-RHEL%2FCentOS-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A comprehensive automation script for configuring DNS, NTP, NFS, and HTTPD services on RHEL/CentOS systems with automatic network detection and intelligent configuration management.

## 📦 Additional Scripts

This documentation also covers:
- **`manage-certs.sh`** - Let's Encrypt wildcard SSL certificate management using Podman
- **`dns-hooks.sh`** - DNS challenge automation for GCP Cloud DNS and AWS Route53

## 🚀 Features

- **Automatic Network Detection**: Automatically detects primary IP, network CIDR, and gateway
- **Multi-Service Support**: Configure DNS (BIND), NTP (Chrony), and NFS services
- **Smart Configuration**: Uses 'auto' values that automatically resolve to detected network settings
- **Configuration Backup**: Automatically backs up existing configuration files
- **Dry Run Mode**: Preview changes without making modifications
- **Environment File Support**: Load configuration from `.env` files
- **Firewall Integration**: Automatically configures firewall rules
- **SELinux Support**: Proper SELinux context setup for NFS exports
- **Comprehensive Logging**: Detailed logging with multiple levels (DEBUG, INFO, WARN, ERROR)

## 📋 Prerequisites

- RHEL/CentOS/Fedora Linux system
- Root privileges (sudo access)
- Active network connection

### Required Packages
The script automatically installs required packages:
- `bind` and `bind-utils` (for DNS)
- `chrony` (for NTP)
- `nfs-utils` (for NFS)

## 🔧 Installation

1. Clone or download the script:
```bash
git clone <repository-url>
cd devsecops-lab
chmod +x configure-services.sh
```

2. (Optional) Create and customize the `.env` file:
```bash
cp .env.example .env
vim .env
```

## 📖 Usage

### Basic Usage

```bash
# Configure all services with auto-detected network settings
sudo ./configure-services.sh --services all

# Configure specific services
sudo ./configure-services.sh --services dns,ntp

# Dry run to preview changes
sudo ./configure-services.sh --dry-run --services all
```

### Advanced Usage

```bash
# Custom domain and timezone
sudo ./configure-services.sh --services all --domain mylab.local --timezone Asia/Bangkok

# Custom NFS export path
sudo ./configure-services.sh --enable-nfs --nfs-export-path /shared

# Using custom environment file
sudo ./configure-services.sh --env-file /path/to/custom.env --services all

# Configure with custom DNS forwarders
sudo ./configure-services.sh --enable-dns --dns-forwarders "1.1.1.1,8.8.8.8"
```

## ⚙️ Configuration Options

### Command Line Arguments

#### General Options
| Option | Description | Default |
|--------|-------------|---------|
| `--help` | Show help message | - |
| `--version` | Show version information | - |
| `--dry-run` | Preview changes without applying | false |
| `--no-backup` | Don't backup existing configs | false |
| `--log-level LEVEL` | Set logging level (DEBUG/INFO/WARN/ERROR) | INFO |
| `--env-file FILE` | Load configuration from file | .env |
| `--services LIST` | Services to configure (dns,ntp,nfs,all) | - |

#### Network Configuration
| Option | Description | Default |
|--------|-------------|---------|
| `--hostname NAME` | Set system hostname | current hostname |
| `--domain NAME` | Domain name | rhlab.kh |
| `--timezone TZ` | System timezone | Asia/Phnom_Penh |

> **Note**: Primary IP, Network CIDR, and Gateway are automatically detected

#### DNS Configuration
| Option | Description | Default |
|--------|-------------|---------|
| `--enable-dns` | Enable DNS server | false |
| `--dns-forwarders LIST` | DNS forwarders (comma-separated) | auto,8.8.8.8,1.1.1.1 |
| `--dns-allow-query RANGE` | Allow queries from | auto |
| `--dns-allow-recursion RANGE` | Allow recursion from | auto |

#### NTP Configuration
| Option | Description | Default |
|--------|-------------|---------|
| `--enable-ntp` | Enable NTP server | false |
| `--ntp-servers LIST` | NTP servers (comma-separated) | pool.ntp.org,time.cloudflare.com |
| `--ntp-allow-networks LIST` | Networks allowed to sync | auto |
| `--no-iburst` | Disable iburst option | false |

#### NFS Configuration
| Option | Description | Default |
|--------|-------------|---------|
| `--enable-nfs` | Enable NFS server | false |
| `--nfs-export-path PATH` | NFS export directory | /data |
| `--nfs-exports LIST` | Custom export definitions | - |
| `--nfs-export-options OPTS` | Default export options | rw,sync,no_subtree_check |
| `--nfs-allowed-networks LIST` | Networks allowed to mount | auto |

#### HTTPD Configuration
| Option | Description | Default |
|--------|-------------|---------|
| `--enable-httpd` | Enable Apache HTTP server | false |
| `--httpd-document-root PATH` | Web document root directory | /var/www/html |
| `--httpd-server-name NAME` | Server name (auto=hostname.domain) | auto |
| `--httpd-port PORT` | HTTP port | 80 |
| `--enable-ssl` | Enable SSL/TLS support | false |
| `--httpd-ssl-port PORT` | HTTPS port | 443 |
| `--httpd-ssl-cert PATH` | SSL certificate path | /etc/ssl/certs/httpd.crt |
| `--httpd-ssl-key PATH` | SSL private key path | /etc/ssl/private/httpd.key |
| `--httpd-custom-config TEXT` | Additional Apache configuration | - |

### Environment File (.env)

Create a `.env` file for persistent configuration:

```bash
# ==== BASIC CONFIGURATION ====
HOSTNAME=bastion-vm
DOMAIN=rhlab.kh
TIMEZONE=Asia/Phnom_Penh

# ==== SERVICE SELECTION ====
DNS_ENABLED=true
NTP_ENABLED=true
NFS_ENABLED=true

# ==== DNS SERVER CONFIGURATION ====
DNS_FORWARDERS=auto,8.8.8.8,1.1.1.1
DNS_ALLOW_QUERY=auto
DNS_ALLOW_RECURSION=auto

# ==== NTP SERVER CONFIGURATION ====
NTP_SERVERS=pool.ntp.org,time.cloudflare.com,time.google.com
NTP_ALLOW_NETWORKS=auto

# ==== NFS SERVER CONFIGURATION ====
NFS_EXPORT_PATH=/data
NFS_EXPORT_OPTIONS=rw,sync,no_subtree_check,no_root_squash
NFS_ALLOWED_NETWORKS=auto

# ==== ADVANCED OPTIONS ====
BACKUP_CONFIG=true
FIREWALL_ENABLED=true
FIREWALL_ZONE=public
LOG_LEVEL=INFO
```

## 🌐 Network Auto-Detection

The script automatically detects:
- **Primary IP**: The main IP address of the system
- **Network CIDR**: The network range (e.g., 192.168.1.0/24)
- **Gateway IP**: The default gateway

You can use `auto` in configuration to leverage these detected values:
- `DNS_FORWARDERS=auto,8.8.8.8` → Uses gateway IP as first forwarder
- `DNS_ALLOW_QUERY=auto` → Allows queries from detected network
- `NFS_ALLOWED_NETWORKS=auto` → Allows NFS access from detected network

## 📁 Services Overview

### DNS Server (BIND)
- Configures authoritative DNS for the specified domain
- Creates forward and reverse DNS zones
- Sets up DNS forwardering to upstream servers
- Automatic zone file generation with proper SOA records

### NTP Server (Chrony)
- Synchronizes with upstream NTP servers
- Allows network clients to sync time
- Configures drift compensation and logging

### NFS Server
- Creates and exports network file shares
- Sets proper permissions and SELinux contexts
- Supports custom export configurations
- Automatic firewall rule configuration

## 🛡️ Security Features

- **Firewall Integration**: Automatically opens required ports
- **SELinux Support**: Proper contexts for NFS exports
- **Network Restrictions**: Services limited to specified networks
- **Configuration Backup**: All changes are backed up with timestamps

## 📊 Examples

### Example 1: Basic Lab Setup
```bash
# Set up a complete lab environment
sudo ./configure-services.sh --services all \
  --hostname lab-server \
  --domain lab.local \
  --timezone America/New_York
```

### Example 2: NFS-Only Server
```bash
# Configure only NFS with custom export
sudo ./configure-services.sh --enable-nfs \
  --nfs-export-path /shared \
  --nfs-export-options "rw,sync,no_root_squash"
```

### Example 3: DNS with Custom Forwarders
```bash
# DNS server with specific upstream servers
sudo ./configure-services.sh --enable-dns \
  --domain company.internal \
  --dns-forwarders "192.168.1.1,1.1.1.1,8.8.8.8"
```

### Example 4: Production-Ready Setup
```bash
# Complete setup with custom configuration
sudo ./configure-services.sh --services all \
  --hostname bastion \
  --domain prod.local \
  --nfs-export-path /data \
  --ntp-servers "ntp1.company.com,ntp2.company.com" \
  --firewall-zone public
```

## 🔍 Troubleshooting

### Common Issues

1. **Network Detection Fails**
   ```bash
   # Check network configuration
   ip route show
   ip addr show
   ```

2. **Permission Denied**
   ```bash
   # Ensure running as root
   sudo ./configure-services.sh --services all
   ```

3. **Service Start Failures**
   ```bash
   # Check service status
   systemctl status named chronyd nfs-server
   
   # Check logs
   journalctl -u named -f
   journalctl -u chronyd -f
   journalctl -u nfs-server -f
   ```

4. **Firewall Issues**
   ```bash
   # Check firewall status
   firewall-cmd --list-all
   
   # Manual firewall configuration
   firewall-cmd --permanent --add-service=dns
   firewall-cmd --permanent --add-service=ntp
   firewall-cmd --permanent --add-service=nfs
   firewall-cmd --reload
   ```

### Log Analysis
```bash
# View script logs with different levels
./configure-services.sh --log-level DEBUG --dry-run --services all

# Check system logs
tail -f /var/log/messages
journalctl -f
```

## 🧪 Testing

### DNS Testing
```bash
# Test DNS resolution
nslookup $(hostname) localhost
dig @localhost $(hostname)
```

### NTP Testing
```bash
# Check NTP status
chrony sources -v
timedatectl status
```

### NFS Testing
```bash
# Test NFS mount
showmount -e localhost
mkdir /tmp/nfs-test
mount -t nfs localhost:/data /tmp/nfs-test
```

## 📝 File Locations

- **Configuration Files**:
  - DNS: `/etc/named.conf`, `/var/named/*.zone`
  - NTP: `/etc/chrony.conf`
  - NFS: `/etc/exports`

- **Service Files**:
  - DNS zones: `/var/named/`
  - NFS exports: `/data/` (or custom path)

- **Logs**:
  - Script logs: stdout/stderr
  - Service logs: `journalctl -u <service-name>`

- **Backups**:
  - Format: `<original-file>.backup.YYYYMMDD-HHMMSS`
  - Location: Same directory as original file

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section
2. Review service logs
3. Run with `--dry-run` and `--log-level DEBUG`
4. Create an issue with full logs and configuration

## Extra configuration for Single Node Openshift 
After running the script you will need to create dns records in the file /var/named/<your domain>.zone for Single Node Opensshift, for example:
```
cat > /var/named/rhlab.kh.zone <<ZONE
@   IN SOA   ns.rhlab.kh. admin.rhlab.kh. (
            2025041901 ; serial
            3600       ; refresh
            900        ; retry
            604800     ; expire
            86400 )    ; minimum
    IN NS    ns.rhlab.kh.
@  IN A     192.168.44.10
ns  IN A     192.168.44.10
bastion IN A     192.168.44.10
api.demo IN A     192.168.44.11
*.apps.demo IN A     192.168.44.11

ZONE
```

and the reverse dns file:
```
cat > /var/named/40.168.192.in-addr.arpa.rev <<REV
@   IN SOA   ns.rhlab.kh. admin.rhlab.kh. (
            2025041901 ; serial
            3600
            900
            604800
            86400 )
    IN NS    ns.rhlab.kh.
10    IN PTR   bastion.rhlab.kh.
11    IN PTR   api.demo.rhlab.kh.
12.rhlab.kh.
REV
```

---

**Version**: 1.1.0  
**Last Updated**: June 2025  
**Compatibility**: RHEL 8+, CentOS 8+, Fedora 30+
