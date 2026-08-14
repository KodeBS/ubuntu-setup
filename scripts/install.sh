#!/usr/bin/env bash
# Script tổng: chạy tất cả, chạy vài module, hoặc chọn từ menu.
#
#   ./install.sh                 # menu chọn (mặc định)
#   ./install.sh --all           # chạy hết theo thứ tự
#   ./install.sh zsh docker      # chỉ chạy module chỉ định
#   ./install.sh --list          # liệt kê module
#
# Bỏ qua phần hỏi bằng env var, vd:
#   NODE_VERSION=22 VN_INPUT_ENGINE=bamboo APPS=vscode,chrome ./install.sh --all
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

# Thứ tự chạy khi --all (base trước, phần còn lại phụ thuộc vào nó).
MODULES=(base zsh vietnamese-input nvm-node docker git apps clipboard)

describe() {
  case "$1" in
    base)            echo "Gói nền tảng: build-essential, curl, git, jq, ripgrep, fonts..." ;;
    zsh)             echo "zsh + Oh My Zsh + plugins + Powerlevel10k + font JetBrainsMono Nerd Font Mono" ;;
    vietnamese-input) echo "Bộ gõ tiếng Việt (ibus-bamboo / ibus-unikey)" ;;
    nvm-node)        echo "nvm + Node.js (chọn version, gợi ý 22 LTS) + yarn/pnpm" ;;
    docker)          echo "Docker Engine + Compose plugin, chạy không cần sudo" ;;
    git)             echo "Cấu hình git, SSH key, GitHub CLI" ;;
    apps)            echo "VS Code, Chrome, Postman" ;;
    clipboard)       echo "Clipboard Indicator (GNOME extension) + phím tắt Super+V" ;;
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

run_module() {
  local m="$1" script="$HERE/$1/install.sh"
  [[ -f "$script" ]] || die "Không tìm thấy module: $m ($script)"
  echo
  printf "${C_BLUE}────── %s ──────${C_RESET}\n" "$m"
  # chạy trong subshell để 1 module fail không kéo cả run xuống
  if bash "$script"; then
    ok "module '$m' xong."
  else
    err "module '$m' lỗi (exit $?). Tiếp tục module kế tiếp."
    FAILED+=("$m")
  fi
}

require_ubuntu
log "Ubuntu ${OS_VERSION} (${OS_CODENAME:-?}) — ubuntu-setup"

FAILED=()
selected=()

case "${1:-}" in
  --list|-l) list_modules; exit 0 ;;
  --all|-a)  selected=("${MODULES[@]}") ;;
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

log "Sẽ chạy: ${selected[*]}"
need_sudo   # xin sudo 1 lần cho cả run

for m in "${selected[@]}"; do run_module "$m"; done

echo
if (( ${#FAILED[@]} )); then
  err "Module lỗi: ${FAILED[*]}"
else
  ok "Tất cả module đã chạy xong."
fi
cat <<'EOF'

Việc cần làm thủ công sau khi cài:
  • Logout/reboot  -> áp dụng zsh mặc định, group docker, ibus engine.
  • Bộ gõ tiếng Việt: đã thêm vào Input Sources tự động, chuyển bằng Super+Space.
  • Terminal: mở cửa sổ mới để nhận font JetBrainsMono Nerd Font Mono.
  • gh auth login  (nếu đã cài GitHub CLI)
  • Clipboard: bấm Super+V (ăn sau khi logout/reboot).
EOF
