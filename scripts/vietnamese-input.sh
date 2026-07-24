#!/usr/bin/env bash
# Bộ gõ tiếng Việt: ibus-bamboo (khuyên dùng cho GNOME/Ubuntu) hoặc ibus-unikey.
# Ref: https://github.com/BambooEngine/ibus-bamboo#cài-đặt
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

ENGINE="${VN_INPUT_ENGINE:-}"   # bamboo | unikey ; hỏi nếu để trống

if [[ -z "$ENGINE" ]]; then
  echo "Chọn bộ gõ tiếng Việt:"
  echo "  1) ibus-bamboo  (mặc định, hỗ trợ tốt Chrome/Electron)"
  echo "  2) ibus-unikey  (nhẹ, có sẵn trong kho Ubuntu)"
  read -r -p "Lựa chọn [1]: " choice </dev/tty || true
  case "${choice:-1}" in
    2) ENGINE=unikey ;;
    *) ENGINE=bamboo ;;
  esac
fi

apt_install ibus

case "$ENGINE" in
  bamboo)
    # PPA chính thức của BambooEngine. Nếu PPA chưa hỗ trợ codename mới (vd 26.04
    # ngay sau khi release), đặt VN_INPUT_PPA_CODENAME=noble để dùng bản cũ hơn.
    PPA_CODENAME="${VN_INPUT_PPA_CODENAME:-$OS_CODENAME}"
    log "Thêm PPA bamboo-engine/ibus-bamboo (codename: $PPA_CODENAME)"
    if ! sudo add-apt-repository -y "ppa:bamboo-engine/ibus-bamboo"; then
      die "Không thêm được PPA. Thử: VN_INPUT_PPA_CODENAME=noble $0"
    fi
    if [[ "$PPA_CODENAME" != "$OS_CODENAME" ]]; then
      sudo sed -i "s/${OS_CODENAME}/${PPA_CODENAME}/g" \
        /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.list 2>/dev/null || true
      sudo sed -i "s/Suites: ${OS_CODENAME}/Suites: ${PPA_CODENAME}/g" \
        /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.sources 2>/dev/null || true
    fi
    _APT_UPDATED=""   # ép update lại sau khi thêm PPA
    apt_install ibus-bamboo
    ENGINE_ID="Bamboo"
    ;;
  unikey)
    apt_install ibus-unikey
    ENGINE_ID="Unikey"
    ;;
  *) die "Engine không hợp lệ: $ENGINE" ;;
esac

# Đặt ibus làm input method mặc định
if has im-config; then
  im-config -n ibus || warn "im-config lỗi, bỏ qua."
fi

log "Khởi động lại ibus daemon"
ibus restart >/dev/null 2>&1 || (setsid ibus-daemon -drx >/dev/null 2>&1 &) || true

ok "Đã cài $ENGINE_ID."
cat <<EOF

Bước cuối (làm bằng tay 1 lần):
  1. Logout / reboot để ibus nạp engine mới.
  2. Settings > Keyboard > Input Sources > "+" > Vietnamese > chọn "$ENGINE_ID".
  3. Chuyển bộ gõ bằng Super+Space (hoặc phím tự đặt).
EOF
