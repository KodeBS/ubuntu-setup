#!/usr/bin/env bash
# Gỡ VS Code, Google Chrome, Postman + repo apt của chúng.
#
# MẶC ĐỊNH GIỮ profile người dùng: ~/.config/Code (settings, extension, workspace)
# và ~/.config/google-chrome (bookmark, mật khẩu đã lưu, session đăng nhập). Gỡ
# gói không đụng tới chúng, cài lại là mọi thứ trở về như cũ. Chỉ --purge mới xoá,
# và phải gõ 'yes' cho từng cái.
#
# Chọn app: APPS=vscode,chrome ./apps/uninstall.sh   (bỏ trống thì script hỏi,
# chỉ hỏi những app thực sự đang có trên máy).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

require_ubuntu
need_sudo

vscode_present() { pkg_installed code || has code; }
chrome_present() { pkg_installed google-chrome-stable || has google-chrome-stable || has google-chrome; }
postman_present() { has snap && snap list postman >/dev/null 2>&1; }

uninstall_vscode() {
  apt_remove code
  # Repo Microsoft cũng phục vụ các sản phẩm khác; chỉ xoá đúng file vscode.list
  # và keyring do apps.sh tạo.
  safe_rm /etc/apt/sources.list.d/vscode.list /etc/apt/keyrings/packages.microsoft.gpg \
    && ok "Đã gỡ VS Code + repo Microsoft." \
    || warn "Không dọn sạch được repo Microsoft."

  if purging; then
    if confirm_danger "Sắp xoá ~/.config/Code và ~/.vscode — mất hết settings, extension, danh sách workspace."; then
      safe_rm "$HOME/.config/Code" "$HOME/.vscode" "$HOME/.cache/vscode-cpptools" \
        && ok "Đã xoá dữ liệu VS Code." || warn "Còn sót dữ liệu VS Code."
    else
      dim "Giữ profile VS Code."
    fi
  else
    dim "Giữ ~/.config/Code và ~/.vscode."
  fi
}

uninstall_chrome() {
  apt_remove google-chrome-stable
  # File repo này do postinst của gói .deb tự tạo, apt remove không dọn.
  safe_rm /etc/apt/sources.list.d/google-chrome.list \
          /etc/apt/trusted.gpg.d/google-chrome.gpg \
          /etc/apt/keyrings/google-chrome.gpg \
    && ok "Đã gỡ Google Chrome + repo Google." \
    || warn "Không dọn sạch được repo Google."

  if purging; then
    if confirm_danger "Sắp xoá ~/.config/google-chrome — mất bookmark, mật khẩu đã lưu, mọi phiên đăng nhập."; then
      safe_rm "$HOME/.config/google-chrome" "$HOME/.cache/google-chrome" \
        && ok "Đã xoá profile Chrome." || warn "Còn sót profile Chrome."
    else
      dim "Giữ profile Chrome."
    fi
  else
    dim "Giữ ~/.config/google-chrome."
  fi
}

uninstall_postman() {
  has snap || { dim "Không có snapd."; return 0; }
  # `snap remove` giữ lại snapshot dữ liệu (khôi phục bằng `snap restore`);
  # `--purge` bỏ luôn snapshot.
  if purging; then
    sudo snap remove --purge postman && ok "Đã gỡ Postman (xoá cả snapshot)."
  else
    sudo snap remove postman && ok "Đã gỡ Postman (snapshot dữ liệu vẫn giữ: snap saved)."
  fi
}

# --- chọn app --------------------------------------------------------------------
APPS="${APPS:-}"
if [[ -z "$APPS" ]]; then
  vscode_present  && confirm "Gỡ VS Code?"        && APPS+="vscode,"
  chrome_present  && confirm "Gỡ Google Chrome?"  && APPS+="chrome,"
  postman_present && confirm "Gỡ Postman (snap)?" && APPS+="postman,"
fi

if [[ -z "$APPS" ]]; then
  dim "Không có app nào được chọn (hoặc máy chưa cài app nào trong nhóm này)."
  exit 0
fi

IFS=',' read -ra list <<<"$APPS"
for app in "${list[@]}"; do
  case "$app" in
    vscode)  uninstall_vscode ;;
    chrome)  uninstall_chrome ;;
    postman) uninstall_postman ;;
    "")      ;;
    *)       warn "App không rõ: $app" ;;
  esac
done

dim "JetBrains Toolbox / DataGrip không do script này quản, gỡ tay nếu cần."
ok "Xong phần apps."
