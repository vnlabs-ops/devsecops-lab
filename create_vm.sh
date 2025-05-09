#!/bin/bash
set -e

# ==== DEFAULTS ====
VM_NAME="bastion"
VM_CPU=4
VM_MEM_MB=8192
VM_DISK_SIZE=200
VM_IMG_DIR="/var/lib/libvirt/images"
KS_FILE="kickstart.cfg"
GENERATE_KS=true
AUTO_PARTITION=false
MONITOR_REBOOT=true
VM_LAB_DOMAIN="rhlab.local"
VM_LAB_MAC="52:54:00:$(printf '%02x' $((RANDOM % 256))):$(printf '%02x' $((RANDOM % 256))):$(printf '%02x' $((RANDOM % 256)))"

#---- Partitions ----
ROOT_RATIO=35 # / chiếm 35% tổng dung lượng hard-disk 
HOME_RATIO=15 # /home chiếm 15% tổng dung lượng hard-disk 
# (nếu định dùng bastion làm mirror - cài đặt với aba - thì tăng tỉ lệ lên cho phù hợp)
DATA_RATIO=50 # /data chiếm 15% tổng dung lượng hard-disk

# ==== USAGE ====
function print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Required:
  --iso PATH           Path to ISO installation media
  --variant VARIANT    ISO variant: RHEL, Ubuntu, RHCoreOS
  --domain NAME        Domain name for internal DNS (default: rhlab.local)

Optional:
  --name NAME          Name of the VM (default: bastion)
  --user USERNAME      Username to create inside VM (not need if variant=RHCOS)
  --pass PASSWORD      Password for the created user (not need if variant=RHCOS)
  --cpu NUM            Number of CPUs (default: 4)
  --ram MB             RAM in MB (default: 8192)
  --disk GB            Disk size in GB (default: 200)
  --autopart           Use automatic partitioning (default: manual layout)
  --no-ks              Do not generate or use Kickstart (Ubuntu/RHCoreOS)
  --no-monitor         Do not monitor VM State (default: monitoring is ON)
  --mac-address        Specify MAC Address for the VM manually (in case of RHCOS)
  

Notes:
  - Without --autopart, manual partition layout is used (default).
  - For RHCoreOS:
      * Kickstart is not used (implied by --no-ks)
      * Manually MAC Address must be specified
      * Reboot monitoring is disabled by default
      * You must explicitly use --autopart (manual partitioning not supported)

Examples:
  $0 --iso /path/to/rhel.iso --variant RHEL --user demo --pass secret123
  $0 --iso /path/to/ubuntu.iso --variant Ubuntu --user ubuntu --pass ubuntu123 --no-ks
  $0 --iso /path/to/rhcos.iso --variant RHCoreOS --user core --pass core123 --mac-address $VM_LAB_MAC --no-ks --autopart --no-monitor
EOF
}

# ==== PARSE ARGUMENTS ====
function parse_arguments() {
  if [[ "$#" -eq 0 ]]; then print_usage; exit 1; fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --name) VM_NAME="$2"; shift 2 ;;
      --cpu) VM_CPU="$2"; shift 2 ;;
      --ram) VM_MEM_MB="$2"; shift 2 ;;
      --disk) VM_DISK_SIZE="$2"; shift 2 ;;
      --no-ks) GENERATE_KS=false; shift ;;
      --no-monitor) MONITOR_REBOOT=false; shift ;;
      --autopart) AUTO_PARTITION=true; shift ;;
      --iso) ISO_PATH="$2"; shift 2 ;;
      --variant) ISO_VARIANT="$2"; shift 2 ;;
      --user) VM_USER="$2"; shift 2 ;;
      --pass) VM_PASS="$2"; shift 2 ;;
      --domain) VM_LAB_DOMAIN="$2"; shift 2;;
      --mac-address) VM_LAB_MAC="$2"; shift 2;;
      --help) print_usage; exit 0 ;;
      *) echo "❌ Unknown option: $1"; print_usage; exit 1 ;;
    esac
  done

    # Required: ISO path and variant
    if [[ -z "$ISO_PATH" || -z "$ISO_VARIANT" ]]; then
    echo "❌ Missing required arguments."
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

  case "$ISO_VARIANT" in
    ubuntu) GENERATE_KS=false ;;
    RHCoreOS|RHCOS) GENERATE_KS=false; MONITOR_REBOOT=false ;;
    rhel) ;; # Accept RHEL in general
    *) echo "❌ Unsupported ISO variant: $ISO_VARIANT"; exit 1 ;;
  esac

  if [[ "$ISO_VARIANT" =~ ^(RHCoreOS|RHCOS)$ ]] then 
  if [[ "$AUTO_PARTITION" == false ]]; then
    echo "❌ For RHCoreOS, you must use --autopart (manual partitioning is not supported)."
    exit 1
  fi
  if [[ -z "$VM_LAB_MAC" ]]; then
    echo "❌ For RHCoreOS, you must specify MAC Address for the VM."
    exit 1
  fi
  fi
  shopt -u nocasematch
}

