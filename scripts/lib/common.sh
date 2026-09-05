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

# Máy vừa cài thường vừa nối WiFi/DHCP xong, mạng chưa ổn định; hỏng đúng một
# nhịp là cả module fail. --retry chỉ thử lại với lỗi kết nối và 5xx/408/429,
# KHÔNG thử lại 404 — nên chỗ dùng curl để dò "repo này có tồn tại không" vẫn
# trả lời sai/đúng ngay lập tức như cũ.
CURL_RETRY=(--retry 3 --retry-connrefused --retry-delay 2)

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

# --- apt ----------------------------------------------------------------------
# Mọi lệnh apt phải đi qua đây, đừng gọi `sudo apt-get` thẳng.
#
# DPkg::Lock::Timeout là thứ quan trọng nhất: trên máy vừa cài xong, systemd chạy
# apt-daily/unattended-upgrades ngay sau lần boot đầu và giữ khoá dpkg vài phút.
# Mặc định apt KHÔNG chờ, nó fail ngay -> module đầu tiên chết, rồi mọi module
# dùng apt phía sau chết theo, trong khi thật ra chỉ cần đợi một lúc.
APT_LOCK_WAIT="${APT_LOCK_WAIT:-300}"
apt_get() { # apt_get <đối số của apt-get>
  sudo DEBIAN_FRONTEND=noninteractive \
       apt-get -o DPkg::Lock::Timeout="$APT_LOCK_WAIT" "$@"
}

# Dấu hiệu "đã apt update trong lượt chạy này".
#
# Không dùng riêng biến _APT_UPDATED được: dispatcher chạy mỗi module bằng một
# tiến trình `bash` riêng, biến của tiến trình con không truyền ngược lên cha,
# nên `--all` sẽ update lại 5-6 lần. Dispatcher export UBUNTU_SETUP_RUN (một thư
# mục tạm cho cả lượt chạy) để các module dùng chung một dấu hiệu trên đĩa.
# Chạy module lẻ (không qua dispatcher) thì biến đó trống -> quay về hành vi cũ.
# Phải trả 0 cả khi không có gì để in: viết `[[ ... ]] && printf` thì lúc biến
# trống hàm trả 1, `stamp="$(_apt_stamp)"` mang theo exit code đó và `set -e`
# giết script ngay giữa chừng — chạy module lẻ sẽ chết im lặng.
_apt_stamp() {
  [[ -n "${UBUNTU_SETUP_RUN:-}" ]] || return 0
  printf '%s/apt-updated' "$UBUNTU_SETUP_RUN"
}

apt_update_once() {
  local stamp; stamp="$(_apt_stamp)"
  [[ -n "${_APT_UPDATED:-}" ]] && return 0
  [[ -n "$stamp" && -f "$stamp" ]] && { _APT_UPDATED=1; return 0; }
  log "apt update"
  apt_get update -y
  _APT_UPDATED=1
  [[ -n "$stamp" ]] && : >"$stamp"
  return 0
}

# Gọi sau khi thêm repo/PPA mới: lần apt_install kế tiếp phải update lại.
apt_invalidate_update() {
  local stamp; stamp="$(_apt_stamp)"
  _APT_UPDATED=""
  [[ -n "$stamp" ]] && rm -f "$stamp"
  return 0
}

apt_install() {
  apt_update_once
  log "apt install: $*"
  apt_get install -y "$@"
}

# Có mở được /dev/tty không? `[[ -r /dev/tty ]]` KHÔNG đủ: khi tiến trình không
# có controlling terminal (cron, setsid, một số container) thì file vẫn tồn tại và
# đủ quyền, chỉ có open() mới fail. Phải thử mở thật — và thử trong subshell, để
# lỗi redirect không giết luôn shell cha.
have_tty() { (: </dev/tty) 2>/dev/null; }

