## **Ví dụ sử dụng:**

### **1. Deploy từ ISO (RHEL/CentOS):**
```bash
./vcenter_deploy.sh \
  --vcenter-server vcenter.lab.local \
  --vcenter-user administrator@vsphere.local \
  --vcenter-pass VMware123! \
  --vcenter-datacenter "Lab DC" \
  --vcenter-cluster "Cluster1" \
  --vcenter-datastore "datastore1" \
  --vcenter-portgroup "VM Network" \
  --iso "[datastore1] ISO/rhel-9.2-x86_64-dvd.iso" \
  --variant RHEL \
  --vm-ip 192.168.1.100 \
  --vm-gateway 192.168.1.1 \
  --vm-dns 192.168.1.1 \
  --user admin \
  --pass RedHat123! \
  --name bastion-vm \
  --cpu 4 \
  --ram 8 \
  --disk 200
```

### **2. Deploy từ Template (Ubuntu):**
```bash
./vcenter_deploy.sh \
  --vcenter-server vcenter.lab.local \
  --vcenter-user administrator@vsphere.local \
  --vcenter-pass VMware123! \
  --vcenter-datacenter "Lab DC" \
  --vcenter-cluster "Cluster1" \
  --vcenter-datastore "datastore1" \
  --vcenter-portgroup "VM Network" \
  --vcenter-template "ubuntu-20.04-template" \
  --variant Ubuntu \
  --vm-ip 192.168.1.101 \
  --vm-gateway 192.168.1.1 \
  --vm-dns 192.168.1.1 \
  --user ubuntu \
  --pass Ubuntu123!
```

### **3. Deploy với custom folder:**
```bash
./vcenter_deploy.sh \
  --vcenter-server vcenter.lab.local \
  --vcenter-user administrator@vsphere.local \
  --vcenter-pass VMware123! \
  --vcenter-datacenter "Lab DC" \
  --vcenter-cluster "Cluster1" \
  --vcenter-datastore "datastore1" \
  --vcenter-portgroup "VM Network" \
  --vcenter-folder "Lab VMs" \
  --iso "[datastore1] ISO/rhel-9.2-x86_64-dvd.iso" \
  --variant RHEL \
  --vm-ip 192.168.1.102 \
  --vm-gateway 192.168.1.1 \
  --vm-dns 192.168.1.1 \
  --user labuser \
  --pass Lab123!
```

## **Yêu cầu hệ thống:**

### **1. Cài đặt PowerShell Core:**
```bash
# RHEL/CentOS/Fedora
sudo dnf install -y powershell

# Ubuntu/Debian
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update
sudo apt install -y powershell
```

### **2. Script sẽ tự động cài VMware PowerCLI:**
- Không cần cài thủ công
- Script tự động kiểm tra và cài đặt PowerCLI module

## **Tính năng đặc biệt:**

### **1. Kickstart tự động:**
- Tạo kickstart file với partition layout tùy chỉnh
- Upload lên datastore
- Cấu hình VM boot với kickstart parameters

### **2. Services được cài đặt:**
- **DNS Server**: BIND9 với zone configuration
- **NTP Server**: Chrony với network time sync
- **NFS Server**: Shared storage tại `/data`
- **VMware Tools**: Tự động cài đặt và enable

### **3. Network Configuration:**
- Static IP configuration
- DNS server setup
- Gateway và subnet configuration
- Tự động tạo DNS records

### **4. Monitoring:**
- Theo dõi quá trình cài đặt
- Detect VM shutdown/restart cycle
- Verify services sau khi hoàn thành

## **Troubleshooting:**

### **1. PowerCLI Certificate Issues:**
```bash
# Nếu gặp lỗi certificate, chạy:
pwsh -c "Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:\$false"
```

### **2. Datastore Path Format:**
- ISO phải ở format: `[datastore_name] path/to/file.iso`
- Ví dụ: `[datastore1] ISO/rhel-9.2.iso`

### **3. Network Connectivity:**
- Đảm bảo script host có thể kết nối tới vCenter
- Port 443 (HTTPS) phải mở từ script host tới vCenter

### **4. Permissions:**
- User cần quyền:
  - Create VM
  - Modify VM configuration
  - Access datastore
  - Manage VM power state

Script này giữ nguyên logic và tính năng của script gốc nhưng được chuyển đổi hoàn toàn để làm việc với VMware vCenter thay vì libvirt/KVM.