# ==== CHECK FOR REQUIRED PACKAGES ON HOST
function check_required_packages() {
  echo "🔍 Checking for required packages..."
  local packages=(libvirt virt-install qemu-kvm genisoimage nmap-ncat tmux)
  local missing=()

  for pkg in "${packages[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "⚠️  The following packages are missing: ${missing[*]}"
    echo "⏳ Installing required packages..."
    sudo dnf install -y "${missing[@]}"
  else
    echo "✅ All required packages already installed."
  fi
}

# ==== PREPARE NETWORK CONTEXT ====
function prepare_network_context() {
  echo "🌐 Preparing network context from 'virbr0'..."
  local net_xml
  net_xml=$(sudo virsh net-dumpxml default)

  HOST_IP=$(echo "$net_xml" | grep "<ip address" | sed -n "s/.*address='\([^']*\)'.*/\1/p")
  NETMASK=$(echo "$net_xml" | grep "<ip address" | sed -n "s/.*netmask='\([^']*\)'.*/\1/p")

  if [[ -z "$HOST_IP" || -z "$NETMASK" ]]; then
    echo "❌ Could not parse virbr0 network. Is the 'default' network up?"
    exit 1
  fi

  if [[ "$NETMASK" != "255.255.255.0" ]]; then
    echo "❌ Only /24 networks are supported currently. Detected $NETMASK"
    exit 1
  fi

  IFS=. read -r A B C D <<< "$HOST_IP"
  NETWORK_BASE="$A.$B.$C.0"
  NETWORK_CIDR="$A.$B.$C.0/24"
  GATEWAY="$HOST_IP"
  PREFIX=24
  REVERSE_ZONE="$C.$B.$A.in-addr.arpa"
}

function assign_vm_ip() {
  prepare_network_context
  echo "🔍 Assigning VM IP in $NETWORK_CIDR..."
  for _ in {1..10}; do
    LAST=$(shuf -i 2-254 -n1)
    VM_IP="$A.$B.$C.$LAST"
    if ! nc -z "$VM_IP" 22 2>/dev/null; then break; fi
  done

  if nc -z "$VM_IP" 22 2>/dev/null; then
    echo "❌ No free IP address found in $NETWORK_CIDR"
    exit 1
  fi

  echo "✅ Assigned VM IP: $VM_IP (gateway $GATEWAY)"
}

