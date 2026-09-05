#!/usr/bin/env bash
# Script tổng: chạy tất cả, chạy vài module, hoặc chọn từ menu.
#
#   ./install.sh                 # menu checklist (mặc định)
#   ./install.sh --all           # chạy hết theo thứ tự
#   ./install.sh zsh docker      # chỉ chạy module chỉ định
#   ./install.sh --list          # liệt kê module
#
# Cờ:
#   --yes     không hỏi gì, trả lời "yes" cho mọi câu hỏi (dùng cho chạy tự động).
#
# Menu mặc định là checklist có khung: ↑↓ di chuyển (↓ ở dòng cuối rơi xuống
# hàng nút), Enter bật/tắt, Tab nhảy nhanh, Esc huỷ. Đặt NO_TUI=1 để dùng menu gõ số; script cũng tự lùi về menu số khi
# không có tty hoặc TERM=dumb.
#
# Bỏ qua phần hỏi bằng env var, vd:
#   NODE_VERSION=22 VN_INPUT_ENGINE=bamboo APPS=vscode,chrome ./install.sh --all
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

# Thứ tự chạy khi --all (base trước, phần còn lại phụ thuộc vào nó).
MODULES=(base zsh vietnamese-input nvm-node docker git apps clipboard disks)

describe() {
  case "$1" in
    base)            echo "Gói nền tảng: build-essential, curl, git, jq" ;;
    zsh)             echo "Oh My Zsh + Powerlevel10k + Nerd Font" ;;
    vietnamese-input) echo "Bộ gõ tiếng Việt (bamboo / unikey)" ;;
    nvm-node)        echo "nvm + Node.js + yarn/pnpm" ;;
    docker)          echo "Docker Engine + Compose, không cần sudo" ;;
    git)             echo "Cấu hình git, SSH key, GitHub CLI" ;;
    apps)            echo "VS Code, Chrome, Postman" ;;
    clipboard)       echo "Clipboard Indicator + phím tắt Super+V" ;;
    disks)           echo "Gắn ổ phụ vào fstab, tự mount khi boot" ;;
    *)               echo "" ;;
  esac
}

list_modules() {
  echo "Modules:"
  local i=1
  for m in "${MODULES[@]}"; do
    printf "  %d) %-18s %s\n" "$i" "$m" "$(describe "$m")"
    ((i++))
  done
}

# RESULTS ghi lại "<module>|<exit code>|<số giây>" để in bảng tổng kết ở cuối.
RESULTS=()

run_module() { # run_module <module> <thứ tự> <tổng số>
  local m="$1" i="$2" n="$3" script="$HERE/$1/install.sh"
  [[ -f "$script" ]] || die "Không tìm thấy module: $m ($script)"
  local start=$SECONDS rc=0
  echo
  hr_title "[$i/$n] $m"
  # Chạy như tiến trình riêng để 1 module fail không kéo cả run xuống.
  bash "$script" || rc=$?
  local dur=$(( SECONDS - start ))
  RESULTS+=("$m|$rc|$dur")
  if (( rc == 0 )); then
    ok "module '$m' xong. ($(fmt_dur "$dur"))"
  else
    err "module '$m' lỗi (exit $rc). Tiếp tục module kế tiếp."
    FAILED+=("$m")
  fi
}

# Bảng tổng kết. Cố tình KHÔNG kẻ viền phải: chiều rộng hiển thị của chuỗi tiếng
# Việt phụ thuộc locale (${#s} đếm ký tự ở locale UTF-8 nhưng đếm byte ở locale C),
# nên viền phải sẽ lệch hàng trên máy đặt LANG=C. Bỏ viền phải là luôn thẳng.
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
  printf "  %d xong · %d lỗi · tổng %s\n" "$okn" "$errn" "$(fmt_dur "$total")"
}

require_ubuntu

# --- đọc cờ --------------------------------------------------------------------
args=()
for a in "$@"; do
  case "$a" in
    --yes|-y) ASSUME_YES=1 ;;
    *)        args+=("$a") ;;
  esac
done
export ASSUME_YES
set -- "${args[@]+"${args[@]}"}"

log "Ubuntu ${OS_VERSION} (${OS_CODENAME:-?}) — ubuntu-setup"

FAILED=()
selected=()
chosen=""; on=""; tui_args=()

case "${1:-}" in
  --list|-l) list_modules; exit 0 ;;
  --all|-a)  selected=("${MODULES[@]}") ;;
  --help|-h) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
  "")
    if use_tui; then
      # Mặc định tick sẵn những module gần như ai cài máy mới cũng cần. `disks`
      # để trống: nó đụng tới phân vùng ổ đĩa, phải là lựa chọn có ý thức.
      tui_args=()
      for m in "${MODULES[@]}"; do
        case "$m" in disks) on=off ;; *) on=on ;; esac
        tui_args+=("$m" "$(describe "$m")" "$on")
      done
      # Không dùng `selected=($(menu_checklist ...))`: command substitution nuốt
      # mất exit code, nên bấm Huỷ sẽ bị hiểu thành "chọn rỗng".
      if ! chosen="$(menu_checklist "ubuntu-setup — chọn module muốn cài" "Bắt đầu cài" "${tui_args[@]}")"; then
        die "Đã huỷ."
      fi
      while IFS= read -r m; do [[ -n "$m" ]] && selected+=("$m"); done <<<"$chosen"
    else
      have_tty || die "Không có tty để hiện menu. Chỉ định module trực tiếp, hoặc dùng --all."
      list_modules
      echo
      echo "  a) tất cả"
      # Không đặt default là "a": `read -a` với input rỗng cho mảng rỗng, nên bấm
      # nhầm Enter là cài sạch mọi module mà không hỏi lại câu nào.
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

# Bắt tên module sai TRƯỚC khi xin sudo và trước khi cài bất cứ thứ gì — gõ nhầm
# 1 chữ mà đã cài xong 2 module rồi mới báo lỗi thì quá muộn.
for m in "${selected[@]}"; do
  [[ -f "$HERE/$m/install.sh" ]] || die "Không có module tên '$m'. Xem: $0 --list"
done

log "Sẽ chạy: ${selected[*]}"
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

Việc cần làm thủ công sau khi cài:
  • Logout/reboot  -> áp dụng zsh mặc định, group docker, ibus engine.
  • Bộ gõ tiếng Việt: đã thêm vào Input Sources tự động, chuyển bằng Super+Space.
  • Terminal: mở cửa sổ mới để nhận font JetBrainsMono Nerd Font Mono.
  • gh auth login  (nếu đã cài GitHub CLI)
  • Clipboard: bấm Super+V (ăn sau khi logout/reboot).
EOF
