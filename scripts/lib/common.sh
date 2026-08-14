#!/usr/bin/env bash
# Shared helpers for all setup scripts.
# Source this, don't execute it:  source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

C_RESET='\033[0m'; C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_DIM='\033[2m'

log()   { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[ok]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[warn]${C_RESET} %s\n" "$*" >&2; }
err()   { printf "${C_RED}[err]${C_RESET} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
dim()   { printf "${C_DIM}%s${C_RESET}\n" "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

# --- OS detection -------------------------------------------------------------
# shellcheck disable=SC1091
[[ -r /etc/os-release ]] && . /etc/os-release
OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-unknown}"           # 24.04, 26.04, ...
OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"  # noble, resolute, ...

require_ubuntu() {
  [[ "$OS_ID" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] \
    || die "Script này dành cho Ubuntu/Debian (đang chạy: $OS_ID)."
}

# Ask sudo once up-front and keep the timestamp alive for the whole run.
need_sudo() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  has sudo || die "Cần sudo."
  sudo -v || die "Không lấy được quyền sudo."
  # Keep-alive. Phải đóng hẳn stdout/stderr của tiến trình nền: nó kế thừa fd của
  # script, nên khi chạy qua pipe (`./install.sh --all | tee log`) thì pipe không
  # bao giờ đóng và lệnh phía sau treo tới 60s sau khi script đã xong.
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done >/dev/null 2>&1 &
}

apt_update_once() {
  if [[ -z "${_APT_UPDATED:-}" ]]; then
    log "apt update"
    sudo apt-get update -y
    _APT_UPDATED=1
  fi
}

apt_install() {
  apt_update_once
  log "apt install: $*"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

confirm() { # confirm "Câu hỏi?"  -> 0 nếu yes
  [[ "${ASSUME_YES:-0}" == 1 ]] && { dim "? $1 -> yes (--yes)"; return 0; }
  local ans
  read -r -p "$(printf "${C_YELLOW}?${C_RESET} %s [y/N] " "$1")" ans </dev/tty || true
  [[ "${ans,,}" == y || "${ans,,}" == yes ]]
}

# Append a line to a file only if it isn't there yet.
ensure_line() { # ensure_line <file> <line>
  local file="$1" line="$2"
  [[ -f "$file" ]] || touch "$file"
  grep -qxF -- "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

# ==============================================================================
# Uninstall helpers — chỉ dùng bởi uninstall.sh và các <module>/uninstall.sh
# ==============================================================================
# PURGE=1      -> gỡ luôn dữ liệu/cấu hình cá nhân (apt purge, xoá ~/.nvm, ...)
# ASSUME_YES=1 -> không hỏi gì, dùng cho chạy tự động
PURGE="${PURGE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

purging() { [[ "$PURGE" == 1 ]]; }

# Xác nhận cho thao tác KHÔNG khôi phục được: phải gõ đúng chữ 'yes'.
confirm_danger() { # confirm_danger "Sắp xoá vĩnh viễn X"
  err "$1"
  [[ "$ASSUME_YES" == 1 ]] && { warn "--yes: bỏ qua xác nhận, vẫn xoá."; return 0; }
  local ans
  read -r -p "$(printf "${C_RED}!!${C_RESET} Gõ 'yes' để xác nhận: ")" ans </dev/tty || true
  [[ "$ans" == yes ]]
}

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed"; }

# Gỡ gói apt, bỏ qua gói chưa cài. Dùng `purge` khi PURGE=1 để dọn cả file config.
apt_remove() { # apt_remove <pkg>...
  local present=() p
  for p in "$@"; do pkg_installed "$p" && present+=("$p"); done
  if (( ${#present[@]} == 0 )); then
    dim "chưa cài, bỏ qua: $*"
    return 0
  fi
  local verb=remove
  purging && verb=purge
  log "apt-get $verb: ${present[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get "$verb" -y "${present[@]}"
}

ts() { date +%Y%m%d-%H%M%S; }

# Copy file ra .bak-<timestamp> trước khi sửa/xoá. Không bao giờ ghi đè bản cũ.
backup_file() { # backup_file <path>
  local f="$1"
  [[ -f "$f" ]] || return 0
  local b="${f}.bak-$(ts)"
  cp -a -- "$f" "$b"
  dim "  backup: $b"
}

# Xoá có rào chắn: chỉ chấp nhận đường dẫn nằm trong $HOME hoặc allowlist hệ thống.
# Mọi thứ khác bị từ chối chứ không im lặng làm bừa.
#
# Trả 0 chỉ khi MỌI path đã thật sự biến mất. Bị từ chối hoặc xoá hụt -> trả 1,
# để caller không in "[ok] đã xoá" trong khi file vẫn còn nguyên.
safe_rm() { # safe_rm <path>...
  local p rc=0
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    [[ -e "$p" || -L "$p" ]] || continue
    if [[ "$p" == "/" || "$p" == "$HOME" || "$p" == "$HOME/" ]]; then
      warn "Từ chối xoá: $p"; rc=1; continue
    fi
    case "$p" in
      "$HOME"/?*)                        rm -rf -- "$p" || rc=1 ;;
      /etc/apt/sources.list.d/?*|/etc/apt/keyrings/?*|/etc/apt/trusted.gpg.d/?*) \
                                         sudo rm -f  -- "$p" || rc=1 ;;
      /var/lib/docker|/var/lib/containerd) sudo rm -rf -- "$p" || rc=1 ;;
      *) warn "Từ chối xoá đường dẫn ngoài phạm vi cho phép: $p"; rc=1; continue ;;
    esac
    if [[ -e "$p" || -L "$p" ]]; then
      err "Xoá không thành công: $p"; rc=1
    else
      dim "  đã xoá: $p"
    fi
  done
  return $rc
}

# Xoá mọi dòng khớp regex khỏi file (có backup). Giữ nguyên quyền/owner của file.
strip_lines() { # strip_lines <file> <extended-regex>
  local file="$1" re="$2" tmp
  [[ -f "$file" ]] || return 0
  grep -qE -- "$re" "$file" || return 0
  backup_file "$file"
  tmp="$(mktemp)"
  grep -vE -- "$re" "$file" >"$tmp" || true
  cat "$tmp" >"$file"
  rm -f "$tmp"
  ok "Đã dọn dòng cũ trong $file"
}

# Chỉ unset git config khi giá trị đúng bằng cái script này từng đặt.
# Người dùng tự đổi giá trị -> giữ nguyên, không đụng vào.
git_unset_if() { # git_unset_if <key> <expected-value>
  local key="$1" want="$2" cur
  cur="$(git config --global --get "$key" 2>/dev/null || true)"
  [[ "$cur" == "$want" ]] || return 0
  git config --global --unset "$key" 2>/dev/null || true
  dim "  git config --unset $key"
}
