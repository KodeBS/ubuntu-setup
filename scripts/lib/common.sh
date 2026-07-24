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
  # keep-alive
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
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
