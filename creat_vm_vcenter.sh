#!/bin/bash
set -e

# ==== DEFAULTS ====
VM_NAME="bastion"
VM_CPU=4
VM_MEM_GB=8
VM_DISK_SIZE=200
GENERATE_KS=true
AUTO_PARTITION=false
MONITOR_REBOOT=true
VM_LAB_DOMAIN="rhlab.local"

# vCenter Configuration
VCENTER_SERVER=""
VCENTER_USERNAME=""
VCENTER_PASSWORD=""
VCENTER_DATACENTER=""
VCENTER_CLUSTER=""
VCENTER_DATASTORE=""
VCENTER_PORTGROUP=""
VCENTER_FOLDER=""
VCENTER_TEMPLATE=""

# Network Configuration
VM_IP=""
VM_GATEWAY=""
VM_NETMASK="255.255.255.0"
VM_DNS=""

#---- Partitions ----
ROOT_RATIO=35 # / chiếm 35% tổng dung lượng hard-disk 
HOME_RATIO=15 # /home chiếm 15% tổng dung lượng hard-disk 
DATA_RATIO=50 # /data chiếm 50% tổng dung lượng hard-disk

# ==== USAGE ====
function print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Required vCenter Parameters:
  --vcenter-server IP/FQDN     vCenter Server address
  --vcenter-user USERNAME      vCenter username
  --vcenter-pass PASSWORD      vCenter password
  --vcenter-datacenter NAME    Target datacenter
  --vcenter-cluster NAME       Target cluster
  --vcenter-datastore NAME     Target datastore
  --vcenter-portgroup NAME     Target port group/network

Required VM Parameters:
  --iso PATH                   Path to ISO on datastore or URL
  --variant VARIANT            ISO variant: RHEL, Ubuntu, RHCoreOS
  --vm-ip IP                   Static IP for VM
  --vm-gateway IP              Gateway IP
  --vm-dns IP                  DNS server IP

Optional vCenter Parameters:
  --vcenter-folder PATH        VM folder path (default: root)
  --vcenter-template NAME      Template to clone from (instead of ISO)

Optional VM Parameters:
  --name NAME                  Name of the VM (default: bastion)
  --user USERNAME              Username to create inside VM
  --pass PASSWORD              Password for the created user
  --cpu NUM                    Number of CPUs (default: 4)
  --ram GB                     RAM in GB (default: 8)
  --disk GB                    Disk size in GB (default: 200)
  --domain NAME                Domain name (default: rhlab.local)
  --netmask MASK               Network mask (default: 255.255.255.0)
  --autopart                   Use automatic partitioning
  --no-ks                      Do not generate kickstart
  --no-monitor                 Do not monitor VM state

Examples:
  $0 --vcenter-server vcenter.lab.local --vcenter-user admin@vsphere.local \\
     --vcenter-pass VMware123! --vcenter-datacenter Lab --vcenter-cluster Cluster1 \\
     --vcenter-datastore datastore1 --vcenter-portgroup "VM Network" \\
     --iso "[datastore1] ISO/rhel-9.2.iso" --variant RHEL \\
     --vm-ip 192.168.1.100 --vm-gateway 192.168.1.1 --vm-dns 192.168.1.1 \\
     --user demo --pass secret123

  $0 --vcenter-server vcenter.lab.local --vcenter-user admin@vsphere.local \\
     --vcenter-pass VMware123! --vcenter-datacenter Lab --vcenter-cluster Cluster1 \\
     --vcenter-datastore datastore1 --vcenter-portgroup "VM Network" \\
     --vcenter-template ubuntu-template --variant Ubuntu \\
     --vm-ip 192.168.1.101 --vm-gateway 192.168.1.1 --vm-dns 192.168.1.1 \\
     --user ubuntu --pass ubuntu123
EOF
}

