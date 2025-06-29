#!/bin/bash
set +e

# ==== SCRIPT INFO ====
SCRIPT_NAME="Service Configuration Script"
SCRIPT_VERSION="1.1.0"
SCRIPT_DESC="Automates DNS, NTP, and NFS configuration on RHEL/CentOS systems"

# ==== DEFAULTS ====
# General
HOSTNAME=$(hostname)
DOMAIN="rhlab.kh"
TIMEZONE="Asia/Phnom_Penh"
LOG_LEVEL="INFO"
DRY_RUN=false
BACKUP_CONFIG=true
SERVICES_TO_CONFIGURE=""

# Network (auto-detected)
PRIMARY_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || echo "")
NETWORK_CIDR=$(ip route | grep "$PRIMARY_IP" | grep 'scope link' | awk '{print $1}' | head -1 2>/dev/null || echo "")
GATEWAY_IP=$(ip route show default | awk '{print $3}' | head -1 2>/dev/null || echo "")

# DNS Configuration
DNS_ENABLED=false
DNS_FORWARDERS="auto,8.8.8.8,1.1.1.1"
DNS_ALLOW_QUERY="auto"
DNS_ALLOW_RECURSION="auto"
DNS_ZONE_FILE=""
DNS_REVERSE_ZONE=""
DNS_SERIAL=""

# NTP Configuration
NTP_ENABLED=false
NTP_SERVERS="pool.ntp.org,time.cloudflare.com,time.google.com"
NTP_ALLOW_NETWORKS="auto"
NTP_IBURST=true
NTP_PREFER_SERVER=""

# NFS Configuration
NFS_ENABLED=false
NFS_EXPORTS=""
NFS_EXPORT_PATH="/data"
NFS_EXPORT_OPTIONS="rw,sync,no_subtree_check,no_root_squash"
NFS_ALLOWED_NETWORKS="auto"

# HTTPD Configuration
HTTPD_ENABLED=false
HTTPD_DOCUMENT_ROOT="/var/www/html"
HTTPD_SERVER_NAME="auto"
HTTPD_PORT="80"
HTTPD_SSL_ENABLED=false
HTTPD_SSL_PORT="443"
HTTPD_SSL_CERT_PATH="/etc/ssl/certs/httpd.crt"
HTTPD_SSL_KEY_PATH="/etc/ssl/private/httpd.key"
HTTPD_CUSTOM_CONFIG=""

# Firewall
FIREWALL_ENABLED=true
FIREWALL_ZONE="public"

# ==== UTILITY FUNCTIONS ====
function log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR) echo "🔴 [$timestamp] ERROR: $message" >&2 ;;
        WARN)  echo "🟡 [$timestamp] WARN:  $message" >&2 ;;
        INFO)  echo "🔵 [$timestamp] INFO:  $message" ;;
        DEBUG) [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "🔍 [$timestamp] DEBUG: $message" ;;
        SUCCESS) echo "✅ [$timestamp] SUCCESS: $message" ;;
    esac
}

