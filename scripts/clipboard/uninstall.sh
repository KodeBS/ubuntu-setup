#!/usr/bin/env bash
# Gỡ GNOME extension Clipboard Indicator + trả Super+V về cho message tray.
#
# Không gỡ wl-clipboard: nó là gói dùng chung (git.sh dùng để copy public key),
# và nằm ở module base.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu

UUID="${CLIPBOARD_EXT_UUID:-clipboard-indicator@tudmotu.com}"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"

# Chạy trên máy không phải GNOME thì không có gì để gỡ — thoát êm, đừng làm hỏng
# cả run `uninstall.sh --all`.
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]] || ! has gsettings; then
  warn "Không phải session GNOME — bỏ qua module clipboard."
  exit 0
fi

# --- helper GVariant kiểu 'as' ---------------------------------------------------
gv_split() { grep -o "'[^']*'" <<<"${1:-}" | tr -d "'" || true; }
gv_pack() {
  local out="" x
  for x in "$@"; do out+="'${x}', "; done
  printf "[%s]" "${out%, }"
}

# --- 1. tắt & gỡ extension --------------------------------------------------------
disable_extension() {
  has gnome-extensions && gnome-extensions disable "$UUID" >/dev/null 2>&1 || true

  local list keep=() p removed=0
  list="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '@as []')"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == "$UUID" ]]; then removed=1; else keep+=("$p"); fi
  done < <(gv_split "$list")

  if (( removed )); then
    gsettings set org.gnome.shell enabled-extensions "$(gv_pack "${keep[@]+"${keep[@]}"}")"
    ok "Đã gỡ $UUID khỏi enabled-extensions."
  else
    dim "$UUID không nằm trong enabled-extensions."
  fi
}

remove_extension() {
  if has gnome-extensions && gnome-extensions uninstall "$UUID" >/dev/null 2>&1; then
    ok "Đã gỡ extension $UUID."
  elif [[ -d "$EXT_DIR" ]]; then
    safe_rm "$EXT_DIR" && ok "Đã xoá $EXT_DIR." || warn "Không xoá được $EXT_DIR."
  else
    dim "Không thấy extension $UUID trên máy."
  fi
}

# --- 2. trả Super+V về message tray ----------------------------------------------
# clipboard.sh đã gỡ <Super>v khỏi toggle-message-tray; reset để GNOME lấy lại
# giá trị mặc định của bản shell đang chạy.
restore_shortcut() {
  local cur
  cur="$(gsettings get org.gnome.shell.keybindings toggle-message-tray 2>/dev/null || echo '')"
  if [[ "$cur" == *"<Super>v"* ]]; then
    dim "toggle-message-tray vẫn đang giữ <Super>v, không cần đổi."
    return 0
  fi
  gsettings reset org.gnome.shell.keybindings toggle-message-tray 2>/dev/null \
    && ok "Đã trả Super+V về cho message tray (mặc định GNOME)." \
    || warn "Không reset được toggle-message-tray."
}

disable_extension
remove_extension
restore_shortcut

# --- 3. lịch sử clipboard (chỉ khi --purge) ---------------------------------------
if purging; then
  if has dconf; then
    dconf reset -f /org/gnome/shell/extensions/clipboard-indicator/ 2>/dev/null || true
  fi
  safe_rm "$HOME/.cache/clipboard-indicator@tudmotu.com" "$HOME/.cache/$UUID" \
    && ok "Đã xoá cấu hình + lịch sử clipboard." \
    || warn "Còn sót cache clipboard."
else
  dim "Giữ lịch sử clipboard trong ~/.cache/$UUID (cài lại là còn nguyên)."
fi

ok "Xong phần clipboard. Logout/reboot để GNOME Shell nạp lại không có extension."
