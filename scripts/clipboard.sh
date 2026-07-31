#!/usr/bin/env bash
# Clipboard manager: GNOME extension "Clipboard Indicator" + wl-clipboard,
# phím tắt Super+V. Tự gỡ CopyQ nếu máy còn bản cài cũ.
#
# Vì sao là extension chứ không phải app standalone:
#   Mutter/GNOME KHÔNG hỗ trợ wlr-data-control / ext-data-control (issue #524 vẫn
#   mở tới GNOME 50), nên mọi clipboard manager "Wayland-native" (cliphist, clipse,
#   greenclip, wl-clip-persist...) đều mù trên GNOME — kiểm chứng nhanh:
#       wl-paste --watch echo x
#       -> "Watch mode requires a compositor that supports the wlroots data-control protocol"
#   App standalone chỉ đọc được clipboard khi ép qua XWayland (CopyQ dùng cách này),
#   đổi lại UI Qt lạc lõng và mờ ở HiDPI. Extension chạy trong tiến trình GNOME Shell
#   nên dùng thẳng St.Clipboard, popup là widget GNOME thật.
#
# Ref: https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator
#      https://gitlab.gnome.org/GNOME/mutter/-/work_items/524
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu

UUID="${CLIPBOARD_EXT_UUID:-clipboard-indicator@tudmotu.com}"
SCHEMA="org.gnome.shell.extensions.clipboard-indicator"
SHORTCUT="${CLIPBOARD_SHORTCUT:-<Super>v}"
# Chọn item xong dán luôn vào ô đang focus (giống Super+V của Windows).
PASTE_ON_SELECT="${CLIPBOARD_PASTE_ON_SELECT:-true}"
# Popup hiện cạnh con trỏ thay vì rơi xuống từ panel.
OPEN_AT_CURSOR="${CLIPBOARD_OPEN_AT_CURSOR:-true}"

EXT_HOME="$HOME/.local/share/gnome-shell/extensions"
EXT_DIR="$EXT_HOME/$UUID"

