#!/usr/bin/env bash
# Docker Engine + CLI + Buildx + Compose plugin, từ repo chính thức của Docker.
# Ref: https://docs.docker.com/engine/install/ubuntu/
#      https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-22-04
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_ubuntu
need_sudo

# Docker repo dùng codename Ubuntu. Với bản mới (vd 26.04 ngay sau release) Docker
# có thể chưa publish kịp -> override: DOCKER_CODENAME=noble ./docker.sh
DOCKER_CODENAME="${DOCKER_CODENAME:-$OS_CODENAME}"
ARCH="$(dpkg --print-architecture)"

if ! curl -fsI "https://download.docker.com/linux/ubuntu/dists/${DOCKER_CODENAME}/Release" >/dev/null 2>&1; then
  warn "Docker chưa có repo cho '$DOCKER_CODENAME'."
  warn "Fallback sang 'noble' (24.04). Đổi bằng: DOCKER_CODENAME=<codename> $0"
  DOCKER_CODENAME=noble
fi

log "Gỡ package docker cũ của Ubuntu (nếu có)"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

log "Thêm GPG key của Docker"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

log "Thêm repo Docker (${DOCKER_CODENAME}/${ARCH})"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${DOCKER_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

_APT_UPDATED=""   # ép apt update lại sau khi thêm repo
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Bật & khởi động docker service"
sudo systemctl enable --now docker

# Chạy docker không cần sudo
if ! id -nG "$USER" | grep -qw docker; then
  log "Thêm $USER vào group 'docker'"
  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"
  # Group membership được gán lúc process sinh ra -> shell/app đang chạy không tự nhận.
  warn "Group 'docker' chưa áp dụng cho shell hiện tại."
  dim  "  • Terminal này:        newgrp docker   (hoặc: su - $USER)"
  dim  "  • Terminal/app khác đang mở & app mở từ GUI (VS Code...): cần logout/reboot"
fi

ok "$(sudo docker --version)"
ok "$(sudo docker compose version)"
dim "Test: sudo docker run --rm hello-world   (bỏ sudo được sau khi 'newgrp docker')"
