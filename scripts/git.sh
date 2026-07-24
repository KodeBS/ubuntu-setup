#!/usr/bin/env bash
# Git: cấu hình user, alias, SSH key, gh CLI.
# Ref: https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup
#      https://docs.github.com/en/authentication/connecting-to-github-with-ssh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

apt_install git

GIT_NAME="${GIT_NAME:-$(git config --global user.name || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email || true)}"

[[ -n "$GIT_NAME"  ]] || read -r -p "Git user.name: "  GIT_NAME  </dev/tty
[[ -n "$GIT_EMAIL" ]] || read -r -p "Git user.email: " GIT_EMAIL </dev/tty

git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global core.editor "${EDITOR:-nano}"
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.lg "log --oneline --graph --decorate --all"
ok "git config: $GIT_NAME <$GIT_EMAIL>"

# --- SSH key -------------------------------------------------------------------
KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$KEY" ]]; then
  ok "SSH key đã có: $KEY"
elif confirm "Tạo SSH key mới (ed25519) cho $GIT_EMAIL?"; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY"
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$KEY"
  echo
  ok "Public key — copy vào GitHub/GitLab:"
  cat "${KEY}.pub"
  # Wayland dùng wl-copy; xclip chỉ để dự phòng cho session Xorg (vd Ubuntu 24.04).
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && has wl-copy; then
    wl-copy <"${KEY}.pub" && dim "(đã copy vào clipboard)"
  elif has xclip; then
    xclip -sel clip <"${KEY}.pub" && dim "(đã copy vào clipboard)"
  fi
fi

# --- GitHub CLI ----------------------------------------------------------------
if confirm "Cài GitHub CLI (gh)?"; then
  if has gh; then
    ok "gh đã có: $(gh --version | head -1)"
  else
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    _APT_UPDATED=""
    apt_install gh
    dim "Đăng nhập: gh auth login"
  fi
fi
