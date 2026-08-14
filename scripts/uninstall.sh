#!/usr/bin/env bash
# Script gỡ: đảo ngược những gì install.sh đã cài.
#
#   ./uninstall.sh                 # menu chọn (mặc định)
#   ./uninstall.sh --all           # gỡ hết, theo thứ tự ngược với lúc cài
#   ./uninstall.sh docker zsh      # chỉ gỡ module chỉ định
#   ./uninstall.sh --list          # liệt kê module
#
# Cờ:
#   --purge   gỡ luôn dữ liệu/cấu hình cá nhân (docker volume, ~/.nvm, lịch sử
#             clipboard, profile Chrome/VS Code...). Mỗi thứ không khôi phục được
#             đều hỏi xác nhận riêng.
#   --yes     không hỏi gì (dùng cho chạy tự động). Đi kèm --purge là xoá thẳng.
#
# MẶC ĐỊNH (không có --purge): chỉ gỡ package + hoàn tác cấu hình do script tạo.
# Dữ liệu cá nhân giữ nguyên. SSH key và git user.name/user.email KHÔNG BAO GIỜ
# bị đụng tới, kể cả khi --purge.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

# Ngược thứ tự install (base gỡ sau cùng vì mọi module khác dựa vào nó).
MODULES=(clipboard apps git docker nvm-node vietnamese-input zsh base)

describe() {
  case "$1" in
    clipboard)        echo "Extension Clipboard Indicator + trả Super+V về message tray" ;;
    apps)             echo "VS Code, Chrome, Postman + repo apt của chúng" ;;
    git)              echo "GitHub CLI + alias git do script tạo (GIỮ SSH key & user.name/email)" ;;
    docker)           echo "Docker Engine/Compose, repo apt, gỡ user khỏi group docker" ;;
    nvm-node)         echo "nvm + toàn bộ Node đã cài + snippet trong .bashrc/.zshrc" ;;
    vietnamese-input) echo "ibus-bamboo/ibus-unikey + PPA (GIỮ gói ibus của hệ thống)" ;;
    zsh)              echo "Oh My Zsh, Powerlevel10k, Nerd Font, zsh; trả shell về bash" ;;
    base)             echo "Tiện ích CLI an toàn (jq, tree, ripgrep, fd...) — giữ gói hệ thống" ;;
    *)                echo "" ;;
  esac
}

list_modules() {
  echo "Modules gỡ được:"
  local i=1
  for m in "${MODULES[@]}"; do
    printf "  %d) %-18s %s\n" "$i" "$m" "$(describe "$m")"
    i=$((i + 1))
  done
}

run_module() {
  local m="$1" script="$HERE/$1/uninstall.sh"
  [[ -f "$script" ]] || die "Không tìm thấy module gỡ: $m ($script)"
  echo
  printf "${C_BLUE}────── gỡ %s ──────${C_RESET}\n" "$m"
  if bash "$script"; then
    ok "module '$m' đã gỡ xong."
  else
    err "module '$m' lỗi (exit $?). Tiếp tục module kế tiếp."
    FAILED+=("$m")
  fi
}

require_ubuntu

# --- đọc cờ --------------------------------------------------------------------
args=()
for a in "$@"; do
  case "$a" in
    --purge)   PURGE=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    *)         args+=("$a") ;;
  esac
done
export PURGE ASSUME_YES
set -- "${args[@]+"${args[@]}"}"

log "Ubuntu ${OS_VERSION} (${OS_CODENAME:-?}) — ubuntu-setup / uninstall"

FAILED=()
selected=()

case "${1:-}" in
  --list|-l) list_modules; exit 0 ;;
  --all|-a)  selected=("${MODULES[@]}") ;;
  # In khối comment đầu file, dừng ngay dòng code đầu tiên (khỏi phải đếm dòng
  # bằng tay mỗi lần sửa header).
  --help|-h) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
  "")
    list_modules
    echo
    echo "  a) tất cả"
    read -r -p "Chọn (vd: 1 3 4 | a): " -a picks </dev/tty || true
    for p in "${picks[@]:-a}"; do
      if [[ "$p" == "a" || "$p" == "all" ]]; then
        selected=("${MODULES[@]}"); break
      elif [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#MODULES[@]} )); then
        selected+=("${MODULES[p-1]}")
      else
        warn "Bỏ qua lựa chọn không hợp lệ: $p"
      fi
    done
    ;;
  *) selected=("$@") ;;
esac

(( ${#selected[@]} )) || die "Không có module nào được chọn."

# Bắt tên module sai TRƯỚC khi xin sudo và trước khi gỡ bất cứ thứ gì — gõ nhầm
# 1 chữ mà đã gỡ xong 2 module rồi mới báo lỗi thì quá muộn.
for m in "${selected[@]}"; do
  [[ -f "$HERE/$m/uninstall.sh" ]] || die "Không có module gỡ tên '$m'. Xem: $0 --list"
done

echo
log "Sẽ gỡ: ${selected[*]}"
if purging; then
  err "CHẾ ĐỘ --purge: xoá luôn dữ liệu cá nhân của các module trên."
  err "  docker volume/image, ~/.nvm, profile Chrome & VS Code, lịch sử clipboard..."
  err "  (SSH key và git user.name/email vẫn được giữ nguyên.)"
else
  dim "Chế độ an toàn: giữ nguyên dữ liệu cá nhân. Thêm --purge nếu muốn xoá sạch."
fi

confirm "Tiếp tục gỡ?" || die "Đã huỷ."

need_sudo   # xin sudo 1 lần cho cả run

for m in "${selected[@]}"; do run_module "$m"; done

echo
if (( ${#FAILED[@]} )); then
  err "Module lỗi: ${FAILED[*]}"
else
  ok "Đã gỡ xong các module đã chọn."
fi
cat <<'EOF'

Việc cần làm thủ công sau khi gỡ:
  • Logout/reboot  -> áp dụng shell bash, bỏ group docker, bỏ ibus engine.
  • Gói apt mồ côi: xem `apt list '~o'` rồi `sudo apt autoremove` nếu muốn dọn.
  • Bản backup của các file config nằm cạnh file gốc: *.bak-<ngày giờ>.
EOF
