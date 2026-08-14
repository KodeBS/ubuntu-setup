#!/usr/bin/env bash
# Gỡ bộ gõ tiếng Việt (ibus-bamboo / ibus-unikey) + PPA của BambooEngine.
#
# KHÔNG gỡ gói `ibus`: đó là input method framework mặc định của GNOME trên
# Ubuntu, gỡ đi thì mất luôn khả năng gõ mọi ngôn ngữ non-latin và ubuntu-desktop
# kéo theo. vietnamese-input.sh có cài `ibus` nhưng gần như chắc chắn nó đã có
# sẵn từ trước.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

# --- 1. gỡ input source khỏi GNOME ----------------------------------------------
# Để lại thì Settings > Keyboard vẫn hiện engine đã bị gỡ, và Super+Space chuyển
# sang một engine không tồn tại -> mất khả năng gõ.
drop_gnome_input_source() {
  has gsettings || return 0
  local cur new
  cur="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo '')"
  [[ -n "$cur" ]] || return 0
  grep -qiE 'bamboo|unikey' <<<"$cur" || { dim "GNOME chưa gán input source tiếng Việt nào."; return 0; }

  if ! has python3; then
    warn "Thiếu python3 — tự gỡ engine tiếng Việt trong Settings > Keyboard > Input Sources."
    return 0
  fi

  # GVariant a(ss) — '[(\'xkb\', \'us\'), (\'ibus\', \'Bamboo\')]' — cũng là
  # literal Python hợp lệ, nên literal_eval parse được mà không cần thư viện GLib.
  new="$(python3 - "$cur" <<'PY' 2>/dev/null
import ast, sys
items = ast.literal_eval(sys.argv[1])
keep = [t for t in items if not any(k in str(t[1]).lower() for k in ("bamboo", "unikey"))]
print("[" + ", ".join("('%s', '%s')" % (a, b) for a, b in keep) + "]" if keep else "@a(ss) []")
PY
)" || { warn "Không đọc được input-sources, bỏ qua."; return 0; }

  gsettings set org.gnome.desktop.input-sources sources "$new" \
    && ok "Đã gỡ input source tiếng Việt khỏi GNOME." \
    || warn "Không ghi được input-sources, tự gỡ trong Settings > Keyboard."
}

# --- 2. gỡ gói -------------------------------------------------------------------
INSTALLED=()
for p in ibus-bamboo ibus-unikey; do pkg_installed "$p" && INSTALLED+=("$p"); done

if (( ${#INSTALLED[@]} == 0 )); then
  dim "Không có ibus-bamboo/ibus-unikey nào được cài."
else
  drop_gnome_input_source
  apt_remove "${INSTALLED[@]}"
fi

# --- 3. gỡ PPA của BambooEngine --------------------------------------------------
remove_bamboo_ppa() {
  local found=0 f
  for f in /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.list \
           /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.sources; do
    [[ -e "$f" ]] && found=1
  done
  (( found )) || { dim "Không thấy PPA ibus-bamboo."; return 0; }

  log "Gỡ PPA bamboo-engine/ibus-bamboo"
  if has add-apt-repository; then
    sudo add-apt-repository -r -y ppa:bamboo-engine/ibus-bamboo >/dev/null 2>&1 || true
  fi
  # add-apt-repository -r hay để lại file rỗng hoặc file .sources; dọn nốt.
  for f in /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.list \
           /etc/apt/sources.list.d/bamboo-engine-ubuntu-ibus-bamboo-*.sources; do
    [[ -e "$f" ]] && { safe_rm "$f" || true; }
  done
  ok "Đã gỡ PPA ibus-bamboo."
}
remove_bamboo_ppa

# --- 4. cấu hình riêng của bamboo (chỉ khi --purge) -----------------------------
if purging && [[ -d "$HOME/.config/ibus-bamboo" ]]; then
  safe_rm "$HOME/.config/ibus-bamboo" \
    && ok "Đã xoá ~/.config/ibus-bamboo." \
    || warn "Không xoá được ~/.config/ibus-bamboo."
fi

# --- 5. nạp lại ibus -------------------------------------------------------------
if has ibus; then
  ibus restart >/dev/null 2>&1 || true
fi

warn 'Gói "ibus" được giữ lại (GNOME cần nó để gõ mọi ngôn ngữ).'
ok "Xong phần bộ gõ tiếng Việt. Logout/reboot để ibus quên hẳn engine cũ."
