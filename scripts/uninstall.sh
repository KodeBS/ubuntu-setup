#!/usr/bin/env bash
# Script gỡ: đảo ngược những gì install.sh đã cài.
#
#   ./uninstall.sh                 # menu checklist (mặc định, không tick sẵn gì)
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
# Menu mặc định là checklist có khung (↑↓ · Enter bật/tắt · Tab · Esc huỷ);
# NO_TUI=1 để dùng menu gõ số.
#
# MẶC ĐỊNH (không có --purge): chỉ gỡ package + hoàn tác cấu hình do script tạo.
# Dữ liệu cá nhân giữ nguyên. SSH key và git user.name/user.email KHÔNG BAO GIỜ
# bị đụng tới, kể cả khi --purge.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

# Ngược thứ tự install (base gỡ sau cùng vì mọi module khác dựa vào nó).
MODULES=(disks clipboard homelab apps git docker nvm-node vietnamese-input zsh base)

describe() {
  case "$1" in
    disks)            echo "Bỏ ổ phụ khỏi fstab (KHÔNG xoá dữ liệu)" ;;
    clipboard)        echo "Clipboard Indicator + trả Super+V về tray" ;;
    homelab)          echo "KodeBS Homelab + repo apt KodeBS" ;;
    apps)             echo "VS Code, Chrome, Postman + repo apt" ;;
    git)              echo "GitHub CLI + alias (GIỮ SSH key & email)" ;;
    docker)           echo "Docker Engine/Compose, repo, group docker" ;;
    nvm-node)         echo "nvm + mọi bản Node + snippet trong rc" ;;
    vietnamese-input) echo "ibus-bamboo/unikey + PPA (GIỮ gói ibus)" ;;
    zsh)              echo "Oh My Zsh, p10k, font, zsh; về lại bash" ;;
    base)             echo "Tiện ích CLI an toàn (jq, tree, rg, fd)" ;;
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

# RESULTS ghi lại "<module>|<exit code>|<số giây>" để in bảng tổng kết ở cuối.
RESULTS=()

run_module() { # run_module <module> <thứ tự> <tổng số>
  local m="$1" i="$2" n="$3" script="$HERE/$1/uninstall.sh"
  [[ -f "$script" ]] || die "Không tìm thấy module gỡ: $m ($script)"
  local start=$SECONDS rc=0
  echo
  hr_title "[$i/$n] gỡ $m"
  bash "$script" || rc=$?
  local dur=$(( SECONDS - start ))
  RESULTS+=("$m|$rc|$dur")
  if (( rc == 0 )); then
    ok "module '$m' đã gỡ xong. ($(fmt_dur "$dur"))"
  else
    err "module '$m' lỗi (exit $rc). Tiếp tục module kế tiếp."
    FAILED+=("$m")
  fi
}

# Không kẻ viền phải: bề rộng hiển thị của chuỗi tiếng Việt phụ thuộc locale
# (${#s} đếm ký tự ở UTF-8 nhưng đếm byte ở LANG=C) nên viền phải sẽ lệch hàng.
print_summary() {
  local line m rc dur okn=0 errn=0 total=0
  echo
  printf "${C_DIM}╭─ Tổng kết ─────────────────────────────${C_RESET}\n"
  for line in "${RESULTS[@]+"${RESULTS[@]}"}"; do
    IFS='|' read -r m rc dur <<<"$line"
    total=$(( total + dur ))
    if (( rc == 0 )); then
      okn=$(( okn + 1 ))
      printf "${C_DIM}│${C_RESET}  ${C_GREEN}✔${C_RESET} %-18s %6s\n" "$m" "$(fmt_dur "$dur")"
    else
      errn=$(( errn + 1 ))
      printf "${C_DIM}│${C_RESET}  ${C_RED}✘${C_RESET} %-18s %6s  ${C_RED}exit %s${C_RESET}\n" "$m" "$(fmt_dur "$dur")" "$rc"
    fi
  done
  printf "${C_DIM}╰────────────────────────────────────────${C_RESET}\n"
  printf "  %d đã gỡ · %d lỗi · tổng %s\n" "$okn" "$errn" "$(fmt_dur "$total")"
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
chosen=""; tui_args=()

case "${1:-}" in
  --list|-l) list_modules; exit 0 ;;
  --all|-a)  selected=("${MODULES[@]}") ;;
  # In khối comment đầu file, dừng ngay dòng code đầu tiên (khỏi phải đếm dòng
  # bằng tay mỗi lần sửa header).
  --help|-h) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
  "")
    if use_tui; then
      # Khác install: ở đây KHÔNG tick sẵn gì cả. Đây là thao tác gỡ, mặc định
      # phải là "không đụng gì" — người dùng tự tick đúng thứ mình muốn bỏ.
      tui_args=()
      for m in "${MODULES[@]}"; do tui_args+=("$m" "$(describe "$m")" off); done
      if ! chosen="$(menu_checklist "ubuntu-setup — chọn module muốn GỠ" "Bắt đầu gỡ" "${tui_args[@]}")"; then
        die "Đã huỷ."
      fi
      while IFS= read -r m; do [[ -n "$m" ]] && selected+=("$m"); done <<<"$chosen"
    else
      have_tty || die "Không có tty để hiện menu. Chỉ định module trực tiếp, hoặc dùng --all."
      list_modules
      echo
      echo "  a) tất cả"
      # Không đặt default là "a": `read -a` với input rỗng cho mảng rỗng, nên bấm
      # nhầm Enter là chọn gỡ sạch mọi module.
      read -r -p "Chọn (vd: 1 3 4 | a | Enter để huỷ): " -a picks </dev/tty || true
      for p in "${picks[@]+"${picks[@]}"}"; do
        if [[ "$p" == "a" || "$p" == "all" ]]; then
          selected=("${MODULES[@]}"); break
        elif [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#MODULES[@]} )); then
          selected+=("${MODULES[p-1]}")
        else
          warn "Bỏ qua lựa chọn không hợp lệ: $p"
        fi
      done
    fi
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

# Thư mục dùng chung cho cả lượt chạy: các module là tiến trình riêng nên cần
# một chỗ trên đĩa để báo nhau "đã apt update rồi" (xem apt_update_once).
UBUNTU_SETUP_RUN="$(mktemp -d)"
export UBUNTU_SETUP_RUN
trap 'rm -rf "$UBUNTU_SETUP_RUN"' EXIT

need_sudo   # xin sudo 1 lần cho cả run

idx=0
for m in "${selected[@]}"; do
  idx=$(( idx + 1 ))
  run_module "$m" "$idx" "${#selected[@]}"
done

print_summary
if (( ${#FAILED[@]} )); then
  err "Module lỗi: ${FAILED[*]}"
fi
cat <<'EOF'

Việc cần làm thủ công sau khi gỡ:
  • Logout/reboot  -> áp dụng shell bash, bỏ group docker, bỏ ibus engine.
  • Gói apt mồ côi: xem `apt list '~o'` rồi `sudo apt autoremove` nếu muốn dọn.
  • Bản backup của các file config nằm cạnh file gốc: *.bak-<ngày giờ>.
EOF
