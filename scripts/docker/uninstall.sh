#!/usr/bin/env bash
# Gỡ Docker Engine + Compose plugin + repo apt, và gỡ user khỏi group docker.
#
# MẶC ĐỊNH KHÔNG XOÁ /var/lib/docker: image, container và nhất là VOLUME (database
# của mọi project chạy local) nằm hết ở đó. `apt remove docker-ce` không đụng vào
# nó, nên cài lại Docker là data còn nguyên. Chỉ --purge mới xoá, và phải gõ 'yes'.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

PKGS=(docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io
      docker-buildx-plugin docker-compose-plugin)

# --- 1. cho xem còn gì trong máy TRƯỚC khi gỡ ----------------------------------
show_inventory() {
  has docker || return 0
  sudo docker info >/dev/null 2>&1 || { dim "Docker daemon không chạy, bỏ qua phần thống kê."; return 0; }
  local c i v
  c="$(sudo docker ps -aq 2>/dev/null | wc -l)"
  i="$(sudo docker images -q 2>/dev/null | wc -l)"
  v="$(sudo docker volume ls -q 2>/dev/null | wc -l)"
  log "Đang có: $c container, $i image, $v volume."
  if (( v > 0 )); then
    dim "Volume hiện có:"
    sudo docker volume ls --format '  {{.Name}}' 2>/dev/null || true
  fi
}

# --- 2. dừng service -------------------------------------------------------------
stop_services() {
  local s
  for s in docker.service docker.socket containerd.service; do
    systemctl list-unit-files "$s" >/dev/null 2>&1 || continue
    sudo systemctl disable --now "$s" >/dev/null 2>&1 || true
  done
  ok "Đã dừng & tắt autostart docker/containerd."
}

# --- 3. gỡ user khỏi group docker ------------------------------------------------
# Để lại thì user vẫn ở group không còn ý nghĩa, và nếu sau này có tiến trình khác
# tạo socket /var/run/docker.sock thì quyền vẫn mở.
leave_docker_group() {
  getent group docker >/dev/null 2>&1 || return 0
  id -nG "$USER" | grep -qw docker || { dim "$USER không ở group docker."; return 0; }
  sudo gpasswd -d "$USER" docker >/dev/null \
    && ok "Đã gỡ $USER khỏi group 'docker' (áp dụng sau khi logout)." \
    || warn "Không gỡ được group, tự chạy: sudo gpasswd -d $USER docker"
}

show_inventory

# Hỏi trước khi làm bất cứ điều gì, vì --purge là không quay lại được.
if purging; then
  confirm_danger "--purge: sẽ XOÁ VĨNH VIỄN /var/lib/docker (toàn bộ image, container, VOLUME) sau khi gỡ gói." \
    || die "Đã huỷ — chạy lại không có --purge để chỉ gỡ gói mà giữ dữ liệu."
fi

stop_services
leave_docker_group
apt_remove "${PKGS[@]}"

# --- 4. repo apt + GPG key -------------------------------------------------------
safe_rm /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc \
  && ok "Đã gỡ repo apt của Docker." \
  || warn "Không dọn sạch được repo apt của Docker."

# --- 5. dữ liệu (chỉ khi --purge, đã xác nhận ở trên) ---------------------------
if purging; then
  safe_rm /var/lib/docker /var/lib/containerd \
    || err "KHÔNG xoá hết được /var/lib/docker — dữ liệu vẫn còn trên máy."
  # ~/.docker chứa config + credential helper của registry.
  if [[ -d "$HOME/.docker" ]]; then
    safe_rm "$HOME/.docker" \
      && ok "Đã xoá ~/.docker (config đăng nhập registry)." \
      || warn "Không xoá được ~/.docker."
  fi
else
  dim "Giữ nguyên /var/lib/docker — cài lại Docker là image/volume còn đủ."
fi

ok "Xong phần Docker."
