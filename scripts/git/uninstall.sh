#!/usr/bin/env bash
# Gỡ GitHub CLI + repo apt của nó, và hoàn tác các git config do git.sh đặt.
#
# BA THỨ KHÔNG BAO GIỜ ĐỤNG TỚI, kể cả với --purge:
#   1. ~/.ssh/id_ed25519 — mất key là mất quyền truy cập mọi repo/server đã khai
#      báo public key; không tạo lại được cùng fingerprint.
#   2. git user.name / user.email — định danh commit, không phải thứ script cài.
#   3. gói `git` — nửa hệ thống và chính repo này phụ thuộc vào nó.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

# --- 1. GitHub CLI ---------------------------------------------------------------
remove_gh() {
  if ! pkg_installed gh && ! has gh; then
    dim "Chưa cài gh."
  else
    # Đăng xuất trước khi gỡ: xoá token khỏi keyring/config đúng cách, thay vì
    # để lại token mồ côi trong ~/.config/gh.
    if has gh && gh auth status >/dev/null 2>&1; then
      if confirm "Đăng xuất gh (thu hồi token đang lưu trên máy)?"; then
        gh auth logout --hostname github.com >/dev/null 2>&1 \
          && ok "Đã đăng xuất gh." \
          || warn "gh auth logout lỗi, bỏ qua."
      fi
    fi
    apt_remove gh
  fi
  safe_rm /etc/apt/sources.list.d/github-cli.list \
          /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && ok "Đã gỡ repo apt của GitHub CLI." \
    || warn "Không dọn sạch được repo apt của GitHub CLI."
}

# --- 2. git config do script tạo -------------------------------------------------
# Chỉ unset khi giá trị y hệt cái git.sh đặt. Bệ Hạ tự đổi giá trị nào thì giữ
# nguyên giá trị đó.
reset_git_config() {
  log "Hoàn tác git config do script đặt (giữ user.name/user.email)"
  git_unset_if alias.st "status"
  git_unset_if alias.co "checkout"
  git_unset_if alias.br "branch"
  git_unset_if alias.lg "log --oneline --graph --decorate --all"
  git_unset_if init.defaultBranch "main"
  git_unset_if pull.rebase "true"
  git_unset_if core.editor "${EDITOR:-nano}"
  ok "Xong git config."

  local name email
  name="$(git config --global --get user.name  2>/dev/null || true)"
  email="$(git config --global --get user.email 2>/dev/null || true)"
  [[ -n "$name$email" ]] && dim "Giữ nguyên định danh: ${name:-?} <${email:-?}>"
  return 0
}

remove_gh
reset_git_config

# --- 3. những thứ cố tình không gỡ ------------------------------------------------
echo
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  warn "SSH key ~/.ssh/id_ed25519 được GIỮ NGUYÊN — script không bao giờ xoá key."
  dim  "Muốn bỏ thật thì tự xoá, và nhớ gỡ public key khỏi GitHub/GitLab trước."
fi
if purging && [[ -d "$HOME/.config/gh" ]]; then
  warn "~/.config/gh vẫn còn (có thể chứa token). Xoá tay nếu cần: rm -rf ~/.config/gh"
fi
warn 'Gói "git" được giữ lại (hệ thống và repo này cần nó).'

ok "Xong phần git."
