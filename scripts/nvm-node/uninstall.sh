#!/usr/bin/env bash
# Gỡ nvm + toàn bộ Node.js đã cài qua nvm + snippet nvm trong .bashrc/.zshrc.
#
# nvm cài trọn gói trong $NVM_DIR (mặc định ~/.nvm), kể cả mọi bản Node và mọi
# package cài -g. Xoá thư mục đó là sạch — không cần `npm uninstall -g` từng cái.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# --- 1. thư mục nvm --------------------------------------------------------------
if [[ -d "$NVM_DIR" ]]; then
  versions="$(ls -1 "$NVM_DIR/versions/node" 2>/dev/null | tr '\n' ' ' || true)"
  [[ -n "$versions" ]] && dim "Node sẽ bị xoá theo: $versions"
  safe_rm "$NVM_DIR" \
    && ok "Đã xoá nvm và mọi bản Node trong đó ($NVM_DIR)" \
    || err "KHÔNG xoá được $NVM_DIR — nvm vẫn còn nguyên trên máy."
else
  dim "Không có $NVM_DIR."
fi

# --- 2. snippet trong rc file ----------------------------------------------------
# nvm-node.sh ghi đúng khối 4 dòng: comment "# nvm" + export NVM_DIR + 2 dòng source.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  strip_lines "$rc" '(^# nvm$|NVM_DIR|nvm\.sh|\$NVM_DIR/bash_completion)'
done

# --- 3. cảnh báo Node cài bằng apt ------------------------------------------------
# Không phải do script này cài, nhưng nếu còn thì `node -v` vẫn chạy được và dễ
# tưởng là gỡ hụt.
if pkg_installed nodejs; then
  warn "Còn gói apt 'nodejs' (không do script này cài). Gỡ tay nếu muốn:"
  dim  "    sudo apt remove nodejs npm"
fi

# --- 4. cache & config của npm/yarn/pnpm (chỉ khi --purge) ----------------------
if purging; then
  # ~/.npmrc có thể chứa token registry -> backup trước rồi mới xoá.
  if [[ -f "$HOME/.npmrc" ]]; then
    if confirm_danger "~/.npmrc có thể chứa token registry riêng. Xoá?"; then
      backup_file "$HOME/.npmrc"
      safe_rm "$HOME/.npmrc" || warn "Không xoá được ~/.npmrc."
    else
      dim "Giữ ~/.npmrc."
    fi
  fi
  safe_rm "$HOME/.npm" "$HOME/.cache/yarn" "$HOME/.yarn" \
          "$HOME/.local/share/pnpm" "$HOME/.cache/pnpm" "$HOME/.config/pnpm" \
          "$HOME/.node_repl_history" \
    && ok "Đã xoá cache npm/yarn/pnpm." \
    || warn "Còn sót cache npm/yarn/pnpm (xem cảnh báo ở trên)."
fi

ok "Xong phần nvm/Node. Mở terminal mới để shell quên PATH cũ."