function print_usage() {
    cat <<USAGE
$SCRIPT_NAME v$SCRIPT_VERSION
$SCRIPT_DESC

Usage: $0 [OPTIONS]

GENERAL OPTIONS:
  --help                       Show this help message
  --version                    Show version information
  --dry-run                    Show what would be done without making changes
  --no-backup                  Don't backup existing configuration files
  --log-level LEVEL            Set log level (DEBUG, INFO, WARN, ERROR) [default: INFO]
  --env-file FILE              Load configuration from .env file [default: .env]
  --services LIST              Comma-separated list of services to configure (dns,ntp,nfs,httpd,all)

NETWORK CONFIGURATION:
  --hostname NAME              Set system hostname [default: current hostname]
  --domain NAME                Domain name [default: rhlab.kh]
  --timezone TZ                System timezone [default: Asia/Phnom_Penh]

NOTE: Primary IP, Network CIDR, and Gateway are automatically detected from the system

DNS CONFIGURATION:
  --enable-dns                 Enable DNS server configuration
  --dns-forwarders LIST        Comma-separated DNS forwarders [default: auto,8.8.8.8,1.1.1.1]
  --dns-allow-query RANGE      Allow queries from (auto=current network) [default: auto]
  --dns-allow-recursion RANGE  Allow recursion from [default: auto]
  --dns-zone-file FILE         Custom zone file to use
  --dns-reverse-zone ZONE      Reverse zone name
  --dns-serial SERIAL          DNS zone serial number

NTP CONFIGURATION:
  --enable-ntp                 Enable NTP server configuration
  --ntp-servers LIST           Comma-separated NTP servers [default: pool.ntp.org,time.cloudflare.com]
  --ntp-allow-networks LIST    Networks allowed to sync (auto=current network) [default: auto]
  --ntp-prefer-server SERVER   Preferred NTP server
  --no-iburst                  Disable iburst option

NFS CONFIGURATION:
  --enable-nfs                 Enable NFS server configuration
  --nfs-export-path PATH       NFS export directory [default: /data]
  --nfs-exports LIST           Comma-separated export definitions (path:options:networks)
  --nfs-export-options OPTS    Default export options [default: rw,sync,no_subtree_check]
  --nfs-allowed-networks LIST  Networks allowed to mount (auto=current network) [default: auto]

HTTPD CONFIGURATION:
  --enable-httpd               Enable Apache HTTP server configuration
  --httpd-document-root PATH   Web document root directory [default: /var/www/html]
  --httpd-server-name NAME     Server name (auto=hostname.domain) [default: auto]
  --httpd-port PORT            HTTP port [default: 80]
  --enable-ssl                 Enable SSL/TLS support
  --httpd-ssl-port PORT        HTTPS port [default: 443]
  --httpd-ssl-cert PATH        SSL certificate path [default: /etc/ssl/certs/httpd.crt]
  --httpd-ssl-key PATH         SSL private key path [default: /etc/ssl/private/httpd.key]
  --httpd-custom-config TEXT   Additional Apache configuration directives

FIREWALL CONFIGURATION:
  --disable-firewall           Don't configure firewall rules
  --firewall-zone ZONE         Firewall zone to use [default: public]

EXAMPLES:
  # Configure all services with defaults (network auto-detected)
  $0 --services all

  # Configure only DNS and NTP
  $0 --services dns,ntp

  # Configure NFS with custom path
  $0 --enable-nfs --nfs-export-path /shared

  # Use custom domain and timezone
  $0 --services all --domain mylab.kh --timezone Asia/Bangkok

  # Dry run to see what would be configured
  $0 --dry-run --services all

.ENV FILE FORMAT:
  # Network Configuration (IP/CIDR/Gateway auto-detected)
  HOSTNAME=bastion-vm
  DOMAIN=rhlab.kh
  TIMEZONE=Asia/Phnom_Penh

  # DNS Configuration
  DNS_ENABLED=true
  DNS_FORWARDERS=auto,8.8.8.8,1.1.1.1
  DNS_ALLOW_QUERY=auto
  DNS_ALLOW_RECURSION=auto

  # NTP Configuration
  NTP_ENABLED=true
  NTP_SERVERS=pool.ntp.org,time.cloudflare.com
  NTP_ALLOW_NETWORKS=auto

  # NFS Configuration (/data with SELinux context)
  NFS_ENABLED=true
  NFS_EXPORT_PATH=/data
  NFS_ALLOWED_NETWORKS=auto

  # General
  BACKUP_CONFIG=true
  FIREWALL_ENABLED=true
  LOG_LEVEL=INFO

NOTE: Use 'auto' in configuration to use auto-detected network values
USAGE
}

function load_env_file() {
    local env_file="$1"
    
    if [[ -f "$env_file" ]]; then
        log INFO "Loading configuration from $env_file"
        
        # Validate .env file format and load variables
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Validate format (KEY=VALUE)
            if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.*$ ]]; then
                export "$line"
                log DEBUG "Loaded: $line"
            else
                log WARN "Skipping invalid line in $env_file: $line"
            fi
        done < "$env_file"
        
        log SUCCESS "Environment file loaded successfully"
    else
        log DEBUG "Environment file not found: $env_file"
    fi
}

function validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            [[ "$i" -gt 255 ]] && return 1
        done
        return 0
    fi
    return 1
}

function validate_cidr() {
    local cidr="$1"
    if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local ip="${cidr%/*}"
        local prefix="${cidr#*/}"
        validate_ip "$ip" && [[ "$prefix" -ge 0 && "$prefix" -le 32 ]]
    else
        return 1
    fi
}

function backup_file() {
    local file="$1"
    
    if [[ "$BACKUP_CONFIG" == true && -f "$file" ]]; then
        local backup_file="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        if [[ "$DRY_RUN" == true ]]; then
            log INFO "Would backup $file to $backup_file"
        else
            cp "$file" "$backup_file"
            log SUCCESS "Backed up $file to $backup_file"
        fi
    fi
}

function execute_command() {
    local description="$1"
    shift
    local command="$*"
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would execute: $description"
        log DEBUG "Command: $command"
    else
        log INFO "Executing: $description"
        if eval "$command"; then
            log SUCCESS "$description completed"
        else
            log ERROR "$description failed"
            return 1
        fi
    fi
}

# ==== CONFIGURATION FUNCTIONS ====
function configure_hostname() {
    if [[ -n "$HOSTNAME" ]]; then
        execute_command "Setting hostname to $HOSTNAME" "hostnamectl set-hostname '$HOSTNAME'"
        
        # Update /etc/hosts
        if [[ -n "$PRIMARY_IP" ]]; then
            local hosts_entry="$PRIMARY_IP $HOSTNAME.$DOMAIN $HOSTNAME"
            execute_command "Adding hosts entry" "echo '$hosts_entry' >> /etc/hosts"
        fi
    fi
}

