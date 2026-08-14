#!/usr/bin/env bash
# Gỡ phần base: CHỈ những tiện ích dòng lệnh mà không gói hệ thống nào phụ thuộc.
#
# base.sh cài lẫn lộn hai nhóm: tiện ích thuần (jq, tree, ripgrep...) và gói nền
# của Ubuntu (curl, ca-certificates, gnupg, software-properties-common...). Nhóm
# thứ hai là dependency của apt/ubuntu-desktop/snapd — `apt remove` một cái là
# apt kéo theo cả desktop, máy không boot vào GUI được nữa. Nên nhóm đó chỉ được
# liệt kê ra, không bao giờ tự gỡ.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

# Gỡ được: không nằm trong dependency chain của apt/desktop.
SAFE=(jq tree ripgrep fd-find zip wl-clipboard)

# KHÔNG gỡ: gỡ là hỏng apt hoặc hỏng desktop.
KEEP=(build-essential ca-certificates curl wget git gnupg unzip tar openssh-client
      software-properties-common)

# symlink fd -> fdfind do base.sh tạo.
FD_LINK="$HOME/.local/bin/fd"
if [[ -L "$FD_LINK" ]] && [[ "$(readlink -f "$FD_LINK")" == *fdfind* ]]; then
  safe_rm "$FD_LINK" && ok "Đã gỡ symlink fd -> fdfind" \
    || warn "Không gỡ được $FD_LINK"
fi

apt_remove "${SAFE[@]}"

echo
warn "Các gói sau CỐ TÌNH không gỡ vì hệ thống phụ thuộc vào chúng:"
printf '    %s\n' "${KEEP[*]}"
dim  "Muốn gỡ thật thì tự chạy và đọc kỹ danh sách apt định xoá kèm theo:"
dim  "    sudo apt remove <tên gói>"

ok "Xong phần base."
