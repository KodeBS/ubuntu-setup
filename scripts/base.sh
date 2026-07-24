#!/usr/bin/env bash
# Gói nền tảng: build tools, curl/git/unzip, tiện ích dòng lệnh.
# Ref: https://help.ubuntu.com/community/InstallingSoftware
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

log "Ubuntu $OS_VERSION ($OS_CODENAME) — cài gói nền tảng"

apt_update_once
log "apt upgrade"
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

apt_install \
  build-essential \
  ca-certificates \
  curl \
  wget \
  git \
  gnupg \
  unzip \
  zip \
  tar \
  jq \
  tree \
  ripgrep \
  fd-find \
  openssh-client \
  software-properties-common \
  wl-clipboard

# fd-find cài binary tên `fdfind` trên Ubuntu; tạo alias `fd` trong ~/.local/bin
mkdir -p "$HOME/.local/bin"
if has fdfind && [[ ! -e "$HOME/.local/bin/fd" ]]; then
  ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
  ok "symlink fd -> fdfind"
fi

ok "Base packages xong."
