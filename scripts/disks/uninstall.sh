#!/usr/bin/env bash
# Gỡ các ổ do disks/install.sh gắn: bỏ dòng trong /etc/fstab, umount, xoá bookmark
# trong sidebar, dọn mount point rỗng.
#
# KHÔNG BAO GIỜ format hay xoá dữ liệu trên ổ — kể cả với --purge. Ổ chỉ thôi
# không tự mount nữa; cắm vào máy khác hay mount tay là dữ liệu còn nguyên.
# Muốn xoá sạch ổ thì tự chạy: DISK_FORMAT=force ./disks/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

[[ "${1:-}" == --help || "${1:-}" == -h ]] && {
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0; }

FSTAB=/etc/fstab
MARK='# ubuntu-setup:disks'

# Đọc các mount point script này từng thêm: dòng ngay sau dòng đánh dấu.
managed_mounts() {
  awk -v mark="$MARK" '
    $0 ~ "^"mark { seen = 1; next }
    seen         { if ($2 != "") print $2; seen = 0 }
  ' "$FSTAB"
}

mapfile -t MOUNTS < <(managed_mounts)
(( ${#MOUNTS[@]} )) || { ok "Không có ổ nào do module này quản lý."; exit 0; }

log "Sẽ gỡ khỏi fstab:"
for mp in "${MOUNTS[@]}"; do
  printf "  %-40s %s\n" "$mp" "$(findmnt -no SOURCE "$mp" 2>/dev/null || echo '(chưa mount)')"
done
dim "Dữ liệu trên ổ được giữ nguyên, chỉ bỏ phần tự mount."
confirm "Tiếp tục?" || die "Đã huỷ."

need_sudo

# --- umount --------------------------------------------------------------------
for mp in "${MOUNTS[@]}"; do
  findmnt "$mp" >/dev/null 2>&1 || continue
  if sudo umount "$mp" 2>/dev/null; then
    ok "umount $mp"
  else
    # Đang có process giữ file trong đó (terminal đang cd vào, IDE mở project...).
    warn "Không umount được $mp — đang có tiến trình dùng:"
    sudo fuser -vm "$mp" 2>&1 | head -5 || true
    dim "  fstab vẫn được dọn; ổ sẽ không mount lại sau lần reboot tới."
  fi
done

# --- fstab ---------------------------------------------------------------------
tmp="$(mktemp)"
awk -v mark="$MARK" '
  $0 ~ "^"mark { skip = 1; next }      # bỏ dòng đánh dấu
  skip         { skip = 0; next }      # và bỏ luôn dòng mount ngay sau nó
  { print }
' "$FSTAB" >"$tmp"

bak="${FSTAB}.bak-$(ts)"
sudo cp -a "$FSTAB" "$bak"
dim "  backup: $bak"
sudo cp "$tmp" "$FSTAB"
rm -f "$tmp"

if sudo findmnt --verify -F "$FSTAB" >/dev/null 2>&1; then
  ok "Đã dọn /etc/fstab."
else
  warn "fstab sau khi sửa không hợp lệ — khôi phục backup."
  sudo cp "$(ls -1t ${FSTAB}.bak-* | head -1)" "$FSTAB"
  die "Đã hoàn tác."
fi
sudo systemctl daemon-reload

# --- bookmark + mount point ----------------------------------------------------
BM="$HOME/.config/gtk-3.0/bookmarks"
if [[ -f "$BM" ]]; then
  pgrep -x nautilus >/dev/null 2>&1 && { nautilus -q >/dev/null 2>&1 || true; sleep 1; }
  changed=0
  for mp in "${MOUNTS[@]}"; do
    uri="file://${mp// /%20}"
    grep -qE "^${uri}( |$)" "$BM" || continue
    [[ $changed == 0 ]] && backup_file "$BM"
    t="$(mktemp)"; grep -vE "^${uri}( |$)" "$BM" >"$t" || true; cat "$t" >"$BM"; rm -f "$t"
    changed=1
  done
  (( changed )) && ok "Đã bỏ khỏi sidebar của Files."
fi

# Chỉ xoá mount point khi nó RỖNG. Còn file nghĩa là ổ chưa umount được, hoặc có
# dữ liệu nằm thẳng trên ổ hệ thống ở đúng đường dẫn đó — cả hai đều không được xoá.
for mp in "${MOUNTS[@]}"; do
  [[ -d "$mp" ]] || continue
  findmnt "$mp" >/dev/null 2>&1 && continue
  if sudo rmdir "$mp" 2>/dev/null; then
    dim "  đã xoá thư mục rỗng: $mp"
  else
    dim "  giữ lại $mp (còn dữ liệu bên trong)"
  fi
done

cat <<'EOF'

Đã gỡ phần tự mount. Dữ liệu trên ổ CÒN NGUYÊN.
  • Mount tạm khi cần:  sudo mount /dev/sdXY /mnt
  • Gắn lại vĩnh viễn:  ./scripts/disks/install.sh
  • Ổ nào không umount được sẽ tự rời ra sau lần reboot tới.
EOF
