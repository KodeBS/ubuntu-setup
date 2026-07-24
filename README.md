# ubuntu-setup

Script cài đặt lại máy Ubuntu từ đầu. Mỗi thứ 1 script riêng, có script tổng `install.sh` để chạy hết hoặc chọn từng phần.

Viết cho **Ubuntu 26.04** (máy mới) nhưng chạy được luôn trên **24.04** (máy công ty hiện tại) — không hard-code codename, mọi thứ lấy từ `/etc/os-release`.

## Chạy trên máy mới cài Ubuntu

Ubuntu desktop mới cài chưa có sẵn `git`, nên bootstrap trước:

```bash
sudo apt update && sudo apt install -y git
git clone git@github.com:KodeBS/ubuntu-setup.git ~/ubuntu-setup
cd ~/ubuntu-setup/scripts
./install.sh --all
```

Không muốn cài git trước thì tải zip (nhớ `chmod +x` vì zip không giữ execute bit):

```bash
sudo apt update && sudo apt install -y curl unzip
curl -fsSL https://github.com/KodeBS/ubuntu-setup/archive/refs/heads/main.zip -o /tmp/s.zip
unzip -q /tmp/s.zip -d ~ && cd ~/ubuntu-setup-main/scripts
chmod +x install.sh *.sh && ./install.sh --all
```

Repo private mà chưa có SSH key trên máy mới → copy folder qua USB, hoặc `scp -r ~/ubuntu-setup user@may-moi:~/`.

## Dùng nhanh

```bash
cd ~/ubuntu-setup/scripts

./install.sh              # menu chọn module
./install.sh --all        # chạy hết theo thứ tự
./install.sh zsh docker   # chỉ chạy module chỉ định
./install.sh --list       # xem danh sách module
```

Từng script chạy độc lập được: `./scripts/docker.sh`, `./scripts/nvm-node.sh`, ...

Script an toàn khi chạy lại nhiều lần (idempotent): cái gì đã có thì báo `[ok]` và bỏ qua, không cài đè.

## Modules

| Script | Nội dung | Nguồn |
|---|---|---|
| `base.sh` | build-essential, curl, git, jq, ripgrep, fd, tree, wl-clipboard | apt |
| `zsh.sh` | zsh + Oh My Zsh + autosuggestions/syntax-highlighting/completions + Powerlevel10k, **font JetBrainsMono Nerd Font Mono + set font terminal + áp sẵn `.p10k.zsh`**, đặt shell mặc định | [ohmyzsh](https://github.com/ohmyzsh/ohmyzsh#basic-installation), [p10k](https://github.com/romkatv/powerlevel10k) |
| `vietnamese-input.sh` | Bộ gõ tiếng Việt: **ibus-bamboo** (mặc định) hoặc ibus-unikey | [BambooEngine](https://github.com/BambooEngine/ibus-bamboo) |
| `nvm-node.sh` | nvm + Node.js (**menu chọn version**, gợi ý 22 LTS) + yarn/pnpm | [nodejs.org/en/download](https://nodejs.org/en/download), [nvm](https://github.com/nvm-sh/nvm) |
| `docker.sh` | Docker Engine, CLI, Buildx, Compose plugin; thêm user vào group `docker` | [docs.docker.com](https://docs.docker.com/engine/install/ubuntu/), [DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-22-04) |
| `git.sh` | user.name/email, alias, SSH key ed25519, GitHub CLI | [git-scm](https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup) |
| `apps.sh` | VS Code, Google Chrome, Postman | [code.visualstudio.com](https://code.visualstudio.com/docs/setup/linux) |
| `clipboard.sh` | **CopyQ** clipboard manager + autostart + phím tắt `Super+V` | [CopyQ](https://github.com/hluk/CopyQ) |

## Chạy không cần trả lời câu hỏi

Mọi chỗ hỏi đều có env var để bỏ qua — tiện khi cài máy mới một phát ăn ngay:

```bash
NODE_VERSION=22 \
VN_INPUT_ENGINE=bamboo \
APPS=vscode,chrome \
GIT_NAME="Your Name" GIT_EMAIL="you@example.com" \
./install.sh --all
```

| Env var | Giá trị | Script |
|---|---|---|
| `NODE_VERSION` | `22`, `24`, `lts/*`, `18.20.4`... | nvm-node |
| `NVM_VERSION` | tag nvm, mặc định `v0.40.3` | nvm-node |
| `VN_INPUT_ENGINE` | `bamboo` \| `unikey` | vietnamese-input |
| `VN_INPUT_PPA_CODENAME` | fallback nếu PPA chưa hỗ trợ codename mới, vd `noble` | vietnamese-input |
| `DOCKER_CODENAME` | fallback nếu Docker chưa publish repo cho codename mới | docker |
| `APPS` | `vscode,chrome,postman` | apps |
| `GIT_NAME` / `GIT_EMAIL` | định danh commit; bỏ trống thì script hỏi | git |
| `TERMINAL_FONT` | mặc định `JetBrainsMono Nerd Font Mono 11` (MesloLGS NF thiếu ký tự tiếng Việt) | zsh |
| `CLIPBOARD_SHORTCUT` | mặc định `<Super>v` | clipboard |
| `CLIPBOARD_COMMAND` | `copyq menu` (mặc định) \| `copyq toggle` | clipboard |

## Sau khi cài

- Group `docker`: `newgrp docker` (hoặc `su - $USER`) là dùng được ngay **trong terminal đó**. Các terminal/app đang mở sẵn và app mở từ GUI thì phải logout/reboot mới nhận.
- **Logout/reboot** để áp dụng: zsh mặc định, ibus engine, và group `docker` cho toàn bộ session.
- Settings → Keyboard → Input Sources → thêm Vietnamese (Bamboo/Unikey), đổi bằng `Super+Space`.
- Powerlevel10k: font `JetBrainsMono Nerd Font Mono` và `~/.p10k.zsh` (rainbow, many icons, nerdfont-v3) được cài
  và set sẵn, **không cần chạy `p10k configure`**. Config cũ nếu có sẽ backup ra `~/.p10k.zsh.bak`.
  Terminal đã mở sẵn phải mở cửa sổ mới mới thấy font mới.
- `gh auth login` nếu đã cài GitHub CLI.
- Clipboard: `Super+V` mở lịch sử CopyQ (ăn sau khi logout/reboot). GNOME mặc định
  chiếm `Super+V` cho notification tray — script tự gỡ, tray vẫn mở được bằng `Super+M`.

## Ghi chú khi lên 26.04

Repo bên thứ ba đôi khi publish trễ vài tuần sau khi Ubuntu ra bản mới. Docker thì script tự kiểm tra repo, không có thì tự lùi về `noble`; PPA ibus-bamboo thì dùng `VN_INPUT_PPA_CODENAME=noble`. Ngoài hai chỗ đó không có gì phụ thuộc version cụ thể.