# ==== PARSE ARGUMENTS ====
function parse_arguments() {
  if [[ "$#" -eq 0 ]]; then print_usage; exit 1; fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      # VM Parameters
      --name) VM_NAME="$2"; shift 2 ;;
      --cpu) VM_CPU="$2"; shift 2 ;;
      --ram) VM_MEM_GB="$2"; shift 2 ;;
      --disk) VM_DISK_SIZE="$2"; shift 2 ;;
      --user) VM_USER="$2"; shift 2 ;;
      --pass) VM_PASS="$2"; shift 2 ;;
      --domain) VM_LAB_DOMAIN="$2"; shift 2 ;;
      --iso) ISO_PATH="$2"; shift 2 ;;
      --variant) ISO_VARIANT="$2"; shift 2 ;;
      --autopart) AUTO_PARTITION=true; shift ;;
      --no-ks) GENERATE_KS=false; shift ;;
      --no-monitor) MONITOR_REBOOT=false; shift ;;

      # Network Parameters
      --vm-ip) VM_IP="$2"; shift 2 ;;
      --vm-gateway) VM_GATEWAY="$2"; shift 2 ;;
      --vm-dns) VM_DNS="$2"; shift 2 ;;
      --netmask) VM_NETMASK="$2"; shift 2 ;;

      # vCenter Parameters
      --vcenter-server) VCENTER_SERVER="$2"; shift 2 ;;
      --vcenter-user) VCENTER_USERNAME="$2"; shift 2 ;;
      --vcenter-pass) VCENTER_PASSWORD="$2"; shift 2 ;;
      --vcenter-datacenter) VCENTER_DATACENTER="$2"; shift 2 ;;
      --vcenter-cluster) VCENTER_CLUSTER="$2"; shift 2 ;;
      --vcenter-datastore) VCENTER_DATASTORE="$2"; shift 2 ;;
      --vcenter-portgroup) VCENTER_PORTGROUP="$2"; shift 2 ;;
      --vcenter-folder) VCENTER_FOLDER="$2"; shift 2 ;;
      --vcenter-template) VCENTER_TEMPLATE="$2"; shift 2 ;;

      --help) print_usage; exit 0 ;;
      *) echo "❌ Unknown option: $1"; print_usage; exit 1 ;;
    esac
  done

  # Validate required vCenter parameters
  if [[ -z "$VCENTER_SERVER" || -z "$VCENTER_USERNAME" || -z "$VCENTER_PASSWORD" || 
        -z "$VCENTER_DATACENTER" || -z "$VCENTER_CLUSTER" || -z "$VCENTER_DATASTORE" || 
        -z "$VCENTER_PORTGROUP" ]]; then
    echo "❌ Missing required vCenter parameters."
    print_usage
    exit 1
  fi

  # Validate required VM parameters
  if [[ -z "$VM_IP" || -z "$VM_GATEWAY" || -z "$VM_DNS" ]]; then
    echo "❌ Missing required network parameters (--vm-ip, --vm-gateway, --vm-dns)."
    print_usage
    exit 1
  fi

  # Validate ISO or Template
  if [[ -z "$ISO_PATH" && -z "$VCENTER_TEMPLATE" ]]; then
    echo "❌ Either --iso or --vcenter-template must be specified."
    print_usage
    exit 1
  fi

  if [[ -z "$ISO_VARIANT" ]]; then
    echo "❌ Missing required argument: --variant"
    print_usage
    exit 1
  fi

  # Skip user/pass validation for RHCoreOS
  shopt -s nocasematch
  if [[ ! "$ISO_VARIANT" =~ ^(RHCoreOS|rhcos)$ ]]; then
    if [[ -z "$VM_USER" || -z "$VM_PASS" ]]; then
      echo "❌ Missing --user or --pass."
      print_usage
      exit 1
    fi
  fi
  shopt -u nocasematch

  # Set defaults
  [[ -z "$VCENTER_FOLDER" ]] && VCENTER_FOLDER=""
  [[ -z "$VM_DNS" ]] && VM_DNS="$VM_GATEWAY"
}

# ==== CHECK FOR REQUIRED PACKAGES ====
function check_required_packages() {
  echo "🔍 Checking for required packages..."
  
  # Check if PowerShell is installed
  if ! command -v pwsh &> /dev/null; then
    echo "❌ PowerShell Core (pwsh) is required but not installed."
    echo "Please install PowerShell Core first:"
    echo "  - RHEL/CentOS: sudo dnf install -y powershell"
    echo "  - Ubuntu: sudo apt install -y powershell"
    exit 1
  fi

  # Check if VMware PowerCLI is installed
  if ! pwsh -c "Get-Module -ListAvailable VMware.PowerCLI" &>/dev/null; then
    echo "⏳ Installing VMware PowerCLI..."
    pwsh -c "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module VMware.PowerCLI -Force"
  else
    echo "✅ VMware PowerCLI is already installed."
  fi

  # Check other utilities
  local packages=(genisoimage curl)
  local missing=()

  for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "⚠️  Installing missing packages: ${missing[*]}"
    if command -v dnf &>/dev/null; then
      sudo dnf install -y "${missing[@]}"
    elif command -v apt &>/dev/null; then
      sudo apt update && sudo apt install -y "${missing[@]}"
    else
      echo "❌ Unable to install packages. Please install manually: ${missing[*]}"
      exit 1
    fi
  fi

  echo "✅ All required packages are available."
}

