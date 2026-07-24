#!/usr/bin/env bash
# Clipboard manager: CopyQ + wl-clipboard, autostart, phím tắt Super+V.
#
# Chọn CopyQ vì nó là app standalone — không phải GNOME Shell extension nên
# không vỡ mỗi lần GNOME lên major version (GPaste trong kho Ubuntu 26.04 vẫn
# là bản 45.x trong khi shell đã là GNOME 50).
#
# Ref: https://github.com/hluk/CopyQ
#      https://copyq.readthedocs.io/en/latest/command-line.html
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

SHORTCUT="${CLIPBOARD_SHORTCUT:-<Super>v}"
# `menu` = popup cạnh con trỏ (giống Super+V của Windows). Đổi thành
# `copyq toggle` nếu thích cửa sổ chính đầy đủ.
COMMAND="${CLIPBOARD_COMMAND:-copyq menu}"

apt_install copyq wl-clipboard

# --- autostart ----------------------------------------------------------------
# Chỉ chạy server nền; không bung cửa sổ chính mỗi lần login.
#
# QT_QPA_PLATFORM=xcb là BẮT BUỘC trên Wayland. Nếu để Qt tự chọn, CopyQ chạy
# như Wayland client thuần và Wayland cấm app nền đọc clipboard -> lịch sử luôn
# rỗng, bấm phím tắt tưởng như không có tác dụng. Ép qua XWayland thì Mutter cầu
# nối clipboard X11<->Wayland và CopyQ theo dõi được.
AUTOSTART="$HOME/.config/autostart/copyq.desktop"
mkdir -p "$(dirname "$AUTOSTART")"
cat >"$AUTOSTART" <<'EOF'
[Desktop Entry]
Type=Application
Name=CopyQ
Comment=Clipboard manager (chạy nền)
Exec=env QT_QPA_PLATFORM=xcb copyq --start-server
Icon=com.github.hluk.copyq
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
ok "autostart: $AUTOSTART"

# --- phím tắt (GNOME) ---------------------------------------------------------
# Trên Wayland app không tự đăng ký được global shortcut, nên phím tắt trong
# Preferences của CopyQ sẽ không ăn. Phải đăng ký qua custom keybinding của GNOME.

# Tách/ghép GVariant kiểu 'as' — gsettings trả về dạng ['a', 'b'] hoặc @as [].
gv_split() { grep -o "'[^']*'" <<<"${1:-}" | tr -d "'" || true; }
gv_pack() {
  local out="" x
  for x in "$@"; do out+="'${x}', "; done
  printf "[%s]" "${out%, }"
}

setup_gnome_shortcut() {
  has gsettings || { warn "Không có gsettings, bỏ qua phần phím tắt."; return; }
  [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] \
    || { warn "Không phải session GNOME (${XDG_CURRENT_DESKTOP:-?}), bỏ qua phần phím tắt."; return; }

  # 1. Gỡ Super+V khỏi binding mặc định của GNOME (toggle-message-tray),
  #    nếu không hai bên tranh nhau và CopyQ thua.
  if [[ "$SHORTCUT" == "<Super>v" ]]; then
    local tray keep=() k
    tray="$(gsettings get org.gnome.shell.keybindings toggle-message-tray 2>/dev/null || echo '')"
    if [[ "$tray" == *"<Super>v"* ]]; then
      while IFS= read -r k; do
        [[ -n "$k" && "$k" != "<Super>v" ]] && keep+=("$k")
      done < <(gv_split "$tray")
      gsettings set org.gnome.shell.keybindings toggle-message-tray "$(gv_pack "${keep[@]+"${keep[@]}"}")"
      ok "Đã gỡ Super+V khỏi toggle-message-tray (notification tray vẫn còn Super+M)."
    fi
  fi

  local schema="org.gnome.settings-daemon.plugins.media-keys"
  local child="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
  local base="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

  local list existing=() p slot=""
  list="$(gsettings get "$schema" custom-keybindings 2>/dev/null || echo '@as []')"
  while IFS= read -r p; do [[ -n "$p" ]] && existing+=("$p"); done < <(gv_split "$list")

  # Đã có slot nào trỏ tới copyq thì ghi đè lên slot đó (chạy lại không đẻ thêm).
  for p in "${existing[@]+"${existing[@]}"}"; do
    if gsettings get "${child}:${p}" command 2>/dev/null | grep -q copyq; then
      slot="$p"; break
    fi
  done

  # Chưa có -> tìm customN còn trống.
  if [[ -z "$slot" ]]; then
    local n=0 candidate
    while :; do
      candidate="${base}/custom${n}/"
      [[ " ${existing[*]+"${existing[*]}"} " == *" $candidate "* ]] || break
      n=$((n + 1))   # không dùng ((n++)): trả exit 1 khi n=0, set -e sẽ giết script
    done
    slot="$candidate"
    existing+=("$slot")
    gsettings set "$schema" custom-keybindings "$(gv_pack "${existing[@]}")"
  fi

  gsettings set "${child}:${slot}" name    'CopyQ - Clipboard'
  gsettings set "${child}:${slot}" command "$COMMAND"
  gsettings set "${child}:${slot}" binding "$SHORTCUT"
  ok "Phím tắt $SHORTCUT -> $COMMAND  ($slot)"
}

setup_gnome_shortcut

# --- tinh chỉnh CopyQ ---------------------------------------------------------
# `copyq config` cần server đang chạy; chỉ làm được khi có session đồ hoạ.
tune_copyq() {
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || { dim "(không có session đồ hoạ, bỏ qua phần config CopyQ)"; return; }
  # Cùng lý do với autostart: phải qua XWayland thì mới theo dõi được clipboard.
  QT_QPA_PLATFORM=xcb setsid copyq --start-server >/dev/null 2>&1 </dev/null &
  local i
  for i in 1 2 3 4 5; do copyq size >/dev/null 2>&1 && break; sleep 1; done
  if ! copyq size >/dev/null 2>&1; then
    warn "Không kết nối được CopyQ server, bỏ qua phần config (mở app rồi chỉnh tay cũng được)."
    return
  fi
  copyq config maxitems 500        >/dev/null 2>&1 || true
  copyq config check_clipboard true >/dev/null 2>&1 || true
  copyq config save_filter_history true >/dev/null 2>&1 || true
  ok "CopyQ: maxitems=500, theo dõi clipboard bật."
}
tune_copyq

cat <<EOF

CopyQ đã sẵn sàng.
  • Bấm $SHORTCUT để mở lịch sử clipboard.
  • Phím tắt chỉ ăn sau khi logout/reboot.
  • Server luôn phải chạy với QT_QPA_PLATFORM=xcb. Chạy tay thì dùng:
      QT_QPA_PLATFORM=xcb copyq --start-server &
    Thiếu biến này CopyQ chạy như Wayland client thuần, không đọc được
    clipboard, lịch sử rỗng và phím tắt trông như bị liệt.
  • Kiểm tra nhanh: copy một đoạn text rồi chạy `copyq size` (phải > 0).
EOF
