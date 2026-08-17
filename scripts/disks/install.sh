#!/usr/bin/env bash
# Gắn ổ cứng phụ vào máy vĩnh viễn: ghi vào /etc/fstab theo UUID nên tự mount
# mỗi lần boot, không phải vào file manager bấm mount thủ công nữa.
#
# Dùng cho ổ data/code gắn thêm (SSD thứ 2, HDD...). Không đụng tới ổ hệ thống.
#
#   ./install.sh                              # menu: chọn ổ, đặt tên
#   DISKS="/dev/sdb=Data" ./install.sh        # không hỏi gì
#   DISKS="/dev/sdb=Data;/dev/sdc=Media" ./install.sh   # nhiều ổ một lượt
#
# Vì sao dùng UUID chứ không phải /dev/sdb1: tên thiết bị do kernel cấp theo thứ
# tự phát hiện, cắm thêm ổ hoặc đổi khe M.2 là nvme0n1 <-> nvme1n1 hoán vị nhau
# ngay. UUID nằm trong superblock của filesystem nên không bao giờ đổi.
#
# Env var:
#   DISKS       "dev=Tên" ngăn nhau bằng ';'. Bỏ trống -> hiện menu chọn.
#   DISK_FORMAT never (mặc định) | empty | force
#                 never = chỉ mount ổ đã có filesystem, không format gì hết
#                 empty = ổ chưa có filesystem thì mới format
#                 force = format lại kể cả khi có dữ liệu (hỏi xác nhận 'yes')
#   DISK_FS     ext4 (mặc định) | xfs — filesystem dùng khi format
#   DISK_MOUNT_BASE  mặc định $HOME — mount point là $DISK_MOUNT_BASE/<Tên>
#   DISK_BOOKMARK    true (mặc định) — thêm vào sidebar của Files
#   DISK_REMOVE_LOST_FOUND  true (mặc định) — xoá lost+found sau khi format
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

require_ubuntu

# In khối comment đầu file, dừng ở dòng code đầu tiên (giống 2 dispatcher).
[[ "${1:-}" == --help || "${1:-}" == -h ]] && {
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0; }

DISKS="${DISKS:-}"
DISK_FORMAT="${DISK_FORMAT:-never}"
DISK_FS="${DISK_FS:-ext4}"
DISK_MOUNT_BASE="${DISK_MOUNT_BASE:-$HOME}"
DISK_BOOKMARK="${DISK_BOOKMARK:-true}"
DISK_REMOVE_LOST_FOUND="${DISK_REMOVE_LOST_FOUND:-true}"

FSTAB=/etc/fstab
MARK='# ubuntu-setup:disks'   # dấu nhận biết dòng do script này thêm, để uninstall gỡ đúng

case "$DISK_FORMAT" in never|empty|force) ;; *) die "DISK_FORMAT không hợp lệ: $DISK_FORMAT (never|empty|force)" ;; esac
case "$DISK_FS"     in ext4|xfs)          ;; *) die "DISK_FS không hỗ trợ: $DISK_FS (ext4|xfs)" ;; esac

need_sudo
has lsblk    || die "Thiếu lsblk (gói util-linux)."
has partprobe || apt_install parted
has parted   || apt_install parted
[[ "$DISK_FS" == xfs ]] && ! has mkfs.xfs && apt_install xfsprogs

# --- nhận diện ổ hệ thống ------------------------------------------------------
# Ổ nào đang chứa /, /boot, /boot/efi hoặc swap thì tuyệt đối không được đụng.
system_disks() {
  local mp src pk
  for mp in / /boot /boot/efi; do
    src="$(findmnt -no SOURCE --target "$mp" 2>/dev/null || true)"
    [[ -n "$src" && -b "$src" ]] || continue
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
    [[ -n "$pk" ]] && echo "/dev/$pk" || echo "$src"
  done
  # swap trên partition (swapfile thì nằm trong / nên đã tính ở trên)
  while read -r name type _; do
    [[ "$type" == partition && -b "$name" ]] || continue
    pk="$(lsblk -no PKNAME "$name" 2>/dev/null | head -1)"
    [[ -n "$pk" ]] && echo "/dev/$pk"
  done < <(tail -n +2 /proc/swaps 2>/dev/null || true)
}

SYS_DISKS="$(system_disks | sort -u)"
is_system_disk() { grep -qxF -- "$1" <<<"$SYS_DISKS"; }