function generate_kickstart_file() {
  echo "📄 Generating Kickstart file..."
  local ks_path="$KS_FILE"
  local BOOT_MB=1024 SWAP_MB=2048 OVERHEAD_MB=1024
  TOTAL_MB=$((VM_DISK_SIZE * 1024))
  AVAILABLE_MB=$((TOTAL_MB - BOOT_MB - SWAP_MB - OVERHEAD_MB))
  ROOT_MB=$((AVAILABLE_MB * ROOT_RATIO / 100))
  HOME_MB=$((AVAILABLE_MB * HOME_RATIO / 100))
  DATA_MB=$((AVAILABLE_MB * DATA_RATIO / 100))

  local LAST_OCTET="${VM_IP##*.}"

  sudo tee "$ks_path" > /dev/null <<EOF
#version=RHEL9
cdrom
lang en_US.UTF-8
keyboard us
timezone Asia/Ho_Chi_Minh --utc
network --bootproto=static --ip=$VM_IP --netmask=255.255.255.0 --gateway=$GATEWAY --nameserver=$VM_IP --device=link --activate --hostname=$VM_NAME
rootpw --plaintext $VM_PASS
user --name=$VM_USER --password=$VM_PASS --plaintext --groups=wheel
firewall --enabled --service=ssh,ntp,dns,nfs,mountd,rpc-bind
selinux --enforcing
bootloader --append="rhgb quiet crashkernel=auto"
zerombr
clearpart --all --initlabel
EOF

  if [[ "$AUTO_PARTITION" == true ]]; then
    echo "autopart" | sudo tee -a "$ks_path" > /dev/null
  else
    sudo tee -a "$ks_path" > /dev/null <<PART
part /boot --fstype="xfs" --size=$BOOT_MB --ondisk=vda
part swap --size=$SWAP_MB --ondisk=vda
part / --fstype="xfs" --size=$ROOT_MB --ondisk=vda
part /home --fstype="xfs" --size=$HOME_MB --ondisk=vda
part /data --fstype="xfs" --size=$DATA_MB --ondisk=vda
PART
  fi

  sudo tee -a "$ks_path" > /dev/null <<EOF
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
python3-pyyaml
ncurses
which
diffutils
nmstate 
net-tools
podman
skopeo
coreos-installer
%end

%post --interpreter=/bin/bash
cat > /etc/named.conf <<NAMEDCONF
options {
    listen-on port 53 { 127.0.0.1; $VM_IP; };
    directory       "/var/named";
    allow-query     { any; };
    forwarders { $GATEWAY; };
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

chown root:named /var/named/*.zone
chmod 640 /var/named/*.zone
systemctl enable --now named

echo "allow $NETWORK_CIDR" >> /etc/chrony.conf
systemctl enable --now chronyd

chmod 777 /data
chown -R nobody:nobody /data
semanage fcontext -a -t public_content_rw_t "/data(/.*)?"
restorecon -Rv /data
echo "/data *(rw,sync,no_subtree_check)" >> /etc/exports
systemctl enable --now nfs-server rpcbind

# Enable Window List extension for the user
su - $VM_USER -c 'gsettings set org.gnome.shell enabled-extensions "[\"window-list@gnome-shell-extensions.gcampax.github.com\"]"'

%end

reboot
EOF
}

# ==== CHECK VM EXIST ====
function check_existing_vm() {
  if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "⚠️  VM '$VM_NAME' already exists."
    read -p "❓ Do you want to delete it and continue? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "🧹 Cleaning up existing VM '$VM_NAME'..."
      sudo virsh destroy "$VM_NAME" 2>/dev/null || true
      sudo virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    else
      read -p "📝 Enter a new VM name: " new_vm_name
      VM_NAME="$new_vm_name"
      echo "🔁 New VM will be created as '$VM_NAME'"
    fi
  fi
}

# ==== INSTALL ====
function start_vm_installation() {
  echo "🚀 Starting VM installation for $ISO_VARIANT..."
  local disk_path="$VM_IMG_DIR/${VM_NAME}.qcow2"
  sudo qemu-img create -f qcow2 "$disk_path" ${VM_DISK_SIZE}G

  shopt -s nocasematch
  if [[ "$GENERATE_KS" == false && "$ISO_VARIANT" =~ ubuntu ]]; then
    sudo virt-install --name "$VM_NAME" --memory "$VM_MEM_MB" --vcpus "$VM_CPU" \
      --disk path="$disk_path",format=qcow2 --os-variant ubuntu20.04 \
      --network network=default --graphics vnc --cdrom "$ISO_PATH" --noautoconsole
    return
  fi

  if [[ "$GENERATE_KS" == false && "$ISO_VARIANT" =~ ^(RHCoreOS|RHCOS)$ ]]; then
    echo "Installing Openshift Single Node Cluster..."
    sudo virt-install \
    --name "$VM_NAME" \
    --memory "$VM_MEM_MB" \
    --vcpus "$VM_CPU" \
    --disk path="$disk_path",format=qcow2 \
    --disk path="$ISO_PATH",device=cdrom,readonly=on \
    --network network=default,mac="$VM_LAB_MAC" \
    --os-variant rhel8-unknown \
    --boot cdrom,hd \
    --graphics vnc \
    --noautoconsole

    return
  fi
  shopt -u nocasematch

  sudo virt-install --name "$VM_NAME" --memory "$VM_MEM_MB" --vcpus "$VM_CPU" \
    --os-variant rhel9.0 --disk path="$disk_path",format=qcow2 \
    --network network=default --graphics vnc --noautoconsole \
    --location "$ISO_PATH" --initrd-inject "$KS_FILE" \
    --extra-args "inst.ks=file:/$KS_FILE" \
    --events on_reboot=restart
}

# ==== MONITOR ====
function monitor_vm_state() {
  echo -e "\n⏳ Monitoring VM reboot (shutdown → startup)..."

  SPINNER='/-\|'
  SPINNER_INTERVAL=0.25
  STATE_CHECK_INTERVAL=10
  i=0
  last_check=0
  seen_shutdown=0
  VM_STATE="unknown"

  while true; do
    now=$(date +%s)
    if (( now - last_check >= STATE_CHECK_INTERVAL )); then
      VM_STATE=$(sudo virsh domstate "$VM_NAME" 2>/dev/null)
      last_check=$now

      if [[ "$VM_STATE" == "shut off" && $seen_shutdown -eq 0 ]]; then
        echo -e "\n✅ VM has shut off after installation."
        seen_shutdown=1
      fi

      if [[ $seen_shutdown -eq 1 && "$VM_STATE" == "running" ]]; then
        echo -e "\n✅ VM is now running after reboot."
        break
      fi

      if [[ $seen_shutdown -eq 1 && "$VM_STATE" == "shut off" ]]; then
        echo -ne "\r🔄 VM is still off. Attempting to start..."
        sudo virsh start "$VM_NAME" &>/dev/null || echo -n " (already active)"
      fi
    fi

    printf "\r[%c] Monitoring VM state: %s" "${SPINNER:i:1}" "$VM_STATE"
    i=$(( (i+1) % ${#SPINNER} ))
    sleep $SPINNER_INTERVAL
  done
}

# Function to show a spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp="${spinstr#?}"
        printf "[ %c ] Waiting for services..." "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf "[ ] Waiting for services... Done\n"
}


# ==== DONE ====
function print_finish_message() {
  # Simulate a background process (example: sleep for 10 seconds)
  sleep 10 &

  # Call the spinner function while the background task is running
  spinner

  shopt -s nocasematch
  if [[ "$GENERATE_KS" == false && "$ISO_VARIANT" =~ ^(RHCoreOS|RHCOS)$ ]]; then
    VM_LAB_MAC=$(virsh dumpxml "$VM_NAME" | grep -oP 'mac address="\K[^"]+')
    VM_IP=$(virsh domifaddr "$VM_NAME" | grep -oP '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' | head -n 1)
    VM_USER=core
    VM_PASS="(not available)"
  fi
  shopt -u nocasematch

  echo
cat <<EOF
===== FINISH =====
VM is ready!

  Name:        $VM_NAME
  ISO:         $ISO_PATH
  Username:    $VM_USER
  Password:    $VM_PASS
  IP Address:  $VM_IP
  MAC Address: $VM_LAB_MAC
EOF

if [[ "$GENERATE_KS" == true ]]; then
  echo
  cat <<EOF
To connect:
    ssh $VM_USER@$VM_IP
EOF

    echo -e "\n✅ Verifying services on VM ($VM_IP)..."
    echo -n "- DNS (port 53):     "; nc -zvw1 $VM_IP 53 && echo OK || echo FAILED
    echo -n "- NTP (port 123/udp): "; nc -u -zvw1 $VM_IP 123 && echo OK || echo FAILED
    echo -n "- NFS (port 2049):   "; nc -zvw1 $VM_IP 2049 && echo OK || echo FAILED
  fi
}

# ==== MAIN ====
parse_arguments "$@"

check_existing_vm

# 👉 Tính toán mạng và gán IP trước khi generate KS
if [[ "$GENERATE_KS" == true ]]; then
  assign_vm_ip
  generate_kickstart_file
fi

start_vm_installation

[[ "$MONITOR_REBOOT" == true ]] && monitor_vm_state

print_finish_message
