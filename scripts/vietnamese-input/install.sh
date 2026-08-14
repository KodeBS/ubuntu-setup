#!/usr/bin/env bash
# Bộ gõ tiếng Việt: ibus-bamboo (khuyên dùng cho GNOME/Ubuntu) hoặc ibus-unikey.
# Ref: https://github.com/BambooEngine/ibus-bamboo#cài-đặt
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

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

# --- nạp engine mới vào registry của ibus ---------------------------------------
# Phải làm TRƯỚC khi ghi gsettings: gnome-shell đối chiếu từng entry 'ibus' trong
# input-sources với registry, entry nào ibus chưa biết thì nó bỏ qua — set xong mà
# Settings vẫn trống.
log "Nạp engine vào registry ibus"
ibus write-cache >/dev/null 2>&1 || true
ibus restart      >/dev/null 2>&1 || (setsid ibus-daemon -drx >/dev/null 2>&1 &) || true

# --- thêm engine vào Input Sources của GNOME ------------------------------------
# Không có bước này thì phải vào Settings > Keyboard > Input Sources bấm "+" bằng
# tay: ibus đã có engine nhưng GNOME không biết để đưa vào danh sách chuyển.
#
# Key `sources` kiểu a(ss): [('xkb', 'us'), ('ibus', 'Bamboo')]. Phần tử ĐẦU là
# input source lúc mới login, nên engine tiếng Việt phải nằm SAU 'xkb' — để lên
# đầu thì mỗi lần đăng nhập là đang ở chế độ gõ tiếng Việt, gõ lệnh terminal ra
# toàn dấu.
add_gnome_input_source() {
  has gsettings || { warn "Không có gsettings — tự thêm '$ENGINE_ID' trong Settings > Keyboard."; return 0; }
  gsettings list-schemas 2>/dev/null | grep -qx org.gnome.desktop.input-sources \
    || { dim "Không phải desktop GNOME, bỏ qua bước thêm input source."; return 0; }

  local key=org.gnome.desktop.input-sources cur new
  cur="$(gsettings get "$key" sources 2>/dev/null || echo '')"

  # So khớp cả 2 dấu nháy để '$ENGINE_ID' không ăn nhầm biến thể khác cùng tiền tố
  # (ibus-bamboo đăng ký 7 engine: Bamboo, Bamboo::Us, BambooUs, ...).
  if [[ "$cur" == *"'$ENGINE_ID'"* ]]; then
    ok "Input source '$ENGINE_ID' đã có trong GNOME."
    return 0
  fi

  if [[ -z "$cur" || "$cur" == "@a(ss) []" || "$cur" == "[]" ]]; then
    new="[('ibus', '$ENGINE_ID')]"
  else
    new="${cur%]}, ('ibus', '$ENGINE_ID')]"
  fi

  if gsettings set "$key" sources "$new"; then
    ok "Đã thêm input source: $new"
  else
    warn "Không ghi được input-sources — tự thêm '$ENGINE_ID' trong Settings > Keyboard."
  fi
}
add_gnome_input_source

ok "Đã cài $ENGINE_ID."
cat <<EOF

Bước cuối:
  1. Logout / reboot để ibus nạp engine mới (BẮT BUỘC — Wayland không cho nạp
     engine vào session đang chạy).
  2. Chuyển bộ gõ bằng Super+Space (Shift+Super+Space để lùi lại).

Input source đã được thêm tự động, KHÔNG cần vào Settings > Keyboard bấm "+".
Kiểm tra: gsettings get org.gnome.desktop.input-sources sources
EOF