# Tên partition đầu tiên: nvme/mmc/loop chèn thêm 'p' trước số.
part1_of() {
  case "$1" in
    *nvme*|*mmcblk*|*loop*) echo "${1}p1" ;;
    *)                      echo "${1}1"  ;;
  esac
}

# --- liệt kê ổ có thể gắn ------------------------------------------------------
candidates() { # -> "dev size model fstype-của-partition-đầu"
  local dev size model
  while read -r dev size model; do
    is_system_disk "$dev" && continue
    printf '%s\t%s\t%s\n' "$dev" "$size" "${model:-?}"
  done < <(lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF=="disk" { $NF=""; print }')
}

describe_disk() { # mô tả ngắn nội dung ổ, để người dùng khỏi chọn nhầm
  local dev="$1" n out="" size fstype label
  n="$(lsblk -no NAME "$dev" | tail -n +2 | wc -l)"
  (( n )) || { echo "chưa chia phân vùng (trống)"; return; }
  # Thứ tự SIZE,FSTYPE,LABEL là cố ý: cột rỗng bị lsblk gộp mất, nên đặt cột
  # chắc chắn có giá trị lên đầu và cột có thể chứa dấu cách (LABEL) xuống cuối.
  while read -r size fstype label; do
    out+="${out:+ | }${fstype:-chưa format} $size${label:+ \"$label\"}"
  done < <(lsblk -no SIZE,FSTYPE,LABEL "$dev" | tail -n +2)
  echo "$out"
}

pick_disks_interactive() {
  local -a devs=() ; local line dev size model i=1
  while IFS=$'\t' read -r dev size model; do devs+=("$dev|$size|$model"); done < <(candidates)
  # Máy chỉ có một ổ là chuyện bình thường -> không coi là lỗi, để `install.sh
  # --all` không báo module này fail.
  (( ${#devs[@]} )) || { warn "Máy không có ổ nào ngoài ổ hệ thống — bỏ qua."; exit 0; }

  echo "Ổ có thể gắn thêm:"
  for line in "${devs[@]}"; do
    IFS='|' read -r dev size model <<<"$line"
    printf "  %d) %-16s %-8s %-24s %s\n" "$i" "$dev" "$size" "$model" "$(describe_disk "$dev")"
    i=$((i + 1))
  done
  echo
  local -a picks=()
  read -r -p "Chọn ổ (vd: 1 2): " -a picks </dev/tty || true
  (( ${#picks[@]} )) || die "Không chọn ổ nào."

  local p name
  for p in "${picks[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#devs[@]} )) || { warn "Bỏ qua: $p"; continue; }
    IFS='|' read -r dev size model <<<"${devs[p-1]}"
    read -r -p "Tên thư mục cho $dev (vd: Workspaces): " name </dev/tty || true
    [[ -n "$name" ]] || { warn "Không đặt tên, bỏ qua $dev"; continue; }
    SPECS+=("$dev=$name")
  done
}

# --- fstab ---------------------------------------------------------------------
# Ghi qua file tạm rồi validate; hỏng cú pháp fstab là lần boot sau vào emergency
# shell, nên luôn có backup và luôn `findmnt --verify` trước khi coi là xong.
fstab_write() { # fstab_write <nội dung mới trên stdin>
  local tmp; tmp="$(mktemp)"
  cat >"$tmp"
  sudo cp -a "$FSTAB" "${FSTAB}.bak-$(ts)"
  sudo cp "$tmp" "$FSTAB"
  rm -f "$tmp"
  if ! sudo findmnt --verify -F "$FSTAB" >/dev/null 2>&1; then
    warn "fstab mới không hợp lệ — khôi phục bản backup."
    sudo cp "$(ls -1t ${FSTAB}.bak-* | head -1)" "$FSTAB"
    die "Huỷ thay đổi fstab."
  fi
}

# Gỡ mọi dòng đang trỏ tới mount point này (kèm dòng đánh dấu ngay trên nó).
fstab_drop_mount() { # fstab_drop_mount <mount-point>
  local mp="$1"
  awk -v mp="$mp" -v mark="$MARK" '
    $0 ~ "^"mark { hold = $0; next }                 # giữ lại dòng đánh dấu, chờ xem dòng sau
    {
      if ($2 == mp) { hold = ""; next }              # đúng mount point -> bỏ cả cặp
      if (hold != "") { print hold; hold = "" }
      print
    }
    END { if (hold != "") print hold }
  ' "$FSTAB"
}

# --- sidebar của Files ---------------------------------------------------------
# Nautilus giữ bookmarks trong bộ nhớ và ghi đè file khi thoát -> sửa lúc nó đang
# chạy là mất trắng. Tắt nó trước rồi mới ghi.
bookmark_add() { # bookmark_add <path> <tên>
  [[ "$DISK_BOOKMARK" == true ]] || return 0
  local path="$1" name="$2" bm="$HOME/.config/gtk-3.0/bookmarks" uri tmp
  uri="file://${path// /%20}"

  if pgrep -x nautilus >/dev/null 2>&1; then
    nautilus -q >/dev/null 2>&1 || true
    sleep 1
  fi

  mkdir -p "$(dirname "$bm")"
  [[ -f "$bm" ]] || : >"$bm"
  grep -qE "^${uri}( |$)" "$bm" && { ok "Sidebar đã có '$name'."; return 0; }

  backup_file "$bm"
  tmp="$(mktemp)"
  grep -vE "^${uri}( |$)" "$bm" >"$tmp" || true
  printf '%s %s\n' "$uri" "$name" >>"$tmp"
  cat "$tmp" >"$bm"
  rm -f "$tmp"
  ok "Đã thêm '$name' vào sidebar của Files."
}

# --- xử lý một ổ ---------------------------------------------------------------
setup_disk() { # setup_disk <dev> <tên>
  local dev="$1" name="$2"
  local mp="$DISK_MOUNT_BASE/$name"
  local part fstype uuid opts

  [[ -b "$dev" ]] || { err "Không thấy thiết bị: $dev"; return 1; }
  is_system_disk "$dev" && { err "$dev là ổ hệ thống — từ chối đụng vào."; return 1; }
  [[ "$name" == */* ]] && { err "Tên không được chứa '/': $name"; return 1; }

  printf "${C_BLUE}────── %s -> %s ──────${C_RESET}\n" "$dev" "$mp"

  # Ổ đã mount ở chỗ khác thì dừng, không giật mount point khỏi tay ai.
  local busy
  busy="$(lsblk -no MOUNTPOINT "$dev" | grep -v '^$' | grep -vxF "$mp" || true)"
  [[ -z "$busy" ]] || { err "$dev đang mount ở: $busy — umount trước đã."; return 1; }

  # --- chọn partition để dùng --------------------------------------------------
  if [[ "$(lsblk -no NAME "$dev" | tail -n +2 | wc -l)" -gt 0 ]]; then
    part="$(lsblk -pno NAME "$dev" | tail -n +2 | head -1)"
  else
    part=""
  fi

  fstype="$([[ -n "$part" ]] && lsblk -no FSTYPE "$part" | head -1 || echo "")"

  # --- có cần format không -----------------------------------------------------
  local do_format=0
  case "$DISK_FORMAT" in
    never) [[ -n "$fstype" ]] || { err "$dev chưa có filesystem. Chạy lại với DISK_FORMAT=empty để format."; return 1; } ;;
    empty) [[ -n "$fstype" ]] || do_format=1 ;;
    force) do_format=1 ;;
  esac

  if (( do_format )); then
    local what="ổ trống"
    [[ -n "$fstype" ]] && what="filesystem $fstype${part:+ trên $part} ĐANG CÓ DỮ LIỆU"
    confirm_danger "Sắp format $dev ($what) — mất sạch, không khôi phục được." \
      || { warn "Bỏ qua $dev."; return 1; }

    log "Xoá bảng phân vùng cũ và tạo GPT mới trên $dev"
    sudo wipefs -a "$dev"
    sudo parted -s "$dev" mklabel gpt
    sudo parted -s -a optimal "$dev" mkpart "$name" "$DISK_FS" 1MiB 100%
    sudo partprobe "$dev"; sudo udevadm settle; sleep 1

    part="$(part1_of "$dev")"
    [[ -b "$part" ]] || { err "Không thấy partition $part sau khi tạo."; return 1; }

    log "Format $part ($DISK_FS, label '$name')"
    case "$DISK_FS" in
      # -m 1: ext4 mặc định giữ 5% cho root — trên ổ 500G là mất đứt 25G, ổ data
      # không cần nhiều thế.
      ext4) sudo mkfs.ext4 -F -L "$name" -m 1 "$part" ;;
      xfs)  sudo mkfs.xfs  -f -L "$name" "$part" ;;
    esac
    fstype="$DISK_FS"
  fi

  [[ -n "$part" ]] || { err "$dev không có partition nào dùng được."; return 1; }

  # Label khớp tên thư mục: label chính là chữ hiện trong sidebar/Disks.
  if [[ "$fstype" == ext4 ]] && has e2label; then
    local cur; cur="$(sudo e2label "$part" 2>/dev/null || true)"
    [[ "$cur" == "$name" ]] || { sudo e2label "$part" "$name"; ok "Đổi label: '${cur:-<trống>}' -> '$name'"; }
  fi

  uuid="$(sudo blkid -s UUID -o value "$part")"
  [[ -n "$uuid" ]] || { err "Không đọc được UUID của $part."; return 1; }

  # --- mount options -----------------------------------------------------------
  # nofail: ổ hỏng/tháo ra thì máy vẫn boot bình thường thay vì rơi vào emergency.
  # x-gvfs-hide: giấu mục "thiết bị" (có nút eject) trong sidebar — đã có bookmark
  # rồi, để cả hai vừa trùng vừa dễ bấm nhầm eject.
  opts="defaults,nofail,x-gvfs-hide"
  local chown_after=1
  case "$fstype" in
    ntfs|ntfs3|exfat|vfat)
      # FS không có khái niệm owner POSIX -> gán quyền bằng mount option.
      opts+=",uid=$(id -u),gid=$(id -g),umask=022"
      chown_after=0 ;;
  esac

  log "Tạo mount point $mp"
  sudo mkdir -p "$mp"

  log "Ghi /etc/fstab (UUID=$uuid)"
  { fstab_drop_mount "$mp"
    printf '%s %s\n' "$MARK" "$name"
    printf 'UUID=%s %s %s %s 0 2\n' "$uuid" "$mp" "$fstype" "$opts"
  } | fstab_write

  sudo systemctl daemon-reload
  findmnt "$mp" >/dev/null 2>&1 && sudo umount "$mp"
  sudo mount "$mp" || { err "Mount $mp thất bại."; return 1; }
  ok "Đã mount $part -> $mp"

  if (( chown_after )); then
    sudo chown "$(id -u):$(id -g)" "$mp"
    sudo chmod 755 "$mp"
    ok "Chủ sở hữu: $USER (ghi file không cần sudo)."
  fi

  # lost+found do mkfs.ext4 tạo, dùng để hứng file mồ côi khi fsck sửa lỗi. Nó
  # không có dấu chấm đầu tên nên luôn hiện trong file manager. Xoá đi cho gọn;
  # khi nào fsck cần, nó tự hỏi tạo lại.
  if (( do_format )) && [[ "$DISK_REMOVE_LOST_FOUND" == true && -d "$mp/lost+found" ]]; then
    sudo rmdir "$mp/lost+found" 2>/dev/null \
      && dim "  đã xoá $mp/lost+found (fsck sẽ tự tạo lại khi cần)" \
      || warn "lost+found không rỗng, giữ nguyên."
  fi

  bookmark_add "$mp" "$name"
  df -h "$mp" | tail -1
}

# --- chạy ----------------------------------------------------------------------
SPECS=()
if [[ -n "$DISKS" ]]; then
  IFS=';' read -r -a SPECS <<<"$DISKS"
else
  pick_disks_interactive
fi
(( ${#SPECS[@]} )) || die "Không có ổ nào để gắn."

FAILED=()
for spec in "${SPECS[@]}"; do
  spec="${spec// /}"
  [[ -z "$spec" ]] && continue
  [[ "$spec" == *=* ]] || { err "Sai cú pháp (cần dev=Tên): $spec"; FAILED+=("$spec"); continue; }
  echo
  setup_disk "${spec%%=*}" "${spec#*=}" || FAILED+=("$spec")
done

echo
(( ${#FAILED[@]} )) && err "Không xử lý được: ${FAILED[*]}"

cat <<EOF

Ổ đã gắn cố định qua /etc/fstab (theo UUID) — tự mount mỗi lần boot.
  • Kiểm tra:  findmnt --verify   và   lsblk -o NAME,LABEL,SIZE,MOUNTPOINT
  • Sidebar Files: mở lại Files (đã tắt lúc ghi bookmark) là thấy mục mới.
  • Backup fstab nằm ở /etc/fstab.bak-<ngày giờ>.
  • Muốn tháo: ./scripts/disks/uninstall.sh (chỉ gỡ mount, KHÔNG xoá dữ liệu).
EOF