# ==== GENERATE KICKSTART FILE ====
function generate_kickstart_file() {
  echo "📄 Generating Kickstart file..."
  local ks_path="kickstart-${VM_NAME}.cfg"
  local BOOT_MB=1024 SWAP_MB=2048 OVERHEAD_MB=1024
  TOTAL_MB=$((VM_DISK_SIZE * 1024))
  AVAILABLE_MB=$((TOTAL_MB - BOOT_MB - SWAP_MB - OVERHEAD_MB))
  ROOT_MB=$((AVAILABLE_MB * ROOT_RATIO / 100))
  HOME_MB=$((AVAILABLE_MB * HOME_RATIO / 100))
  DATA_MB=$((AVAILABLE_MB * DATA_RATIO / 100))

  local LAST_OCTET="${VM_IP##*.}"
  local NETWORK_PREFIX="${VM_IP%.*}.0"
  local REVERSE_ZONE
  IFS=. read -r A B C D <<< "$VM_IP"
  REVERSE_ZONE="$C.$B.$A.in-addr.arpa"

  cat > "$ks_path" <<EOF
#version=RHEL9
cdrom
lang en_US.UTF-8
keyboard us
timezone Asia/Ho_Chi_Minh --utc
network --bootproto=static --ip=$VM_IP --netmask=$VM_NETMASK --gateway=$VM_GATEWAY --nameserver=$VM_DNS --device=link --activate --hostname=$VM_NAME
rootpw --plaintext $VM_PASS
user --name=$VM_USER --password=$VM_PASS --plaintext --groups=wheel
firewall --enabled --service=ssh,ntp,dns,nfs,mountd,rpc-bind
selinux --enforcing
bootloader --append="rhgb quiet crashkernel=auto"
zerombr
clearpart --all --initlabel
EOF

  if [[ "$AUTO_PARTITION" == true ]]; then
    echo "autopart" >> "$ks_path"
  else
    cat >> "$ks_path" <<PART
part /boot --fstype="xfs" --size=$BOOT_MB --ondisk=sda
part swap --size=$SWAP_MB --ondisk=sda
part / --fstype="xfs" --size=$ROOT_MB --ondisk=sda
part /home --fstype="xfs" --size=$HOME_MB --ondisk=sda
part /data --fstype="xfs" --size=$DATA_MB --ondisk=sda
PART
  fi

  cat >> "$ks_path" <<EOF
%packages
@^Server with GUI
kexec-tools
git
bind
bind-utils
chrony
nfs-utils
firefox
tmux
make
jq
python3-jinja2
python3-yaml
ncurses
which
diffutils
nmstate 
net-tools
podman
skopeo
open-vm-tools
%end

%post --interpreter=/bin/bash
# Configure DNS Server
cat > /etc/named.conf <<NAMEDCONF
options {
    listen-on port 53 { 127.0.0.1; $VM_IP; };
    directory       "/var/named";
    allow-query     { any; };
    forwarders { $VM_GATEWAY; };
    recursion yes;
    allow-recursion { any; };    
    dnssec-validation no;
};

zone "$VM_LAB_DOMAIN" IN {
    type master;
    file "$VM_LAB_DOMAIN.zone";
    allow-query     { any; };
};

zone "$REVERSE_ZONE" IN {
    type master;
    file "$REVERSE_ZONE.rev";
    allow-query     { any; };
};
NAMEDCONF

cat > /var/named/$VM_LAB_DOMAIN.zone <<ZONE
@   IN SOA   ns.$VM_LAB_DOMAIN. admin.$VM_LAB_DOMAIN. (
            2025041901 ; serial
            3600       ; refresh
            900        ; retry
            604800     ; expire
            86400 )    ; minimum
    IN NS    ns.$VM_LAB_DOMAIN.
@  IN A     $VM_IP
ns  IN A     $VM_IP
$VM_NAME IN A     $VM_IP
ZONE

cat > /var/named/$REVERSE_ZONE.rev <<REV
@   IN SOA   ns.$VM_LAB_DOMAIN. admin.$VM_LAB_DOMAIN. (
            2025041901 ; serial
            3600
            900
            604800
            86400 )
    IN NS    ns.$VM_LAB_DOMAIN.
$LAST_OCTET    IN PTR   $VM_NAME.$VM_LAB_DOMAIN.
REV

chown root:named /var/named/*.zone /var/named/*.rev
chmod 640 /var/named/*.zone /var/named/*.rev
systemctl enable --now named

# Configure NTP
echo "allow $NETWORK_PREFIX/24" >> /etc/chrony.conf
systemctl enable --now chronyd

# Configure NFS
mkdir -p /data
chmod 777 /data
chown -R nobody:nobody /data
if command -v semanage &>/dev/null; then
    semanage fcontext -a -t public_content_rw_t "/data(/.*)?" || true
    restorecon -Rv /data || true
fi
echo "/data *(rw,sync,no_subtree_check)" >> /etc/exports
systemctl enable --now nfs-server rpcbind

# Enable VMware Tools
systemctl enable --now vmtoolsd

# Configure desktop for user
if [[ -n "$VM_USER" ]]; then
    su - $VM_USER -c 'gsettings set org.gnome.shell enabled-extensions "[\"window-list@gnome-shell-extensions.gcampax.github.com\"]"' || true
fi

%end

reboot
EOF

  echo "✅ Kickstart file generated: $ks_path"
  KS_FILE="$ks_path"
}

# ==== CREATE VCENTER SESSION ====
function create_vcenter_session() {
  echo "🔐 Connecting to vCenter: $VCENTER_SERVER..."
  
  pwsh -c "
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:\$false | Out-Null
    try {
      Connect-VIServer -Server '$VCENTER_SERVER' -User '$VCENTER_USERNAME' -Password '$VCENTER_PASSWORD' -ErrorAction Stop | Out-Null
      Write-Host '✅ Successfully connected to vCenter'
    } catch {
      Write-Host '❌ Failed to connect to vCenter: ' \$_.Exception.Message
      exit 1
    }
  " || exit 1
}

# ==== CHECK EXISTING VM ====
function check_existing_vm() {
  echo "🔍 Checking if VM '$VM_NAME' already exists..."
  
  local vm_exists=$(pwsh -c "
    try {
      \$vm = Get-VM -Name '$VM_NAME' -ErrorAction SilentlyContinue
      if (\$vm) { Write-Host 'true' } else { Write-Host 'false' }
    } catch {
      Write-Host 'false'
    }
  ")

  if [[ "$vm_exists" == "true" ]]; then
    echo "⚠️  VM '$VM_NAME' already exists."
    read -p "❓ Do you want to delete it and continue? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "🧹 Cleaning up existing VM '$VM_NAME'..."
      pwsh -c "
        try {
          \$vm = Get-VM -Name '$VM_NAME'
          if (\$vm.PowerState -eq 'PoweredOn') {
            Stop-VM -VM \$vm -Confirm:\$false | Out-Null
          }
          Remove-VM -VM \$vm -DeletePermanently -Confirm:\$false | Out-Null
          Write-Host '✅ VM deleted successfully'
        } catch {
          Write-Host '❌ Failed to delete VM: ' \$_.Exception.Message
          exit 1
        }
      " || exit 1
    else
      read -p "📝 Enter a new VM name: " new_vm_name
      VM_NAME="$new_vm_name"
      echo "🔁 New VM will be created as '$VM_NAME'"
    fi
  fi
}

# ==== UPLOAD KICKSTART TO DATASTORE ====
function upload_kickstart_to_datastore() {
  if [[ "$GENERATE_KS" == true && -f "$KS_FILE" ]]; then
    echo "📤 Uploading kickstart file to datastore..."
    
    pwsh -c "
      try {
        \$datastore = Get-Datastore -Name '$VCENTER_DATASTORE'
        \$drive = New-PSDrive -Location \$datastore -Name ds -PSProvider VimDatastore -Root '\'
        Copy-DatastoreItem -Item '$KS_FILE' -Destination 'ds:\$KS_FILE' -Force
        Remove-PSDrive -Name ds -Confirm:\$false
        Write-Host '✅ Kickstart uploaded to datastore'
      } catch {
        Write-Host '❌ Failed to upload kickstart: ' \$_.Exception.Message
        exit 1
      }
    " || exit 1
  fi
}

# ==== CREATE VM ====
function create_vm() {
  echo "🚀 Creating VM '$VM_NAME'..."
  
  local vm_creation_script=""
  
  if [[ -n "$VCENTER_TEMPLATE" ]]; then
    # Clone from template
    vm_creation_script="
      \$template = Get-Template -Name '$VCENTER_TEMPLATE'
      \$datastore = Get-Datastore -Name '$VCENTER_DATASTORE'
      \$cluster = Get-Cluster -Name '$VCENTER_CLUSTER'
      \$portgroup = Get-VirtualPortGroup -Name '$VCENTER_PORTGROUP'
      
      \$spec = New-OSCustomizationSpec -Name 'temp-$VM_NAME' -Type Linux -Domain '$VM_LAB_DOMAIN' -DnsServer '$VM_DNS' -DnsSuffix '$VM_LAB_DOMAIN'
      \$nicmapping = Get-OSCustomizationNicMapping -OSCustomizationSpec \$spec
      Set-OSCustomizationNicMapping -OSCustomizationNicMapping \$nicmapping -IpMode UseStaticIP -IpAddress '$VM_IP' -SubnetMask '$VM_NETMASK' -DefaultGateway '$VM_GATEWAY'
      
      \$vm = New-VM -Name '$VM_NAME' -Template \$template -Datastore \$datastore -ResourcePool \$cluster -OSCustomizationSpec \$spec
      
      # Clean up temp customization spec
      Remove-OSCustomizationSpec -OSCustomizationSpec \$spec -Confirm:\$false
    "
  else
    # Create from ISO
    vm_creation_script="
      \$datastore = Get-Datastore -Name '$VCENTER_DATASTORE'
      \$cluster = Get-Cluster -Name '$VCENTER_CLUSTER'
      \$portgroup = Get-VirtualPortGroup -Name '$VCENTER_PORTGROUP'
      
      \$vm = New-VM -Name '$VM_NAME' -Datastore \$datastore -ResourcePool \$cluster -NumCpu $VM_CPU -MemoryGB $VM_MEM_GB -DiskGB $VM_DISK_SIZE -NetworkName '$VCENTER_PORTGROUP' -GuestId rhel9_64Guest
      
      # Add CD-ROM with ISO
      if ('$ISO_PATH' -match '^\[.*\].*') {
        # Datastore ISO path
        \$cdrom = Get-CDDrive -VM \$vm
        Set-CDDrive -CD \$cdrom -IsoPath '$ISO_PATH' -StartConnected:\$true -Confirm:\$false | Out-Null
      } else {
        Write-Host '⚠️  ISO path should be in datastore format: [datastore] path/to/iso.iso'
      }
    "
  fi

  # Add kickstart parameters if using kickstart
  if [[ "$GENERATE_KS" == true ]]; then
    vm_creation_script+="
      # Add kickstart boot parameters
      \$bootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
      \$bootOptions.BootDelay = 3000
      \$extraConfig = New-Object VMware.Vim.optionvalue
      \$extraConfig.Key = 'bios.bootDelay'
      \$extraConfig.Value = '3000'
      
      \$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
      \$spec.BootOptions = \$bootOptions
      \$spec.ExtraConfig += \$extraConfig
      
      \$vm.ExtensionData.ReconfigVM(\$spec)
    "
  fi

  # Move to folder if specified
  if [[ -n "$VCENTER_FOLDER" ]]; then
    vm_creation_script+="
      \$folder = Get-Folder -Name '$VCENTER_FOLDER'
      Move-VM -VM \$vm -Destination \$folder | Out-Null
    "
  fi

  pwsh -c "
    try {
      $vm_creation_script
      Write-Host '✅ VM created successfully'
    } catch {
      Write-Host '❌ Failed to create VM: ' \$_.Exception.Message
      exit 1
    }
  " || exit 1
}

# ==== START VM ====
function start_vm() {
  echo "▶️  Starting VM '$VM_NAME'..."
  
  pwsh -c "
    try {
      \$vm = Get-VM -Name '$VM_NAME'
      Start-VM -VM \$vm -Confirm:\$false | Out-Null
      Write-Host '✅ VM started successfully'
    } catch {
      Write-Host '❌ Failed to start VM: ' \$_.Exception.Message
      exit 1
    }
  " || exit 1
}

# ==== MONITOR VM STATE ====
function monitor_vm_state() {
  if [[ "$MONITOR_REBOOT" == false ]]; then
    echo "⏭️  Skipping VM state monitoring."
    return
  fi

  echo "⏳ Monitoring VM state..."
  
  local SPINNER='/-\|'
  local i=0
  local seen_shutdown=false
  local installation_complete=false
  
  while [[ "$installation_complete" == false ]]; do
    local vm_state=$(pwsh -c "
      try {
        \$vm = Get-VM -Name '$VM_NAME'
        Write-Host \$vm.PowerState
      } catch {
        Write-Host 'Unknown'
      }
    ")
    
    case "$vm_state" in
      "PoweredOff")
        if [[ "$seen_shutdown" == false ]]; then
          echo -e "\n✅ VM has shut down after installation."
          seen_shutdown=true
          echo "🔄 Starting VM..."
          start_vm
        fi
        ;;
      "PoweredOn")
        if [[ "$seen_shutdown" == true ]]; then
          echo -e "\n✅ VM is now running after reboot."
          installation_complete=true
          break
        fi
        ;;
    esac
    
    printf "\r[%c] VM State: %s" "${SPINNER:i:1}" "$vm_state"
    i=$(( (i+1) % ${#SPINNER} ))
    sleep 2
  done
}

# ==== CLEANUP ====
function cleanup_and_disconnect() {
  echo "🧹 Cleaning up..."
  
  # Remove local kickstart file
  [[ -f "$KS_FILE" ]] && rm -f "$KS_FILE"
  
  # Disconnect from vCenter
  pwsh -c "
    try {
      Disconnect-VIServer -Server '$VCENTER_SERVER' -Confirm:\$false
      Write-Host '✅ Disconnected from vCenter'
    } catch {
      Write-Host '⚠️  Error disconnecting from vCenter'
    }
  " 2>/dev/null || true
}

# ==== PRINT FINISH MESSAGE ====
function print_finish_message() {
  echo "⏳ Waiting for services to start..."
  sleep 10
  
  # Get VM information
  local vm_info=$(pwsh -c "
    try {
      \$vm = Get-VM -Name '$VM_NAME'
      \$ip = \$vm.Guest.IPAddress | Where-Object { \$_ -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\$' } | Select-Object -First 1
      if (-not \$ip) { \$ip = '$VM_IP' }
      Write-Host \"IP:\$ip\"
      Write-Host \"State:\$(\$vm.PowerState)\"
    } catch {
      Write-Host 'IP:$VM_IP'
      Write-Host 'State:Unknown'
    }
  ")
  
  local actual_ip=$(echo "$vm_info" | grep "IP:" | cut -d: -f2)
  local vm_state=$(echo "$vm_info" | grep "State:" | cut -d: -f2)
  
  echo
  cat <<EOF
===== DEPLOYMENT COMPLETE =====
VM is ready!

  Name:           $VM_NAME
  vCenter:        $VCENTER_SERVER
  Datacenter:     $VCENTER_DATACENTER
  Cluster:        $VCENTER_CLUSTER
  Datastore:      $VCENTER_DATASTORE
  Network:        $VCENTER_PORTGROUP
  IP Address:     ${actual_ip:-$VM_IP}
  State:          $vm_state
  Username:       $VM_USER
  Password:       $VM_PASS
  Domain:         $VM_LAB_DOMAIN
EOF

  if [[ "$GENERATE_KS" == true && -n "$VM_USER" ]]; then
    echo
    echo "To connect:"
    echo "    ssh $VM_USER@${actual_ip:-$VM_IP}"
    
    echo
    echo "✅ Verifying services on VM (${actual_ip:-$VM_IP})..."
    
    # Check services
    if command -v nc &>/dev/null; then
      echo -n "- SSH (port 22):     "; nc -zvw3 "${actual_ip:-$VM_IP}" 22 && echo "OK" || echo "FAILED"
      echo -n "- DNS (port 53):     "; nc -zvw3 "${actual_ip:-$VM_IP}" 53 && echo "OK" || echo "FAILED"
      echo -n "- NFS (port 2049):   "; nc -zvw3 "${actual_ip:-$VM_IP}" 2049 && echo "OK" || echo "FAILED"
    fi
  fi
}

# ==== MAIN FUNCTION ====
function main() {
  # Setup error handling
  trap cleanup_and_disconnect EXIT
  
  parse_arguments "$@"
  check_required_packages
  create_vcenter_session
  check_existing_vm
  
  if [[ "$GENERATE_KS" == true ]]; then
    generate_kickstart_file
    upload_kickstart_to_datastore
  fi
  
  create_vm
  start_vm
  monitor_vm_state
  print_finish_message
}

# ==== EXECUTION ====
main "$@"