#!/usr/bin/env bash
# Gỡ KodeBS Homelab + repo apt của KodeBS.
#
# MẶC ĐỊNH GIỮ dữ liệu app: ~/.config/KodeBS Homelab (settings.json). Gỡ gói
# không đụng tới nó, cài lại là mọi thiết lập trở về như cũ. Chỉ --purge mới xoá,
# và phải gõ 'yes'.
#
# Repo apt chỉ bị gỡ khi trên máy không còn gói KodeBS nào khác — gỡ 1 app mà
# cắt luôn đường update của các app còn lại thì quá tay.
#
# KHÔNG đụng tới những gì app đã cấu hình cho hệ thống: site Nginx, rule UFW,
# /etc/docker/daemon.json, xrdp. Đó là cấu hình server đang chạy, phải tự tay
# tháo trong app trước khi gỡ nếu muốn.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

KEYRING=/etc/apt/keyrings/kodebs.asc
SOURCES=/etc/apt/sources.list.d/kodebs.sources
PKG=kodebs-homelab

require_ubuntu
need_sudo

if pkg_installed "$PKG"; then
  apt_remove "$PKG"
else
  dim "$PKG chưa cài."
fi

# Entry autostart do chính app ghi vào ~/.config/autostart, dpkg không biết tới
# nó. Để lại thì mỗi lần đăng nhập desktop lại cố chạy một binary đã bị gỡ.
autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/kodebs-homelab.desktop"
if [[ -f "$autostart" ]]; then
  safe_rm "$autostart" && ok "Đã bỏ entry autostart." || warn "Không xoá được $autostart"
fi

# --- repo apt --------------------------------------------------------------------
# Còn gói KodeBS nào khác thì giữ repo lại.
others="$(dpkg-query -W -f='${binary:Package} ${Status}\n' 'kodebs-*' 2>/dev/null \
  | awk '$2" "$3" "$4 == "install ok installed" { print $1 }' \
  | grep -vx "$PKG" || true)"

if [[ -n "$others" ]]; then
  warn "Giữ repo KodeBS: còn gói khác đang dùng nó ($(echo "$others" | tr '\n' ' '))."
elif [[ -f "$SOURCES" || -f "$KEYRING" ]]; then
  safe_rm "$SOURCES" "$KEYRING" \
    && ok "Đã gỡ repo apt KodeBS." \
    || warn "Không dọn sạch được repo KodeBS."
fi

# --- dữ liệu người dùng ------------------------------------------------------------
data="${XDG_CONFIG_HOME:-$HOME/.config}/KodeBS Homelab"
if purging; then
  if [[ -e "$data" ]]; then
    if confirm_danger "Sắp xoá \"$data\" — mất toàn bộ thiết lập của app."; then
      safe_rm "$data" && ok "Đã xoá dữ liệu KodeBS Homelab." || warn "Còn sót dữ liệu."
    else
      dim "Giữ dữ liệu KodeBS Homelab."
    fi
  fi
else
  [[ -e "$data" ]] && dim "Giữ \"$data\"."
fi

cat <<'EOF'

Script không tự tháo những thứ app đã đổi trên hệ thống (còn nguyên và vẫn chạy):
  • site Nginx trong /etc/nginx/sites-enabled
  • rule UFW / cấu hình xrdp của Direct Link
  • /etc/docker/daemon.json (bản cũ nằm ở daemon.json.kodebs.bak)
Muốn sạch hẳn thì tắt từng thứ trong app TRƯỚC khi gỡ.
EOF

ok "Xong phần homelab."