# Không có tty (ssh 'bash install.sh', cron, container...) -> coi như trả lời "no"
# thay vì đọc hụt rồi để biến rỗng. `ans` PHẢI được gán sẵn: `local ans` chỉ khai
# báo chứ không gán, nên `${ans,,}` sẽ nổ "unbound variable" dưới `set -u`.
confirm() { # confirm "Câu hỏi?"  -> 0 nếu yes
  [[ "${ASSUME_YES:-0}" == 1 ]] && { dim "? $1 -> yes (--yes)"; return 0; }
  local ans=""
  if ! have_tty; then
    warn "Không có tty để hỏi \"$1\" -> mặc định KHÔNG. Dùng ASSUME_YES=1 nếu muốn tự động."
    return 1
  fi
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
  local ans=""
  if ! have_tty; then
    warn "Không có tty để xác nhận -> KHÔNG xoá. Dùng ASSUME_YES=1 nếu thật sự muốn."
    return 1
  fi
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
  apt_get "$verb" -y "${present[@]}"
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

# Ghi lại khối `plugins=(...)` trong .zshrc.
#
# Phải xử lý được cả dạng nhiều dòng — rất nhiều người viết .zshrc kiểu này:
#     plugins=(
#       git
#       docker
#     )
# `sed` làm việc theo từng dòng nên chỉ thay được dòng `plugins=(`, để lại phần
# đuôi `git`, `docker`, `)` lơ lửng -> zsh báo lỗi cú pháp mỗi lần mở shell.
# Nên khớp cả khối bằng perl -0777 (slurp cả file), và chỉ thay lần xuất hiện đầu.
set_zsh_plugins() { # set_zsh_plugins <file> <danh sách plugin>
  local file="$1" plugins="$2"
  [[ -f "$file" ]] || { ensure_line "$file" "plugins=($plugins)"; return 0; }
  if grep -qE '^[[:space:]]*plugins=\(' "$file"; then
    backup_file "$file"
    ZSH_PLUGINS="$plugins" perl -0777 -i \
      -pe 's/^[ \t]*plugins=\([^)]*\)/"plugins=(" . $ENV{ZSH_PLUGINS} . ")"/me' "$file"
  else
    ensure_line "$file" "plugins=($plugins)"
  fi
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


# ==============================================================================
# Giao diện: menu chọn module + header/tổng kết cho dispatcher
# ==============================================================================
# Menu tự vẽ thay vì whiptail: newt hardcode Enter trong listbox = submit, không
# remap được, mà ta muốn Enter dùng để bật/tắt lựa chọn.
#
# Phím:  ↑↓ di chuyển · Enter/Space bật/tắt
#        ↓ ở dòng cuối rơi xuống hàng nút OK/Huỷ, ↑ ở đó thì quay lại
#        Tab nhảy nhanh giữa danh sách và nút · ←→ đổi nút · Esc/q huỷ
#
# Cần terminal tương tác. NO_TUI=1 hoặc TERM=dumb hoặc không có tty -> menu gõ số.
use_tui() {
  [[ "${NO_TUI:-0}" == 1 ]] && return 1
  [[ -n "${TERM:-}" && "$TERM" != dumb ]] || return 1
  have_tty
}

term_cols()  { tput cols  2>/dev/null || echo 80; }
term_lines() { tput lines 2>/dev/null || echo 24; }

# Kẻ một đường ngang dài hết bề ngang terminal, có tiêu đề ở đầu.
#   ────── [3/8] nvm-node ─────────────────────────
hr_title() { # hr_title <tiêu đề>
  local title="$1" cols pad n
  cols="$(term_cols)"; (( cols > 100 )) && cols=100
  n=$(( cols - ${#title} - 9 )); (( n < 3 )) && n=3
  printf -v pad '%*s' "$n" ''
  printf "${C_BLUE}────── %s ${C_RESET}${C_DIM}%s${C_RESET}\n" "$title" "${pad// /─}"
}

fmt_dur() { # fmt_dur <giây> -> 8s | 1m06s
  local s="$1"
  (( s < 60 )) && { printf '%ds' "$s"; return; }
  printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
}

# Số CỘT HIỂN THỊ của một chuỗi. Không dùng ${#s}: nó đếm ký tự ở locale UTF-8
# nhưng đếm BYTE ở LANG=C, nên viền phải của khung sẽ lệch tuỳ máy. Đếm số byte
# dẫn đầu UTF-8 (bỏ mọi byte tiếp diễn 0x80-0xBF) thì đúng ở mọi locale.
# Chỉ đúng với ký tự rộng 1 cột — đủ dùng: ta chỉ hiển thị chữ Latin/tiếng Việt.
dwidth() { printf '%s' "$1" | tr -d '\200-\277' | wc -c; }

rep() { # rep <ký tự> <số lần>
  local pad; printf -v pad '%*s' "$2" ''; printf '%s' "${pad// /$1}"
}

# Checklist tự vẽ, có khung.
#   menu_checklist <tiêu đề> <nhãn nút OK> <tag> <mô tả> <on|off> ...
# In ra STDOUT các tag được chọn (mỗi dòng một tag); trả 1 nếu người dùng huỷ.
#
# Giao diện vẽ thẳng ra /dev/tty (fd 3) chứ không ra stdout: người gọi dùng
# `chosen="$(menu_checklist ...)"` nên stdout đã bị command substitution nuốt.
#
# Phím:  ↑↓ di chuyển (↓ ở dòng cuối rơi xuống hàng nút, ↑ ở đó thì quay lại)
#        Enter/Space bật/tắt · Tab nhảy nhanh · ←→ đổi nút · Esc/q huỷ
menu_checklist() {
  local title="$1" oklabel="$2"; shift 2
  local -a tag=() desc=() on=()
  while (( $# >= 3 )); do
    tag+=("$1"); desc+=("$2"); [[ "$3" == on ]] && on+=(1) || on+=(0); shift 3
  done
  local n=${#tag[@]} focus=0 btn=0 i key rest

  # --- đo & đệm sẵn một lần, không đo lại mỗi lần vẽ ---------------------------
  local tagw=0 descw=0 w
  for (( i = 0; i < n; i++ )); do
    w=$(dwidth "${tag[i]}");  (( w > tagw ))  && tagw=$w
    w=$(dwidth "${desc[i]}"); (( w > descw )) && descw=$w
  done
  local hint="↑↓ chọn · Enter bật/tắt · Tab nhảy nhanh · Esc huỷ"
  local titlew hintw
  titlew=$(dwidth "$title"); hintw=$(dwidth "$hint")

  # inner = "  " + [✓] + " " + tag + "  " + mô tả + " "
  local inner=$(( tagw + descw + 9 ))
  (( inner < hintw + 2 ))   && inner=$(( hintw + 2 ))
  (( inner < titlew + 12 )) && inner=$(( titlew + 12 ))
  # Terminal hẹp hơn khung thì bỏ viền, vẽ trần — vẫn dùng được, chỉ kém đẹp.
  local framed=1
  (( $(term_cols) < inner + 2 )) && framed=0

  local -a tagpad=() descpad=()
  for (( i = 0; i < n; i++ )); do
    tagpad[i]="${tag[i]}$(rep ' ' $(( tagw - $(dwidth "${tag[i]}") )))"
    descpad[i]="${desc[i]}$(rep ' ' $(( descw - $(dwidth "${desc[i]}") )))"
  done
  # inner - hintw - 2: trừ 2 khoảng trắng thụt đầu dòng. (Đếm nhầm thành 3 thì
  # riêng dòng này ngắn hơn các dòng khác 1 cột, viền phải bị thụt vào.)
  local hintpad="$hint$(rep ' ' $(( inner - hintw - 2 )))"
  local bar; bar="$(rep '─' "$inner")"

  exec 3>/dev/tty 4</dev/tty
  local drawn=0 rows=$(( n + 8 ))
  restore_term() { printf '\033[?25h' >&3; exec 3>&- 4<&- 2>/dev/null || true; }
  trap 'restore_term; trap - INT; kill -INT $$' INT
  trap 'restore_term' RETURN
  printf '\033[?25l' >&3

  # Vẽ một dòng nội dung, kèm viền nếu có.
  line() { # line <nội dung đã đệm đủ $inner cột>
    if (( framed )); then printf "\033[K${C_DIM}│${C_RESET}%b${C_DIM}│${C_RESET}\n" "$1" >&3
    else                  printf '\033[K%b\n' "$1" >&3; fi
  }

  draw() {
    (( drawn )) && printf '\033[%dA' "$rows" >&3
    drawn=1
    local sel=0
    for (( i = 0; i < n; i++ )); do (( on[i] )) && sel=$(( sel + 1 )); done
    local count="$sel/$n"
    local fill=$(( inner - 6 - titlew - ${#count} ))
    (( fill < 1 )) && fill=1

    if (( framed )); then
      printf "\033[K${C_DIM}╭─ ${C_RESET}${C_BLUE}%s${C_RESET} ${C_DIM}%s %s ─╮${C_RESET}\n" \
        "$title" "$(rep '─' "$fill")" "$count" >&3
    else
      printf "\033[K  ${C_BLUE}%s${C_RESET}  ${C_DIM}%s${C_RESET}\n" "$title" "$count" >&3
    fi
    line "$(rep ' ' "$inner")"

    for (( i = 0; i < n; i++ )); do
      # Hai kênh hiển thị TÁCH BẠCH:
      #   đảo màu cả dòng = đang đứng ở đâu
      #   ô [✓] / [ ]     = đang bật hay tắt
      # Trước đây dùng ●/○ tô xanh, nhưng dòng đang chọn bị đảo màu nên mất luôn
      # màu, chỉ còn phân biệt đặc/rỗng — nhìn không ra. Ô có/không có dấu tick
      # thì rõ kể cả khi không còn màu.
      local box='[ ]' body
      (( on[i] )) && box='[✓]'
      if (( focus == i )); then
        body="\033[7m  $box ${tagpad[i]}  ${descpad[i]} \033[0m"
      elif (( on[i] )); then
        body="  ${C_GREEN}$box${C_RESET} ${tagpad[i]}  ${C_DIM}${descpad[i]}${C_RESET} "
      else
        body="  ${C_DIM}$box${C_RESET} ${tagpad[i]}  ${C_DIM}${descpad[i]}${C_RESET} "
      fi
      line "$body"
    done

    line "$(rep ' ' "$inner")"
    if (( framed )); then
      printf "\033[K${C_DIM}├%s┤${C_RESET}\n" "$bar" >&3
    else
      printf '\033[K\n' >&3
    fi
    line "  ${C_DIM}${hintpad}${C_RESET}"
    if (( framed )); then printf "\033[K${C_DIM}╰%s╯${C_RESET}\n" "$bar" >&3
    else                  printf '\033[K\n' >&3; fi

    local b1=" $oklabel " b2=" Huỷ bỏ "
    if (( focus == n && btn == 0 )); then b1="\033[7m$b1\033[0m"; else b1="${C_DIM}[${C_RESET}$b1${C_DIM}]${C_RESET}"; fi
    if (( focus == n && btn == 1 )); then b2="\033[7m$b2\033[0m"; else b2="${C_DIM}[${C_RESET}$b2${C_DIM}]${C_RESET}"; fi
    printf '\033[K\n\033[K      %b     %b\n' "$b1" "$b2" >&3
  }

  while :; do
    draw
    IFS= read -rsN1 key <&4 || { restore_term; return 1; }
    case "$key" in
      $'\e')
        # Esc đơn độc = huỷ; Esc[A/B/C/D = phím mũi tên. Phân biệt bằng timeout:
        # phím mũi tên gửi cả chuỗi liền một mạch, Esc thật thì không có gì theo sau.
        if IFS= read -rsN1 -t 0.05 rest <&4 && [[ "$rest" == '[' || "$rest" == O ]]; then
          IFS= read -rsN1 -t 0.05 rest <&4 || rest=''
          case "$rest" in
            # ↓ ở dòng cuối rơi xuống hàng nút, ↑ ở hàng nút thì quay lại danh
            # sách — giống trình cài Ubuntu. Tab vẫn còn để nhảy nhanh.
            A) if (( focus == n )); then focus=$(( n - 1 ))
               elif (( focus > 0 )); then focus=$(( focus - 1 )); fi ;;
            B) if (( focus < n - 1 )); then focus=$(( focus + 1 ))
               elif (( focus == n - 1 )); then focus=$n; btn=0; fi ;;
            C) (( focus == n )) && btn=1 ;;
            D) (( focus == n )) && btn=0 ;;
            Z) (( focus == n )) && focus=0 ;;              # Shift+Tab
          esac
        else
          restore_term; return 1
        fi ;;
      $'\t')
        if (( focus < n )); then focus=$n; btn=0; else focus=0; fi ;;
      $'\n'|$'\r'|'')
        if (( focus < n )); then
          on[focus]=$(( 1 - on[focus] ))
        elif (( btn == 0 )); then
          break
        else
          restore_term; return 1
        fi ;;
      ' ')
        (( focus < n )) && on[focus]=$(( 1 - on[focus] )) ;;
      q|Q) restore_term; return 1 ;;
    esac
  done

  restore_term
  for (( i = 0; i < n; i++ )); do (( on[i] )) && printf '%s\n' "${tag[i]}"; done
  return 0
}
