#!/usr/bin/env bash
# zsh + Oh My Zsh + plugin (autosuggestions, syntax-highlighting) + Powerlevel10k.
# Ref: https://github.com/ohmyzsh/ohmyzsh#basic-installation
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

apt_install zsh git curl

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

if [[ -d "$ZSH_DIR" ]]; then
  ok "Oh My Zsh đã có ở $ZSH_DIR"
else
  log "Cài Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

[[ -f "$HOME/.zshrc" ]] || cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"

clone_plugin() { # clone_plugin <repo-url> <dest>
  local url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    dim "đã có: $(basename "$dest")"
  else
    log "clone $(basename "$dest")"
    git clone --depth=1 "$url" "$dest"
  fi
}

clone_plugin https://github.com/zsh-users/zsh-autosuggestions      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_plugin https://github.com/zsh-users/zsh-completions          "$ZSH_CUSTOM/plugins/zsh-completions"
clone_plugin https://github.com/romkatv/powerlevel10k              "$ZSH_CUSTOM/themes/powerlevel10k"

# --- cấu hình .zshrc -----------------------------------------------------------
PLUGINS="git docker docker-compose npm node z zsh-completions zsh-autosuggestions zsh-syntax-highlighting"
if grep -qE '^\s*plugins=' "$HOME/.zshrc"; then
  sed -i "s|^\s*plugins=.*|plugins=($PLUGINS)|" "$HOME/.zshrc"
else
  ensure_line "$HOME/.zshrc" "plugins=($PLUGINS)"
fi
ok "plugins=($PLUGINS)"

# --- JetBrainsMono Nerd Font ----------------------------------------------------
# Phải là bản Nerd Font patched, nếu không mọi icon trong prompt (logo distro,
# folder, git branch) đều ra ô vuông tofu.
#
# KHÔNG dùng MesloLGS NF (font p10k khuyến nghị): nó thiếu sạch khối ký tự tiếng
# Việt có dấu (U+1EA0-U+1EF9), fontconfig phải rơi về Noto Sans — một font
# proportional — nên chữ có dấu lệch bề rộng lẫn baseline giữa lưới monospace.
#
# Phải lấy đúng bản "NerdFontMono": Nerd Fonts phát hành 3 biến thể, bản thường
# ("Nerd Font") có glyph double-width và bản "Propo" thì proportional — cả hai
# đều làm terminal giãn ô gấp đôi. Chỉ bản Mono là single-width.
#
# Ghim tag thay vì master: nerd-fonts đã xoá thư mục patched-fonts khỏi nhánh
# master (repo quá nặng), nên URL master trả 404 — font không cài được mà script
# vẫn chạy tiếp, prompt ra toàn ô vuông hex. Tag cũ vẫn giữ nguyên file.
install_nerd_font() {
  local dir="$HOME/.local/share/fonts"
  local tag="v3.4.0"
  local base="https://github.com/ryanoasis/nerd-fonts/raw/$tag/patched-fonts/JetBrainsMono/Ligatures"
  local variants=("Regular" "Bold" "Italic" "BoldItalic")
  local missing=() v
  for v in "${variants[@]}"; do
    [[ -f "$dir/JetBrainsMonoNerdFontMono-$v.ttf" ]] || missing+=("$v")
  done
  if (( ${#missing[@]} == 0 )); then ok "JetBrainsMono Nerd Font Mono đã có."; return; fi

  log "Tải JetBrainsMono Nerd Font Mono (${#missing[@]} file)"
  mkdir -p "$dir"
  local failed=0
  for v in "${missing[@]}"; do
    if curl -fsSL "$base/$v/JetBrainsMonoNerdFontMono-$v.ttf" -o "$dir/JetBrainsMonoNerdFontMono-$v.ttf"; then
      dim "  JetBrainsMonoNerdFontMono-$v.ttf"
    else
      warn "Không tải được JetBrainsMonoNerdFontMono-$v"; rm -f "$dir/JetBrainsMonoNerdFontMono-$v.ttf"
      failed=1
    fi
  done
  fc-cache -f "$dir" >/dev/null 2>&1 || true
  if (( failed )); then
    warn "Thiếu file font -> prompt p10k sẽ ra ô vuông. Kiểm tra tag '$tag' còn không:"
    warn "  https://github.com/ryanoasis/nerd-fonts/releases"
  else
    ok "JetBrainsMono Nerd Font Mono xong."
  fi
}

# --- font cho terminal ---------------------------------------------------------
# Ubuntu 26.04 dùng Ptyxis; 24.04 trở về trước dùng GNOME Terminal.
set_terminal_font() {
  local font="${TERMINAL_FONT:-JetBrainsMono Nerd Font Mono 11}"
  has gsettings || { warn "Không có gsettings, tự set font terminal giúp nhé."; return; }

  if gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.Ptyxis"; then
    gsettings set org.gnome.Ptyxis use-system-font false
    gsettings set org.gnome.Ptyxis font-name "$font"
    ok "Ptyxis font -> $font"
    return
  fi

  if gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.Terminal.ProfilesList"; then
    local uuid path
    uuid="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")"
    if [[ -n "$uuid" ]]; then
      path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${uuid}/"
      gsettings set "$path" use-system-font false
      gsettings set "$path" font "$font"
      ok "GNOME Terminal font -> $font"
      return
    fi
  fi
  warn "Không nhận ra terminal đang dùng — set font '$font' bằng tay nhé."
}

if confirm "Dùng theme Powerlevel10k? (không thì giữ theme hiện tại)"; then
  if grep -qE '^\s*ZSH_THEME=' "$HOME/.zshrc"; then
    sed -i 's|^\s*ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  else
    ensure_line "$HOME/.zshrc" 'ZSH_THEME="powerlevel10k/powerlevel10k"'
  fi
  ok 'ZSH_THEME="powerlevel10k/powerlevel10k"'

  install_nerd_font
  set_terminal_font

  # Áp config p10k dựng sẵn (rainbow, many icons, nerdfont-v3) -> khỏi phải
  # chạy lại `p10k configure` trên máy mới.
  P10K_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotfiles/p10k.zsh"
  if [[ -f "$P10K_SRC" ]]; then
    if [[ -f "$HOME/.p10k.zsh" ]] && ! cmp -s "$P10K_SRC" "$HOME/.p10k.zsh"; then
      cp "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.bak"
      dim "backup config cũ -> ~/.p10k.zsh.bak"
    fi
    cp "$P10K_SRC" "$HOME/.p10k.zsh"
    ok "Đã áp ~/.p10k.zsh (chạy \`p10k configure\` nếu muốn đổi)."
  else
    warn "Không thấy $P10K_SRC — chạy \`p10k configure\` sau vậy."
  fi
  ensure_line "$HOME/.zshrc" '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
fi

# --- đặt zsh làm shell mặc định ------------------------------------------------
ZSH_BIN="$(command -v zsh)"
grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null

if [[ "${SHELL:-}" != "$ZSH_BIN" ]]; then
  log "Đổi shell mặc định sang zsh"
  sudo chsh -s "$ZSH_BIN" "$USER" && ok "Shell mặc định: $ZSH_BIN (có hiệu lực sau khi logout)"
else
  ok "zsh đã là shell mặc định."
fi