function configure_timezone() {
    if [[ -n "$TIMEZONE" ]]; then
        execute_command "Setting timezone to $TIMEZONE" "timedatectl set-timezone '$TIMEZONE'"
    fi
}

function install_packages() {
    local packages=()
    
    [[ "$DNS_ENABLED" == true ]] && packages+=(bind bind-utils)
    [[ "$NTP_ENABLED" == true ]] && packages+=(chrony)
    [[ "$NFS_ENABLED" == true ]] && packages+=(nfs-utils)
    [[ "$HTTPD_ENABLED" == true ]] && packages+=(httpd mod_ssl)
    
    if [[ ${#packages[@]} -gt 0 ]]; then
        execute_command "Installing packages: ${packages[*]}" "dnf install -y ${packages[*]}"
    fi
}

function configure_dns() {
    [[ "$DNS_ENABLED" != true ]] && return
    
    log INFO "Configuring DNS server..."
    log INFO "Auto-detected network: $NETWORK_CIDR"
    log INFO "Using primary IP: $PRIMARY_IP"
    
    local named_conf="/etc/named.conf"
    backup_file "$named_conf"
    
    # Process 'auto' values in DNS configuration
    if [[ "$DNS_FORWARDERS" == *"auto"* ]]; then
        DNS_FORWARDERS=$(echo "$DNS_FORWARDERS" | sed "s/auto/$GATEWAY_IP/g")
    fi
    
    if [[ "$DNS_ALLOW_QUERY" == "auto" ]]; then
        # Convert CIDR to BIND-compatible format
        if [[ "$NETWORK_CIDR" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
            DNS_ALLOW_QUERY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        else
            DNS_ALLOW_QUERY="$NETWORK_CIDR"
        fi
    fi
    
    if [[ "$DNS_ALLOW_RECURSION" == "auto" ]]; then
        # Convert CIDR to BIND-compatible format
        if [[ "$NETWORK_CIDR" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
            DNS_ALLOW_RECURSION="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        else
            DNS_ALLOW_RECURSION="$NETWORK_CIDR"
        fi
    fi
    
    # Generate reverse zone if not provided
    if [[ -z "$DNS_REVERSE_ZONE" && -n "$PRIMARY_IP" ]]; then
        IFS='.' read -ra IP_PARTS <<< "$PRIMARY_IP"
        DNS_REVERSE_ZONE="${IP_PARTS[2]}.${IP_PARTS[1]}.${IP_PARTS[0]}.in-addr.arpa"
    fi
    
    # Generate serial if not provided
    [[ -z "$DNS_SERIAL" ]] && DNS_SERIAL=$(date +%Y%m%d%H)
    
    local named_config="acl trusted {
    localhost;
    localnets;
    ${DNS_ALLOW_QUERY};
};

options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { ::1; };
    directory \"/var/named\";
    dump-file \"/var/named/data/cache_dump.db\";
    statistics-file \"/var/named/data/named_stats.txt\";
    memstatistics-file \"/var/named/data/named_mem_stats.txt\";
    allow-query { trusted; };
    allow-query-cache { trusted; };
    allow-recursion { trusted; };
    forwarders { $(echo $DNS_FORWARDERS | sed 's/,/; /g'); };
    recursion yes;
    dnssec-validation no;
    auth-nxdomain no;
    notify explicit;
};

logging {
    channel default_debug {
        file \"data/named.run\";
        severity dynamic;
    };
};

zone \".\" IN {
    type hint;
    file \"named.ca\";
};

include \"/etc/named.rfc1912.zones\";
include \"/etc/named.root.key\";

zone \"${DOMAIN}\" IN {
    type master;
    file \"${DOMAIN}.zone\";
    allow-update { none; };
};

zone \"${DNS_REVERSE_ZONE}\" IN {
    type master;
    file \"${DNS_REVERSE_ZONE}.rev\";
    allow-update { none; };
};"
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would write DNS configuration to $named_conf"
    else
        echo "$named_config" > "$named_conf"
        log SUCCESS "DNS configuration written to $named_conf"
    fi
    
    # Create zone files
    create_dns_zone_files
    
    execute_command "Enabling and starting named service" "systemctl enable --now named"
}

function create_dns_zone_files() {
    local zone_file="/var/named/${DOMAIN}.zone"
    local reverse_file="/var/named/${DNS_REVERSE_ZONE}.rev"
    
    # Forward zone
    local forward_zone="\$TTL 86400
@   IN  SOA ns.${DOMAIN}. admin.${DOMAIN}. (
        ${DNS_SERIAL}  ; serial
        3600           ; refresh
        900            ; retry
        604800         ; expire
        86400 )        ; minimum

    IN  NS  ns.${DOMAIN}.

@           IN  A   ${PRIMARY_IP}
ns          IN  A   ${PRIMARY_IP}
${HOSTNAME} IN  A   ${PRIMARY_IP}"
    
    # Reverse zone
    local last_octet="${PRIMARY_IP##*.}"
    local reverse_zone="\$TTL 86400
@   IN  SOA ns.${DOMAIN}. admin.${DOMAIN}. (
        ${DNS_SERIAL}  ; serial
        3600           ; refresh
        900            ; retry
        604800         ; expire
        86400 )        ; minimum

    IN  NS  ns.${DOMAIN}.

${last_octet}   IN  PTR ${HOSTNAME}.${DOMAIN}."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would create zone files: $zone_file, $reverse_file"
    else
        echo "$forward_zone" > "$zone_file"
        echo "$reverse_zone" > "$reverse_file"
        chown named:named "$zone_file" "$reverse_file"
        log SUCCESS "DNS zone files created"
    fi
}

function configure_ntp() {
    [[ "$NTP_ENABLED" != true ]] && return
    
    log INFO "Configuring NTP server..."
    log INFO "Using network: $NETWORK_CIDR"
    
    # Process 'auto' values in NTP configuration
    if [[ "$NTP_ALLOW_NETWORKS" == "auto" ]]; then
        NTP_ALLOW_NETWORKS="$NETWORK_CIDR"
    fi
    
    local chrony_conf="/etc/chrony.conf"
    backup_file "$chrony_conf"
    
    local chrony_config="# Generated by $SCRIPT_NAME
"
    
    # Add NTP servers
    IFS=',' read -ra SERVERS <<< "$NTP_SERVERS"
    for server in "${SERVERS[@]}"; do
        server=$(echo "$server" | xargs)  # trim whitespace
        chrony_config+="server $server"
        [[ "$NTP_IBURST" == true ]] && chrony_config+=" iburst"
        [[ "$server" == "$NTP_PREFER_SERVER" ]] && chrony_config+=" prefer"
        chrony_config+=$'\n'
    done
    
    chrony_config+="
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
"
    
    # Allow networks to sync
    if [[ -n "$NTP_ALLOW_NETWORKS" ]]; then
        IFS=',' read -ra NETWORKS <<< "$NTP_ALLOW_NETWORKS"
        for network in "${NETWORKS[@]}"; do
            network=$(echo "$network" | xargs)
            chrony_config+="allow $network"$'\n'
        done
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would write NTP configuration to $chrony_conf"
    else
        echo "$chrony_config" > "$chrony_conf"
        log SUCCESS "NTP configuration written to $chrony_conf"
    fi
    
    execute_command "Enabling and starting chronyd service" "systemctl enable --now chronyd"
}

function configure_nfs() {
    [[ "$NFS_ENABLED" != true ]] && return
    
    log INFO "Configuring NFS server..."
    
    # Create export directory with proper permissions and SELinux context
    if [[ -n "$NFS_EXPORT_PATH" ]]; then
        execute_command "Creating NFS export directory $NFS_EXPORT_PATH" "mkdir -p '$NFS_EXPORT_PATH'"
        execute_command "Setting NFS directory permissions" "chmod 755 '$NFS_EXPORT_PATH'"
        execute_command "Setting NFS directory ownership" "chown nobody:nobody '$NFS_EXPORT_PATH'"
        
        # Set SELinux context for NFS
        if command -v semanage &>/dev/null && command -v restorecon &>/dev/null; then
            execute_command "Setting SELinux context for NFS export" "semanage fcontext -a -t public_content_rw_t '$NFS_EXPORT_PATH(/.*)?'"
            execute_command "Applying SELinux context" "restorecon -Rv '$NFS_EXPORT_PATH'"
        else
            log WARN "SELinux tools not available, skipping SELinux context setup"
        fi
    fi
    
    local exports_file="/etc/exports"
    backup_file "$exports_file"
    
    local exports_config="# Generated by $SCRIPT_NAME
"
    
    # Process 'auto' values in NFS configuration
    if [[ "$NFS_ALLOWED_NETWORKS" == "auto" ]]; then
        NFS_ALLOWED_NETWORKS="$NETWORK_CIDR"
    fi
    
    log INFO "NFS export path: $NFS_EXPORT_PATH"
    log INFO "NFS allowed networks: $NFS_ALLOWED_NETWORKS"
    
    if [[ -n "$NFS_EXPORTS" ]]; then
        # Parse custom exports (format: path:options:networks,path:options:networks)
        IFS=',' read -ra EXPORT_ENTRIES <<< "$NFS_EXPORTS"
        for entry in "${EXPORT_ENTRIES[@]}"; do
            IFS=':' read -ra EXPORT_PARTS <<< "$entry"
            local path="${EXPORT_PARTS[0]}"
            local options="${EXPORT_PARTS[1]:-$NFS_EXPORT_OPTIONS}"
            local networks="${EXPORT_PARTS[2]:-$NFS_ALLOWED_NETWORKS}"
            
            # Process 'auto' in networks
            if [[ "$networks" == "auto" ]]; then
                networks="$NETWORK_CIDR"
            fi
            
            if [[ -n "$networks" ]]; then
                IFS=',' read -ra NET_LIST <<< "$networks"
                for network in "${NET_LIST[@]}"; do
                    network=$(echo "$network" | xargs)
                    exports_config+="$path $network($options)"$'\n'
                done
            else
                exports_config+="$path *($options)"$'\n'
            fi
        done
    else
        # Default export
        if [[ -n "$NFS_ALLOWED_NETWORKS" ]]; then
            IFS=',' read -ra NETWORKS <<< "$NFS_ALLOWED_NETWORKS"
            for network in "${NETWORKS[@]}"; do
                network=$(echo "$network" | xargs)
                exports_config+="$NFS_EXPORT_PATH $network($NFS_EXPORT_OPTIONS)"$'\n'
            done
        else
            exports_config+="$NFS_EXPORT_PATH *($NFS_EXPORT_OPTIONS)"$'\n'
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would write NFS exports to $exports_file"
    else
        echo "$exports_config" > "$exports_file"
        log SUCCESS "NFS exports written to $exports_file"
    fi
    
    execute_command "Enabling and starting NFS services" "systemctl enable --now nfs-server rpcbind"
    execute_command "Exporting NFS shares" "exportfs -ra"
}

function configure_httpd() {
    [[ "$HTTPD_ENABLED" != true ]] && return
    
    log INFO "Configuring HTTPD server..."
    
    # Create document root if it doesn't exist
    if [[ ! -d "$HTTPD_DOCUMENT_ROOT" ]]; then
        execute_command "Creating document root directory $HTTPD_DOCUMENT_ROOT" "mkdir -p '$HTTPD_DOCUMENT_ROOT'"
        execute_command "Setting document root permissions" "chmod 755 '$HTTPD_DOCUMENT_ROOT'"
        execute_command "Setting document root ownership" "chown apache:apache '$HTTPD_DOCUMENT_ROOT'"
        
        # Set SELinux context for web content
        if command -v semanage &>/dev/null && command -v restorecon &>/dev/null; then
            execute_command "Setting SELinux context for web content" "semanage fcontext -a -t httpd_exec_t '$HTTPD_DOCUMENT_ROOT(/.*)?'"
            execute_command "Applying SELinux context" "restorecon -Rv '$HTTPD_DOCUMENT_ROOT'"
        else
            log WARN "SELinux tools not available, skipping SELinux context setup"
        fi
    fi
    
    # Process 'auto' values in HTTPD configuration
    if [[ "$HTTPD_SERVER_NAME" == "auto" ]]; then
        HTTPD_SERVER_NAME="$HOSTNAME.$DOMAIN"
    fi
    
    local httpd_conf="/etc/httpd/conf/httpd.conf"
    backup_file "$httpd_conf"
    
    # Create basic httpd.conf
    local httpd_config="# Generated by $SCRIPT_NAME
ServerRoot /etc/httpd
Listen $HTTPD_PORT

Include conf.modules.d/*.conf

User apache
Group apache

ServerAdmin admin@$DOMAIN
ServerName $HTTPD_SERVER_NAME:$HTTPD_PORT

DocumentRoot \"$HTTPD_DOCUMENT_ROOT\"

<Directory \"$HTTPD_DOCUMENT_ROOT\">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<IfModule dir_module>
    DirectoryIndex index.html index.php
</IfModule>

<Files \".ht*\">
    Require all denied
</Files>

ErrorLog logs/error_log
LogLevel warn

<IfModule log_config_module>
    LogFormat \"%h %l %u %t \\\"%r\\\" %>s %b \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\"\" combined
    LogFormat \"%h %l %u %t \\\"%r\\\" %>s %b\" common
    CustomLog logs/access_log combined
</IfModule>

<IfModule alias_module>
    ScriptAlias /cgi-bin/ \"/var/www/cgi-bin/\"
</IfModule>

<Directory \"/var/www/cgi-bin\">
    AllowOverride None
    Options None
    Require all granted
</Directory>

<IfModule mime_module>
    TypesConfig /etc/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
    AddType text/html .shtml
    AddOutputFilter INCLUDES .shtml
</IfModule>

AddDefaultCharset UTF-8

<IfModule mime_magic_module>
    MIMEMagicFile conf/magic
</IfModule>

EnableSendfile on

IncludeOptional conf.d/*.conf"
    
    # Add SSL configuration if enabled
    if [[ "$HTTPD_SSL_ENABLED" == true ]]; then
        httpd_config+="

# SSL Configuration
LoadModule ssl_module modules/mod_ssl.so
Listen $HTTPD_SSL_PORT ssl

<VirtualHost *:$HTTPD_SSL_PORT>
    ServerName $HTTPD_SERVER_NAME:$HTTPD_SSL_PORT
    DocumentRoot \"$HTTPD_DOCUMENT_ROOT\"
    
    SSLEngine on
    SSLCertificateFile \"$HTTPD_SSL_CERT_PATH\"
    SSLCertificateKeyFile \"$HTTPD_SSL_KEY_PATH\"
    
    <Directory \"$HTTPD_DOCUMENT_ROOT\">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>"
    fi
    
    # Add custom configuration if provided
    if [[ -n "$HTTPD_CUSTOM_CONFIG" ]]; then
        httpd_config+="

# Custom Configuration
$HTTPD_CUSTOM_CONFIG"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Would write HTTPD configuration to $httpd_conf"
    else
        echo "$httpd_config" > "$httpd_conf"
        log SUCCESS "HTTPD configuration written to $httpd_conf"
    fi
    
    # Create a simple index.html if it doesn't exist
    local index_file="$HTTPD_DOCUMENT_ROOT/index.html"
    if [[ ! -f "$index_file" ]]; then
        local index_content="<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Welcome to $HTTPD_SERVER_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        h1 { color: #333; }
        .info { background: #f4f4f4; padding: 20px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class=\"container\">
        <h1>🌐 Welcome to $HTTPD_SERVER_NAME</h1>
        <div class=\"info\">
            <p><strong>Server:</strong> $HTTPD_SERVER_NAME</p>
            <p><strong>Document Root:</strong> $HTTPD_DOCUMENT_ROOT</p>
            <p><strong>Generated:</strong> $(date)</p>
        </div>
        <p>This Apache HTTP Server is running successfully!</p>
        <p>You can place your web content in <code>$HTTPD_DOCUMENT_ROOT</code></p>
    </div>
</body>
</html>"
        
        if [[ "$DRY_RUN" == true ]]; then
            log INFO "Would create default index.html at $index_file"
        else
            echo "$index_content" > "$index_file"
            chown apache:apache "$index_file"
            log SUCCESS "Created default index.html"
        fi
    fi
    
    # Generate self-signed SSL certificate if SSL is enabled and cert doesn't exist
    if [[ "$HTTPD_SSL_ENABLED" == true && ! -f "$HTTPD_SSL_CERT_PATH" ]]; then
        log INFO "Generating self-signed SSL certificate..."
        
        # Create SSL directories
        execute_command "Creating SSL certificate directory" "mkdir -p '$(dirname "$HTTPD_SSL_CERT_PATH")'"
        execute_command "Creating SSL key directory" "mkdir -p '$(dirname "$HTTPD_SSL_KEY_PATH")'"
        
        # Generate SSL certificate
        local ssl_subj="/C=KH/ST=Phnom Penh/L=Phnom Penh/O=RHLAB/OU=IT Department/CN=$HTTPD_SERVER_NAME"
        execute_command "Generating SSL certificate" "openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout '$HTTPD_SSL_KEY_PATH' -out '$HTTPD_SSL_CERT_PATH' -subj '$ssl_subj'"
        execute_command "Setting SSL certificate permissions" "chmod 600 '$HTTPD_SSL_KEY_PATH'"
        execute_command "Setting SSL certificate ownership" "chown apache:apache '$HTTPD_SSL_CERT_PATH' '$HTTPD_SSL_KEY_PATH'"
    fi
    
    execute_command "Enabling and starting httpd service" "systemctl enable --now httpd"
}

function configure_firewall() {
    [[ "$FIREWALL_ENABLED" != true ]] && return
    
    log INFO "Configuring firewall rules..."
    
    # DNS
    if [[ "$DNS_ENABLED" == true ]]; then
        execute_command "Opening DNS port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=dns"
    fi
    
    # NTP
    if [[ "$NTP_ENABLED" == true ]]; then
        execute_command "Opening NTP port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=ntp"
    fi
    
    # NFS
    if [[ "$NFS_ENABLED" == true ]]; then
        execute_command "Opening NFS ports in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=nfs"
        execute_command "Opening RPC bind port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=rpc-bind"
        execute_command "Opening mountd port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=mountd"
    fi
    
    # HTTPD
    if [[ "$HTTPD_ENABLED" == true ]]; then
        execute_command "Opening HTTP port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=http"
        if [[ "$HTTPD_SSL_ENABLED" == true ]]; then
            execute_command "Opening HTTPS port in firewall" "firewall-cmd --permanent --zone=$FIREWALL_ZONE --add-service=https"
        fi
    fi
    
    execute_command "Reloading firewall configuration" "firewall-cmd --reload"
}

function parse_all_arguments() {
    # First pass: extract env-file
    local env_file=".env"
    local args=("$@")
    
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--env-file" && $((i+1)) -lt ${#args[@]} ]]; then
            env_file="${args[$((i+1))]}"
            break
        fi
    done
    
    # Load environment file
    load_env_file "$env_file"
    
    # Second pass: parse all arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) print_usage; exit 0 ;;
            --version) echo "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-backup) BACKUP_CONFIG=false; shift ;;
            --log-level) LOG_LEVEL="$2"; shift 2 ;;
            --env-file) shift 2 ;;  # Already processed
            --services) SERVICES_TO_CONFIGURE="$2"; shift 2 ;;
            
            # Network
            --hostname) HOSTNAME="$2"; shift 2 ;;
            --domain) DOMAIN="$2"; shift 2 ;;
            --timezone) TIMEZONE="$2"; shift 2 ;;
            
            # DNS
            --enable-dns) DNS_ENABLED=true; shift ;;
            --dns-forwarders) DNS_FORWARDERS="$2"; shift 2 ;;
            --dns-allow-query) DNS_ALLOW_QUERY="$2"; shift 2 ;;
            --dns-allow-recursion) DNS_ALLOW_RECURSION="$2"; shift 2 ;;
            --dns-zone-file) DNS_ZONE_FILE="$2"; shift 2 ;;
            --dns-reverse-zone) DNS_REVERSE_ZONE="$2"; shift 2 ;;
            --dns-serial) DNS_SERIAL="$2"; shift 2 ;;
            
            # NTP
            --enable-ntp) NTP_ENABLED=true; shift ;;
            --ntp-servers) NTP_SERVERS="$2"; shift 2 ;;
            --ntp-allow-networks) NTP_ALLOW_NETWORKS="$2"; shift 2 ;;
            --ntp-prefer-server) NTP_PREFER_SERVER="$2"; shift 2 ;;
            --no-iburst) NTP_IBURST=false; shift ;;
            
            # NFS
            --enable-nfs) NFS_ENABLED=true; shift ;;
            --nfs-export-path) NFS_EXPORT_PATH="$2"; shift 2 ;;
            --nfs-exports) NFS_EXPORTS="$2"; shift 2 ;;
            --nfs-export-options) NFS_EXPORT_OPTIONS="$2"; shift 2 ;;
            --nfs-allowed-networks) NFS_ALLOWED_NETWORKS="$2"; shift 2 ;;
            
            # HTTPD
            --enable-httpd) HTTPD_ENABLED=true; shift ;;
            --httpd-document-root) HTTPD_DOCUMENT_ROOT="$2"; shift 2 ;;
            --httpd-server-name) HTTPD_SERVER_NAME="$2"; shift 2 ;;
            --httpd-port) HTTPD_PORT="$2"; shift 2 ;;
            --enable-ssl) HTTPD_SSL_ENABLED=true; shift ;;
            --httpd-ssl-port) HTTPD_SSL_PORT="$2"; shift 2 ;;
            --httpd-ssl-cert) HTTPD_SSL_CERT_PATH="$2"; shift 2 ;;
            --httpd-ssl-key) HTTPD_SSL_KEY_PATH="$2"; shift 2 ;;
            --httpd-custom-config) HTTPD_CUSTOM_CONFIG="$2"; shift 2 ;;
            
            # Firewall
            --disable-firewall) FIREWALL_ENABLED=false; shift ;;
            --firewall-zone) FIREWALL_ZONE="$2"; shift 2 ;;
            
            *) log ERROR "Unknown option: $1"; print_usage; exit 1 ;;
        esac
    done
    
    # Process services list
    if [[ -n "$SERVICES_TO_CONFIGURE" ]]; then
        IFS=',' read -ra SERVICES <<< "$SERVICES_TO_CONFIGURE"
        for service in "${SERVICES[@]}"; do
            case "$(echo "$service" | xargs | tr '[:upper:]' '[:lower:]')" in
                dns) DNS_ENABLED=true ;;
                ntp) NTP_ENABLED=true ;;
                nfs) NFS_ENABLED=true ;;
                httpd) HTTPD_ENABLED=true ;;
                all) DNS_ENABLED=true; NTP_ENABLED=true; NFS_ENABLED=true; HTTPD_ENABLED=true ;;
                *) log WARN "Unknown service: $service" ;;
            esac
        done
    fi
}

function validate_configuration() {
    log INFO "Validating configuration..."
    
    # Check auto-detected values
    if [[ -z "$PRIMARY_IP" ]]; then
        log ERROR "Could not auto-detect primary IP address"
        exit 1
    fi
    
    if [[ -z "$NETWORK_CIDR" ]]; then
        log ERROR "Could not auto-detect network CIDR"
        exit 1
    fi
    
    if [[ -z "$GATEWAY_IP" ]]; then
        log ERROR "Could not auto-detect gateway IP"
        exit 1
    fi
    
    # Validate auto-detected values
    if ! validate_ip "$PRIMARY_IP"; then
        log ERROR "Invalid auto-detected primary IP: $PRIMARY_IP"
        exit 1
    fi
    
    if ! validate_cidr "$NETWORK_CIDR"; then
        log ERROR "Invalid auto-detected network CIDR: $NETWORK_CIDR"
        exit 1
    fi
    
    if ! validate_ip "$GATEWAY_IP"; then
        log ERROR "Invalid auto-detected gateway IP: $GATEWAY_IP"
        exit 1
    fi
    
    # Check if any service is enabled
    if [[ "$DNS_ENABLED" != true && "$NTP_ENABLED" != true && "$NFS_ENABLED" != true && "$HTTPD_ENABLED" != true ]]; then
        log ERROR "No services enabled. Use --services or individual --enable-* flags"
        exit 1
    fi
    
    log SUCCESS "Configuration validation passed"
}

function print_configuration_summary() {
    log INFO "Configuration Summary:"
    echo "  🏷️  Hostname: $HOSTNAME"
    echo "  🌐 Domain: $DOMAIN"
    echo "  📍 Primary IP: $PRIMARY_IP (auto-detected)"
    echo "  🌐 Network CIDR: $NETWORK_CIDR (auto-detected)"
    echo "  🚪 Gateway: $GATEWAY_IP (auto-detected)"
    echo "  🕐 Timezone: $TIMEZONE"
    echo "  📋 Services: DNS=$DNS_ENABLED, NTP=$NTP_ENABLED, NFS=$NFS_ENABLED, HTTPD=$HTTPD_ENABLED"
    echo "  🔥 Firewall: $FIREWALL_ENABLED"
    echo "  💾 Backup Config: $BACKUP_CONFIG"
    echo "  🧪 Dry Run: $DRY_RUN"
    if [[ "$NFS_ENABLED" == true ]]; then
        echo "  📁 NFS Export: $NFS_EXPORT_PATH -> $NFS_ALLOWED_NETWORKS"
    fi
}

function main() {
    log INFO "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Check if running as root
    if [[ $EUID -ne 0 && "$DRY_RUN" != true ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Parse all arguments
    parse_all_arguments "$@"
    
    # Validate and display configuration
    validate_configuration
    print_configuration_summary
    
    # Ask for confirmation unless dry run
    if [[ "$DRY_RUN" != true ]]; then
        read -p "Continue with configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Configuration cancelled by user"
            exit 0
        fi
    fi
    
    # Execute configuration
    log INFO "Starting service configuration..."
    
    configure_hostname
    configure_timezone
    install_packages
    configure_dns
    configure_ntp
    configure_nfs
    configure_httpd
    configure_firewall
    
    log SUCCESS "Service configuration completed successfully!"
    
    # Print service status
    echo
    log INFO "Service Status:"
    if [[ "$DRY_RUN" != true ]]; then
        [[ "$DNS_ENABLED" == true ]] && systemctl is-active named &>/dev/null && echo "  ✅ DNS (named): Active" || echo "  ❌ DNS (named): Inactive"
        [[ "$NTP_ENABLED" == true ]] && systemctl is-active chronyd &>/dev/null && echo "  ✅ NTP (chronyd): Active" || echo "  ❌ NTP (chronyd): Inactive"
        [[ "$NFS_ENABLED" == true ]] && systemctl is-active nfs-server &>/dev/null && echo "  ✅ NFS (nfs-server): Active" || echo "  ❌ NFS (nfs-server): Inactive"
        [[ "$HTTPD_ENABLED" == true ]] && systemctl is-active httpd &>/dev/null && echo "  ✅ HTTPD (httpd): Active" || echo "  ❌ HTTPD (httpd): Inactive"
    else
        echo "  🧪 Dry run mode - no services actually configured"
    fi
    
    # Print connection information
    if [[ "$DRY_RUN" != true ]]; then
        echo
        log INFO "Service Access Information:"
        [[ "$DNS_ENABLED" == true ]] && echo "  🔍 DNS Server: $PRIMARY_IP (domain: $DOMAIN)"
        [[ "$NTP_ENABLED" == true ]] && echo "  🕐 NTP Server: $PRIMARY_IP"
        [[ "$NFS_ENABLED" == true ]] && echo "  📁 NFS Server: $PRIMARY_IP:$NFS_EXPORT_PATH"
        [[ "$NFS_ENABLED" == true ]] && echo "  📋 Mount command: sudo mount -t nfs $PRIMARY_IP:$NFS_EXPORT_PATH /mnt"
    fi
}

# Execute main function
main "$@"
