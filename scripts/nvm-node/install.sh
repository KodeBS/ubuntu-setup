#!/usr/bin/env bash
# nvm + Node.js (mặc định gợi ý Node 22 LTS, có menu chọn version).
# Ref: https://nodejs.org/en/download  |  https://github.com/nvm-sh/nvm#install--update-script
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

NVM_VERSION="${NVM_VERSION:-v0.40.3}"     # tag nvm để cài
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_VERSION="${NODE_VERSION:-}"          # vd: 22 | 20 | lts/* ; hỏi nếu để trống

require_ubuntu
need_sudo
apt_install curl ca-certificates

# --- cài / cập nhật nvm --------------------------------------------------------
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  ok "nvm đã có ở $NVM_DIR"
else
  log "Cài nvm $NVM_VERSION"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

# nạp nvm vào shell hiện tại
export NVM_DIR
# shellcheck disable=SC1091
source "$NVM_DIR/nvm.sh"

# nvm install script chỉ tự thêm vào file rc mặc định; đảm bảo cả bash lẫn zsh có.
NVM_SNIPPET='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  grep -q 'NVM_DIR' "$rc" || { printf '\n# nvm\n%s\n' "$NVM_SNIPPET" >>"$rc"; ok "Đã thêm nvm vào $(basename "$rc")"; }
done

# --- chọn version Node ---------------------------------------------------------
if [[ -z "$NODE_VERSION" ]]; then
  echo
  echo "Chọn phiên bản Node.js muốn cài:"
  echo "  1) 22   — LTS 'Jod'      (khuyên dùng)"
  echo "  2) 24   — LTS mới hơn"
  echo "  3) 20   — LTS cũ (maintenance)"
  echo "  4) lts/* — LTS mới nhất hiện tại"
  echo "  5) node  — bản Current mới nhất"
  echo "  6) khác  — tự nhập (vd 18.20.4)"
  read -r -p "Lựa chọn [1]: " choice </dev/tty || true
  case "${choice:-1}" in
    1) NODE_VERSION=22 ;;
    2) NODE_VERSION=24 ;;
    3) NODE_VERSION=20 ;;
    4) NODE_VERSION='lts/*' ;;
    5) NODE_VERSION=node ;;
    6) read -r -p "Nhập version: " NODE_VERSION </dev/tty ;;
    *) NODE_VERSION=22 ;;
  esac
fi

log "nvm install $NODE_VERSION"
nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
nvm use default

log "Cập nhật npm + cài global tools"
npm install -g npm@latest >/dev/null
npm install -g yarn pnpm >/dev/null || warn "Không cài được yarn/pnpm (bỏ qua)."

ok "Node $(node -v) | npm $(npm -v) | nvm $(nvm --version)"
dim "Mở terminal mới (hoặc: source ~/.zshrc) để dùng nvm."
