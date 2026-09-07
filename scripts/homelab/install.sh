#!/usr/bin/env bash
# KodeBS Homelab — app desktop biến một máy thành home server (monitor, Docker,
# port, Nginx, UFW, direct link, task nền).
#
# Cài qua apt repo riêng của KodeBS thay vì tải .deb: cài xong thì app lên bản
# mới cùng lượt `apt upgrade` như mọi gói khác trên máy.
# Ref: https://kodebs.github.io/apt · https://github.com/KodeBS/homelab
#
# Env:
#   KODEBS_APT_URL=<url>   trỏ sang mirror/repo khác (mặc định GitHub Pages).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

APT_URL="${KODEBS_APT_URL:-https://kodebs.github.io/apt}"
KEYRING=/etc/apt/keyrings/kodebs.asc
SOURCES=/etc/apt/sources.list.d/kodebs.sources
PKG=kodebs-homelab

require_ubuntu
need_sudo

# Repo chỉ build amd64. Dừng sớm chứ đừng thêm repo rồi để apt báo "không tìm
# thấy gói" — người dùng sẽ tưởng repo hỏng.
arch="$(dpkg --print-architecture)"
[[ "$arch" == amd64 ]] || die "KodeBS Homelab chỉ có bản amd64 (máy này: $arch)."

apt_install curl

# --- signing key ---------------------------------------------------------------
# Tải ra file tạm rồi mới kiểm tra: WiFi captive portal hay trang 404 cũng trả về
# 200 kèm HTML, ghi thẳng đè lên keyring thì apt chỉ báo một lỗi rất khó đoán.
log "Lấy signing key của KodeBS"
tmpkey="$(mktemp)"
trap 'rm -f "$tmpkey"' EXIT
curl -fsSL "${CURL_RETRY[@]}" "$APT_URL/kodebs.asc" -o "$tmpkey" \
  || die "Không tải được $APT_URL/kodebs.asc"
grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$tmpkey" \
  || die "$APT_URL/kodebs.asc trả về thứ gì đó không phải PGP key."

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 "$tmpkey" "$KEYRING"
ok "Đã tin key: $KEYRING"

# --- repo ----------------------------------------------------------------------
# Ghi đè mỗi lần chạy (nội dung cố định) nên chạy lại bao nhiêu lần cũng được.
sudo tee "$SOURCES" >/dev/null <<EOF
Types: deb
URIs: $APT_URL
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING
EOF
ok "Đã thêm repo: $SOURCES"

apt_invalidate_update   # vừa thêm repo -> phải update lại
apt_install "$PKG"

# smartmontools chỉ là `recommends`. Ubuntu desktop mặc định bật
# Install-Recommends nên thường có sẵn, nhưng máy cài kiểu tối giản thì không —
# thiếu nó trang Disks mất phần SMART.
if ! has smartctl; then
  if confirm "Cài smartmontools để trang Disks đọc được SMART?"; then
    apt_install smartmontools
  else
    dim "Bỏ qua smartmontools — trang Disks vẫn chạy, chỉ không có SMART."
  fi
fi

ok "Xong KodeBS Homelab. Mở từ app grid, hoặc chạy: kodebs-homelab"
dim "Nâng cấp sau này đi chung với: sudo apt upgrade"
