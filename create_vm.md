# Tài liệu hướng dẫn `create_vm.sh`

## 📌 Giới thiệu tổng quan

Script `create_vm.sh` được thiết kế để **tự động hóa quá trình tạo và cài đặt máy ảo (VM)** trên nền tảng **libvirt/KVM** sử dụng công cụ `virt-install`.  
Script có thể chạy trên các hệ điều hành **Fedora, RHEL, CentOS Stream, AlmaLinux, Rocky Linux**, hoặc bất kỳ distro nào hỗ trợ libvirt.

### ✨ Mục đích sử dụng:

- Triển khai nhanh một VM với RHEL, Ubuntu hoặc RHCoreOS
- Tùy chọn chia ổ đĩa theo tỉ lệ (/, /home, /data)
- Cấu hình dịch vụ nội bộ: DNS, NTP, NFS tự động
- Tùy chọn sử dụng Kickstart hoặc không (tùy theo loại OS)

---

## 🧰 Các tính năng chính

- Khởi tạo VM mới (có hỗ trợ xóa VM cũ nếu trùng tên)
- Tự gán IP tĩnh từ dải mạng `virbr0` (libvirt default)
- Hỗ trợ chia ổ đĩa theo tỉ lệ tùy chọn
- Sinh file Kickstart tự động cho RHEL/CentOS
- Theo dõi quá trình reboot sau cài đặt
- Kiểm tra hoạt động của DNS, NTP, NFS sau khi khởi động

---

## 🚀 Ví dụ sử dụng: tạo VM với RHEL

```bash
./create_vm.sh \
  --iso /home/user/Downloads/rhel-9.5-x86_64-dvd.iso \
  --variant RHEL \
  --user admin \
  --pass secret123 \
  --name bastion \
  --domain rhlab.local \
  --cpu 4 --ram 8192 --disk 200
```

> 📦 VM sẽ được cài đặt qua Kickstart với domain do người dùng định nghĩa, chia ổ theo mặc định: / 30%, /home 20%, /data 50%  
> Các dịch vụ DNS, NTP, NFS được cấu hình và kích hoạt sẵn

---

## 🧱 Ví dụ sử dụng: tạo VM với RHCoreOS

```bash
./create_vm.sh \
  --iso /home/user/Downloads/rhcos-live.x86_64.iso \
  --variant RHCoreOS \
  --name coreos-node \
  --cpu 2 --ram 4096 --disk 40 \
  --autopart --no-monitor
```

> ✅ Không cần khai báo `--user`, `--pass`.  
> Script sẽ khởi tạo VM và thực hiện cài đặt từ ISO với `coreos.inst.install_dev=vda`.

---

## 💾 Cách chia phân vùng

Script sử dụng 3 biến tùy chỉnh để xác định tỉ lệ dung lượng:

```bash
ROOT_RATIO=30
HOME_RATIO=20
DATA_RATIO=50
```

Dung lượng phân vùng được tính toán như sau:

```bash
TOTAL_MB = VM_DISK_SIZE * 1024
AVAILABLE_MB = TOTAL_MB - BOOT_MB - SWAP_MB - OVERHEAD_MB

ROOT_MB = AVAILABLE_MB * ROOT_RATIO / 100
...
```

> ⚠️ Tổng của `ROOT_RATIO + HOME_RATIO + DATA_RATIO` nên < 100 để tránh lỗi cài đặt

---

## ⚙️ Các dịch vụ được cấu hình trong VM (RHEL)

Sau khi cài đặt, VM sẽ có sẵn các dịch vụ:

| Dịch vụ | File cấu hình | Ghi chú |
|--------|----------------|--------|
| **BIND DNS** | `/etc/named.conf`, `/var/named/*.zone` | Sinh zone `<domain>` và reverse DNS |
| **Chrony NTP** | `/etc/chrony.conf` | Cho phép subnet `<subnet của virb0>` |
| **NFS Server** | `/etc/exports` | Chia sẻ thư mục `/data` cho subnet |

Sau khi VM khởi động, script sẽ kiểm tra tự động các cổng:

- DNS: `port 53`
- NTP: `port 123/udp`
- NFS: `port 2049`

---

## 📂 Vị trí file cấu hình (trong VM)

| Thành phần         | Đường dẫn                      |
|--------------------|--------------------------------|
| BIND config        | `/etc/named.conf`              |
| Zone file          | `/var/named/<domain>.zone`     |
| Reverse zone file  | `/var/named/<reverse>.rev`     |
| Chrony             | `/etc/chrony.conf`             |
| NFS export         | `/etc/exports`                 |

Bạn có thể SSH vào VM và sửa trực tiếp các file trên nếu muốn tùy chỉnh sau này.

---

## 📌 Ghi chú cuối cùng

- Script chỉ hỗ trợ mạng **/24 subnet** qua `virbr0`
- Bạn nên sử dụng **GNOME Boxes, virt-manager hoặc Cockpit** để quan sát thêm
- Nếu cài với GUI, bạn có thể thêm `gnome-terminal`, `firefox`, `tmux` v.v. vào `%packages`
---

## ✅ Tương thích Kickstart với các hệ điều hành

Script sử dụng Kickstart chủ yếu cho các bản phân phối RHEL-like. Dưới đây là mức độ tương thích với các hệ điều hành phổ biến:

| Hệ điều hành       | Hỗ trợ Kickstart | Ghi chú đặc biệt |
|--------------------|------------------|------------------|
| **RHEL**           | ✅ Chính thức    | Là nơi định nghĩa Kickstart, hỗ trợ đầy đủ nhất |
| **CentOS Stream**  | ✅ Tốt            | Dựa trên RHEL, hoàn toàn tương thích |
| **AlmaLinux**      | ✅ Tốt            | RHEL-compatible binary fork, hỗ trợ Kickstart |
| **Rocky Linux**    | ✅ Tốt            | Cũng là fork của RHEL, tương thích hoàn toàn |
| **Fedora**         | ✅ Nhưng cần chỉnh | Một số biến thể khác nhỏ, package set có thể thay đổi |

### 📝 Gợi ý nếu sử dụng trên Fedora:

- Sử dụng nhóm phần mềm như `@gnome-desktop-environment` thay vì `@^graphical-server-environment`
- Tránh hard-code các gói có thể không tồn tại trên Fedora như `nfs-utils` (dù vẫn khả dụng)
- Đảm bảo không dùng repo hoặc gói nội bộ của RHEL

Nếu cần hỗ trợ nhiều nền tảng, bạn có thể thêm logic phát hiện `variant` trong script để sinh Kickstart tương ứng.

