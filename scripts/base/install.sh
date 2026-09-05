#!/usr/bin/env bash
# Gói nền tảng: build tools, curl/git/unzip, tiện ích dòng lệnh.
# Ref: https://help.ubuntu.com/community/InstallingSoftware
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

log "Ubuntu $OS_VERSION ($OS_CODENAME) — cài gói nền tảng"

apt_update_once

# Nâng cấp toàn hệ thống KHÔNG phải việc của "cài gói nền tảng": trên máy vừa cài
# đây là vài trăm gói, thường kéo theo kernel mới và đòi reboot. Để mặc định chạy
# là bất ngờ cho người dùng, nên hỏi. BASE_UPGRADE=1/0 để bỏ qua phần hỏi.
case "${BASE_UPGRADE:-ask}" in
  1) do_upgrade=1 ;;
  0) do_upgrade=0 ;;
  *) confirm "Nâng cấp toàn bộ gói hệ thống trước? (lâu, có thể kéo kernel mới)" \
       && do_upgrade=1 || do_upgrade=0 ;;
esac
if (( do_upgrade )); then
  log "apt upgrade"
  apt_get upgrade -y
else
  dim "Bỏ qua apt upgrade (chạy lại với BASE_UPGRADE=1 nếu muốn)."
fi

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
