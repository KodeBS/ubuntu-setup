#!/usr/bin/env bash
# App làm việc hằng ngày: VS Code, Google Chrome, và vài app snap tuỳ chọn.
# Ref: https://code.visualstudio.com/docs/setup/linux
#      https://www.google.com/chrome/
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo
apt_install wget gpg

install_vscode() {
  if has code; then ok "VS Code đã có."; return; fi
  log "Cài VS Code (repo Microsoft)"
  sudo install -m 0755 -d /etc/apt/keyrings
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/packages.microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  _APT_UPDATED=""
  apt_install code
}

install_chrome() {
  if has google-chrome || has google-chrome-stable; then ok "Chrome đã có."; return; fi
  log "Cài Google Chrome (.deb chính thức)"
  local deb="/tmp/google-chrome-stable.deb"
  wget -qO "$deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
  rm -f "$deb"
}

install_postman() {
  has snap || { warn "Không có snapd, bỏ qua Postman."; return; }
  log "snap install postman"
  sudo snap install postman || warn "Không cài được Postman"
}

# DataGrip / JetBrains: cài tay qua JetBrains Toolbox, không quản ở đây.

# Chọn app cần cài; APPS=vscode,chrome ./apps.sh để bỏ qua phần hỏi.
APPS="${APPS:-}"
if [[ -z "$APPS" ]]; then
  confirm "Cài VS Code?"        && APPS+="vscode,"
  confirm "Cài Google Chrome?"  && APPS+="chrome,"
  confirm "Cài Postman (snap)?" && APPS+="postman,"
fi

IFS=',' read -ra list <<<"$APPS"
for app in "${list[@]}"; do
  case "$app" in
    vscode)  install_vscode ;;
    chrome)  install_chrome ;;
    postman) install_postman ;;
    "")      ;;
    *)       warn "App không rõ: $app" ;;
  esac
done

ok "Xong phần apps."
