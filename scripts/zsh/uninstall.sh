#!/usr/bin/env bash
# Gỡ zsh + Oh My Zsh + Powerlevel10k + Nerd Font, trả shell mặc định về bash.
#
# Thứ tự quan trọng: PHẢI đổi shell về bash TRƯỚC khi `apt remove zsh`. Làm ngược
# lại thì login shell trỏ tới /usr/bin/zsh đã bị xoá -> lần login sau không vào
# được session đồ hoạ.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
FONT_DIR="$HOME/.local/share/fonts"

# --- 1. trả shell mặc định về bash ---------------------------------------------
restore_shell() {
  local cur
  cur="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$cur" != *zsh ]]; then
    dim "Shell mặc định đang là $cur, không cần đổi."
    return
  fi
  [[ -x /bin/bash ]] || { warn "Không thấy /bin/bash, giữ nguyên shell $cur."; return; }
  sudo chsh -s /bin/bash "$USER" \
    && ok "Shell mặc định -> /bin/bash (có hiệu lực sau khi logout)" \
    || warn "Không đổi được shell, tự chạy: sudo chsh -s /bin/bash $USER"
}

# --- 2. dọn cấu hình trong ~/.zshrc --------------------------------------------
# Không xoá ~/.zshrc ở chế độ thường: file này có thể chứa alias/env người dùng
# tự thêm. Chỉ gỡ đúng những dòng zsh.sh đã ghi vào.
clean_zshrc() {
  local rc="$HOME/.zshrc"
  [[ -f "$rc" ]] || return 0
  strip_lines "$rc" '^\[\[ ! -f ~/\.p10k\.zsh \]\] \|\| source ~/\.p10k\.zsh$'
  if grep -qE '^\s*ZSH_THEME="powerlevel10k/powerlevel10k"' "$rc"; then
    backup_file "$rc"
    sed -i 's|^\s*ZSH_THEME="powerlevel10k/powerlevel10k"|ZSH_THEME="robbyrussell"|' "$rc"
    ok 'ZSH_THEME -> "robbyrussell"'
  fi
  if grep -qE '^\s*plugins=\(.*zsh-autosuggestions' "$rc"; then
    backup_file "$rc"
    sed -i 's|^\s*plugins=(.*|plugins=(git)|' "$rc"
    ok "plugins=(git)"
  fi
}

# --- 3. Oh My Zsh ---------------------------------------------------------------
# custom/ là chỗ người dùng để plugin/theme tự viết. Nếu có thứ lạ trong đó thì
# giữ nguyên cả ~/.oh-my-zsh, chỉ xoá đúng 4 repo mà zsh.sh clone về.
custom_has_foreign() {
  [[ -d "$ZSH_CUSTOM" ]] || return 1
  local e rel
  while IFS= read -r e; do
    rel="${e#"$ZSH_CUSTOM"/}"
    case "$rel" in
      plugins|themes) ;;
      plugins/zsh-autosuggestions|plugins/zsh-syntax-highlighting) ;;
      plugins/zsh-completions|themes/powerlevel10k) ;;
      plugins/example|themes/example.zsh-theme|example.zsh) ;;
      *) return 0 ;;
    esac
  done < <(find "$ZSH_CUSTOM" -mindepth 1 -maxdepth 2)
  return 1
}

remove_ohmyzsh() {
  [[ -d "$ZSH_DIR" ]] || { dim "Không có $ZSH_DIR."; return; }

  if custom_has_foreign && ! purging; then
    warn "$ZSH_CUSTOM có plugin/theme không do script này cài -> giữ lại $ZSH_DIR."
    dim  "Chỉ xoá 4 repo do zsh.sh clone về."
    safe_rm "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
            "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
            "$ZSH_CUSTOM/plugins/zsh-completions" \
            "$ZSH_CUSTOM/themes/powerlevel10k" \
      || warn "Có plugin không xoá được, kiểm tra lại $ZSH_CUSTOM"
    return 0
  fi

  safe_rm "$ZSH_DIR" \
    && ok "Đã xoá Oh My Zsh ($ZSH_DIR)" \
    || warn "Không xoá được $ZSH_DIR"
}

# --- 4. Powerlevel10k config + font ---------------------------------------------
remove_p10k_config() {
  [[ -f "$HOME/.p10k.zsh" ]] || return 0
  backup_file "$HOME/.p10k.zsh"
  safe_rm "$HOME/.p10k.zsh" \
    && ok "Đã xoá ~/.p10k.zsh (bản backup vẫn còn cạnh đó)" \
    || warn "Không xoá được ~/.p10k.zsh"
}

# Chỉ xoá đúng 4 file zsh.sh tải về, không đụng font khác trong thư mục.
remove_nerd_font() {
  local v removed=0
  for v in Regular Bold Italic BoldItalic; do
    local f="$FONT_DIR/JetBrainsMonoNerdFontMono-$v.ttf"
    [[ -f "$f" ]] || continue
    if safe_rm "$f"; then removed=1; fi
  done
  if (( removed )); then
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    ok "Đã gỡ JetBrainsMono Nerd Font Mono."
  fi
}

# --- 5. font terminal ------------------------------------------------------------
reset_terminal_font() {
  has gsettings || return 0
  if gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.Ptyxis"; then
    gsettings reset org.gnome.Ptyxis font-name       2>/dev/null || true
    gsettings reset org.gnome.Ptyxis use-system-font 2>/dev/null || true
    ok "Ptyxis: trả font về mặc định hệ thống."
    return
  fi
  if gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.Terminal.ProfilesList"; then
    local uuid path
    uuid="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")"
    if [[ -n "$uuid" ]]; then
      path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${uuid}/"
      gsettings reset "$path" font            2>/dev/null || true
      gsettings reset "$path" use-system-font  2>/dev/null || true
      ok "GNOME Terminal: trả font về mặc định hệ thống."
    fi
  fi
}

restore_shell
clean_zshrc
remove_p10k_config
remove_nerd_font
reset_terminal_font
remove_ohmyzsh

# --- 6. gói zsh ------------------------------------------------------------------
apt_remove zsh

# --- 7. dữ liệu cá nhân (chỉ khi --purge) ---------------------------------------
if purging; then
  if confirm_danger "Sắp xoá ~/.zshrc, ~/.zsh_history và cache completion của zsh."; then
    backup_file "$HOME/.zshrc"
    # KHÔNG đụng ~/.zshenv: zsh.sh không tạo file đó, nó thường chứa env riêng
    # của máy (cap CPU, biến build...) mà xoá đi là mất luôn.
    safe_rm "$HOME/.zshrc" "$HOME/.zsh_history" || warn "Còn sót file cấu hình zsh."
    dumps=("$HOME"/.zcompdump*)
    [[ -e "${dumps[0]}" ]] && { safe_rm "${dumps[@]}" || true; }
    ok "Đã xoá cấu hình & lịch sử zsh (~/.zshenv giữ nguyên)."
  else
    dim "Bỏ qua xoá ~/.zshrc và lịch sử."
  fi
fi

ok "Xong phần zsh. Logout/reboot để về bash."