[[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] \
  || die "Script này cần session GNOME (đang là: ${XDG_CURRENT_DESKTOP:-?})."
has gnome-extensions || die "Thiếu lệnh gnome-extensions (gói gnome-shell)."
has gsettings        || die "Thiếu gsettings."
has python3          || die "Thiếu python3 (dùng để đọc JSON của extensions.gnome.org)."

need_sudo
apt_install wl-clipboard curl unzip

# --- gỡ CopyQ cũ ---------------------------------------------------------------
# Để lại sẽ tranh Super+V với extension. Dùng `apt-get remove` chứ không `purge`:
# lịch sử clip cũ ở ~/.config/copyq được giữ nguyên, muốn xoá thì tự xoá.
remove_copyq() {
  local autostart="$HOME/.config/autostart/copyq.desktop"

  if pgrep -x copyq >/dev/null 2>&1; then
    copyq exit >/dev/null 2>&1 || pkill -x copyq >/dev/null 2>&1 || true
    ok "Đã tắt CopyQ server."
  fi

  # Chỉ xoá đúng file autostart do script này từng tạo, không đụng file lạ.
  if [[ -f "$autostart" ]] && grep -qi copyq "$autostart"; then
    rm -f "$autostart"
    ok "Đã xoá autostart cũ: $autostart"
  fi

  if dpkg -s copyq >/dev/null 2>&1; then
    log "Gỡ gói copyq (giữ nguyên ~/.config/copyq)"
    sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y copyq
  fi
}

# --- helper GVariant kiểu 'as' -------------------------------------------------
# gsettings trả về dạng ['a', 'b'] hoặc @as [].
gv_split() { grep -o "'[^']*'" <<<"${1:-}" | tr -d "'" || true; }
gv_pack() {
  local out="" x
  for x in "$@"; do out+="'${x}', "; done
  printf "[%s]" "${out%, }"
}

# --- dọn custom keybinding trỏ tới copyq --------------------------------------
drop_copyq_keybinding() {
  local schema="org.gnome.settings-daemon.plugins.media-keys"
  local child="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
  local list keep=() p removed=0

  list="$(gsettings get "$schema" custom-keybindings 2>/dev/null || echo '@as []')"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if gsettings get "${child}:${p}" command 2>/dev/null | grep -q copyq; then
      # Reset cả 3 key của slot, nếu không dconf còn rác trỏ vào lệnh đã gỡ.
      gsettings reset "${child}:${p}" name    2>/dev/null || true
      gsettings reset "${child}:${p}" command 2>/dev/null || true
      gsettings reset "${child}:${p}" binding 2>/dev/null || true
      removed=1
    else
      keep+=("$p")
    fi
  done < <(gv_split "$list")

  if [[ $removed -eq 1 ]]; then
    gsettings set "$schema" custom-keybindings "$(gv_pack "${keep[@]+"${keep[@]}"}")"
    ok "Đã gỡ custom keybinding cũ của CopyQ."
  fi
}

# --- giải phóng Super+V --------------------------------------------------------
# GNOME mặc định gán Super+V cho toggle-message-tray; không gỡ thì shell ăn phím
# trước, extension không bao giờ nhận được.
free_shortcut() {
  [[ "$SHORTCUT" == "<Super>v" ]] || return 0
  local tray keep=() k
  tray="$(gsettings get org.gnome.shell.keybindings toggle-message-tray 2>/dev/null || echo '')"
  [[ "$tray" == *"<Super>v"* ]] || return 0
  while IFS= read -r k; do
    [[ -n "$k" && "$k" != "<Super>v" ]] && keep+=("$k")
  done < <(gv_split "$tray")
  gsettings set org.gnome.shell.keybindings toggle-message-tray "$(gv_pack "${keep[@]+"${keep[@]}"}")"
  ok "Đã gỡ Super+V khỏi toggle-message-tray (tray vẫn mở được bằng Super+M)."
}

# --- cài extension -------------------------------------------------------------
# extensions.gnome.org không có API tải theo tên, phải hỏi extension-info để lấy
# version_tag (pk) đúng với major version của shell đang chạy.
shell_major() { gnome-shell --version | grep -oE '[0-9]+' | head -1; }

installed_version() {
  local meta="$EXT_DIR/metadata.json"
  [[ -f "$meta" ]] || { echo 0; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",0))' "$meta" 2>/dev/null || echo 0
}

install_extension() {
  local ver; ver="$(shell_major)"
  [[ -n "$ver" ]] || die "Không đọc được version của GNOME Shell."
  log "GNOME Shell $ver — hỏi extensions.gnome.org bản tương thích"

  local info
  info="$(curl -fsSL --max-time 20 \
    "https://extensions.gnome.org/extension-info/?uuid=${UUID}&shell_version=${ver}")" \
    || die "Không tải được metadata của $UUID (mất mạng, hoặc extension chưa hỗ trợ GNOME $ver)."

  local tag remote
  read -r tag remote < <(python3 -c '
import json, sys
d = json.load(sys.stdin)
m = d["shell_version_map"].get(sys.argv[1])
if not m:
    sys.exit("no build for shell " + sys.argv[1])
print(m["pk"], m["version"])
' "$ver" <<<"$info") || die "$UUID chưa có bản build cho GNOME $ver."

  local local_ver; local_ver="$(installed_version)"
  if [[ "$local_ver" == "$remote" ]]; then
    ok "$UUID v$remote đã cài sẵn."
    return
  fi

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  log "Tải $UUID v$remote"
  curl -fsSL --max-time 60 -o "$tmp/ext.zip" \
    "https://extensions.gnome.org/download-extension/${UUID}.shell-extension.zip?version_tag=${tag}" \
    || die "Tải extension thất bại."

  gnome-extensions install --force "$tmp/ext.zip" \
    || die "gnome-extensions install thất bại."
  ok "Đã cài $UUID v$remote vào $EXT_DIR"
}

# --- bật extension -------------------------------------------------------------
# `gnome-extensions enable` chỉ ăn khi shell đã quét thấy thư mục mới — với bản
# vừa cài trên Wayland thì chưa. Ghi thẳng vào enabled-extensions để sau khi
# logout là extension tự bật.
enable_extension() {
  gnome-extensions enable "$UUID" >/dev/null 2>&1 || true

  local list current=() p
  list="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '@as []')"
  while IFS= read -r p; do [[ -n "$p" ]] && current+=("$p"); done < <(gv_split "$list")

  for p in "${current[@]+"${current[@]}"}"; do
    [[ "$p" == "$UUID" ]] && { ok "Extension đã nằm trong enabled-extensions."; return; }
  done

  current+=("$UUID")
  gsettings set org.gnome.shell enabled-extensions "$(gv_pack "${current[@]}")"
  ok "Đã thêm $UUID vào enabled-extensions."

  # Extension bị vô hiệu hoá toàn cục thì bật bao nhiêu cũng vô nghĩa.
  if [[ "$(gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)" == "true" ]]; then
    gsettings set org.gnome.shell disable-user-extensions false
    ok "Đã bật lại user extensions (trước đó đang tắt toàn cục)."
  fi
}

# --- cấu hình ------------------------------------------------------------------
# Schema của extension nằm trong thư mục extension, không có trong schema hệ thống
# -> phải chỉ --schemadir cho gsettings.
tune_extension() {
  [[ "$UUID" == "clipboard-indicator@tudmotu.com" ]] || {
    dim "(UUID tuỳ chỉnh, bỏ qua phần cấu hình)"; return; }
  [[ -f "$EXT_DIR/schemas/gschemas.compiled" ]] || {
    warn "Không thấy schema đã compile, bỏ qua phần cấu hình."; return; }

  ext_set() { gsettings --schemadir "$EXT_DIR/schemas" set "$SCHEMA" "$1" "$2"; }
  ext_set enable-keybindings true
  ext_set toggle-menu "$(gv_pack "$SHORTCUT")"
  ext_set paste-on-select "$PASTE_ON_SELECT"
  ext_set open-at-cursor "$OPEN_AT_CURSOR"
  ext_set move-item-first true     # item vừa dùng nhảy lên đầu danh sách
  ext_set cache-images true        # giữ cả ảnh, không chỉ text
  ok "Cấu hình: $SHORTCUT | paste-on-select=$PASTE_ON_SELECT | open-at-cursor=$OPEN_AT_CURSOR"
}

remove_copyq
drop_copyq_keybinding
free_shortcut
install_extension
enable_extension
tune_extension

cat <<EOF

Clipboard Indicator đã sẵn sàng.
  • BẮT BUỘC logout/reboot — Wayland không cho reload GNOME Shell tại chỗ,
    extension chỉ nạp khi shell khởi động lại.
  • Sau khi login: bấm $SHORTCUT để mở lịch sử clipboard (hoặc bấm icon clipboard
    trên panel).
  • Chỉnh sâu hơn: gnome-extensions prefs $UUID
  • Kiểm tra nhanh: gnome-extensions info $UUID   (State phải là ACTIVE)
  • Lịch sử CopyQ cũ vẫn còn ở ~/.config/copyq, tự xoá nếu không cần.
EOF
