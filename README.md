# ubuntu-setup

Script cài đặt lại máy Ubuntu từ đầu. Mỗi tính năng một thư mục (1 file cài + 1 file gỡ), có 2 script tổng `install.sh` / `uninstall.sh` để chạy hết hoặc chọn từng phần.

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
find . -name '*.sh' -exec chmod +x {} + && ./install.sh --all
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

Từng module chạy độc lập được: `./scripts/docker/install.sh`, `./scripts/nvm-node/install.sh`, ...

Script an toàn khi chạy lại nhiều lần (idempotent): cái gì đã có thì báo `[ok]` và bỏ qua, không cài đè.

## Cấu trúc

Mỗi tính năng là **một thư mục**, trong đó có đúng một file cài và một file gỡ. Thêm tính năng mới = tạo thư mục + 2 file + thêm tên vào mảng `MODULES` của 2 dispatcher.

```
scripts/
├── install.sh            # dispatcher cài
├── uninstall.sh          # dispatcher gỡ
├── lib/common.sh         # log, apt_install, apt_remove, safe_rm, backup_file...
├── base/        install.sh  uninstall.sh
├── zsh/         install.sh  uninstall.sh  p10k.zsh
├── vietnamese-input/  install.sh  uninstall.sh
├── nvm-node/    install.sh  uninstall.sh
├── docker/      install.sh  uninstall.sh
├── git/         install.sh  uninstall.sh
├── apps/        install.sh  uninstall.sh
├── clipboard/   install.sh  uninstall.sh
└── disks/       install.sh  uninstall.sh
```

## Gỡ cài đặt

```bash
cd ~/ubuntu-setup/scripts

./uninstall.sh              # menu chọn module
./uninstall.sh --all        # gỡ hết, ngược thứ tự lúc cài
./uninstall.sh docker zsh   # chỉ gỡ module chỉ định
./uninstall.sh --list       # xem danh sách
```

Từng module chạy riêng được: `./scripts/docker/uninstall.sh`, ...

**Mặc định là chế độ an toàn**: chỉ gỡ package và hoàn tác đúng những cấu hình mà script cài đặt đã tạo. Dữ liệu cá nhân giữ nguyên. Mọi file config bị sửa đều được backup ra `<file>.bak-<ngày giờ>` cạnh bản gốc.

| Cờ | Tác dụng |
|---|---|
| `--purge` | Gỡ luôn dữ liệu: `/var/lib/docker` (image + **volume**), `~/.nvm`, profile Chrome & VS Code, lịch sử clipboard, `~/.zshrc`. Mỗi thứ không khôi phục được đều hỏi xác nhận riêng (phải gõ `yes`). |
| `--yes` | Không hỏi gì, dùng khi chạy tự động. Đi kèm `--purge` là xoá thẳng, không hỏi lại. |

### Không bao giờ bị đụng tới — kể cả với `--purge`

| Thứ | Vì sao |
|---|---|
| `~/.ssh/id_ed25519` (+ `.pub`) | Mất key là mất quyền truy cập mọi repo/server đã khai báo public key, không tạo lại được cùng fingerprint |
| `git user.name` / `user.email` | Định danh commit, không phải thứ script cài |
| Gói `git`, `curl`, `ca-certificates`, `gnupg`, `build-essential`, `software-properties-common`, `tar`, `unzip`, `wget`, `openssh-client` | `apt`/`ubuntu-desktop` phụ thuộc trực tiếp — gỡ là hỏng apt hoặc mất session đồ hoạ |
| Gói `ibus` | GNOME cần nó để gõ mọi ngôn ngữ, không riêng tiếng Việt |
| `~/.zshenv` | Script không tạo file này; nó thường chứa env riêng của máy |
| Dữ liệu trên ổ phụ (`disks`) | `uninstall` chỉ bỏ phần tự mount. Format là thao tác riêng, phải chủ động chạy `DISK_FORMAT=force` và gõ `yes` |
| Plugin/theme lạ trong `~/.oh-my-zsh/custom` | Có thứ không do script clone về thì giữ nguyên cả `~/.oh-my-zsh`, chỉ xoá đúng 4 repo script đã cài |

Ngoài ra `git/uninstall.sh` chỉ `git config --unset` khi giá trị **đúng bằng** cái `git/install.sh` đã đặt — tự đổi `pull.rebase` hay alias nào thì giá trị đó được giữ.

### Thứ tự gỡ

Ngược với lúc cài, và trong module `zsh` thì **đổi shell mặc định về bash trước rồi mới `apt remove zsh`** — làm ngược lại thì login shell trỏ tới binary đã bị xoá, lần login sau không vào được session.

| Module | Gỡ gì | Giữ gì (mặc định) |
|---|---|---|
| `disks` | Dòng fstab + bookmark sidebar, umount ổ | **Toàn bộ dữ liệu trên ổ** — không bao giờ format, kể cả `--purge` |
| `clipboard` | Extension Clipboard Indicator, trả `Super+V` về message tray | Lịch sử clip trong `~/.cache/` |
| `apps` | VS Code, Chrome, Postman + repo apt & keyring | `~/.config/Code`, `~/.config/google-chrome`, snapshot snap |
| `git` | GitHub CLI + repo apt, alias git do script tạo | SSH key, `user.name`/`user.email`, gói `git` |
| `docker` | Engine/CLI/Compose, repo apt, gỡ user khỏi group `docker` | `/var/lib/docker` — image & volume còn nguyên |
| `nvm-node` | `~/.nvm` + mọi bản Node, snippet trong `.bashrc`/`.zshrc` | `~/.npmrc`, cache npm/yarn/pnpm |
| `vietnamese-input` | `ibus-bamboo`/`ibus-unikey` + PPA + input source trong GNOME | Gói `ibus` |
| `zsh` | Oh My Zsh, Powerlevel10k, Nerd Font, gói `zsh`; shell về bash | `~/.zshrc` (chỉ gỡ dòng script thêm vào), `~/.zshenv` |
| `base` | `jq`, `tree`, `ripgrep`, `fd-find`, `zip`, `wl-clipboard` | Toàn bộ gói hệ thống ở bảng trên |

Sau khi gỡ: **logout/reboot** để áp dụng shell bash, bỏ group `docker`, và để GNOME Shell nạp lại không có extension.

## Modules

| Module | Nội dung | Nguồn |
|---|---|---|
| `base/` | build-essential, curl, git, jq, ripgrep, fd, tree, wl-clipboard | apt |
| `zsh/` | zsh + Oh My Zsh + autosuggestions/syntax-highlighting/completions + Powerlevel10k, **font JetBrainsMono Nerd Font Mono + set font terminal + áp sẵn `.p10k.zsh`**, đặt shell mặc định | [ohmyzsh](https://github.com/ohmyzsh/ohmyzsh#basic-installation), [p10k](https://github.com/romkatv/powerlevel10k) |
| `vietnamese-input/` | Bộ gõ tiếng Việt: **ibus-bamboo** (mặc định) hoặc ibus-unikey | [BambooEngine](https://github.com/BambooEngine/ibus-bamboo) |
| `nvm-node/` | nvm + Node.js (**menu chọn version**, gợi ý 22 LTS) + yarn/pnpm | [nodejs.org/en/download](https://nodejs.org/en/download), [nvm](https://github.com/nvm-sh/nvm) |
| `docker/` | Docker Engine, CLI, Buildx, Compose plugin; thêm user vào group `docker` | [docs.docker.com](https://docs.docker.com/engine/install/ubuntu/), [DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-22-04) |
| `git/` | user.name/email, alias, SSH key ed25519, GitHub CLI | [git-scm](https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup) |
| `apps/` | VS Code, Google Chrome, Postman | [code.visualstudio.com](https://code.visualstudio.com/docs/setup/linux) |
| `clipboard/` | **Clipboard Indicator** (GNOME extension) + phím tắt `Super+V` | [Clipboard Indicator](https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator) |
| `disks/` | Gắn ổ cứng phụ (ổ chứa code/data) vào `/etc/fstab` **theo UUID** — tự mount mỗi lần boot, thêm vào sidebar của Files | [fstab(5)](https://man7.org/linux/man-pages/man5/fstab.5.html) |

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
| `CLIPBOARD_PASTE_ON_SELECT` | `true` (mặc định) \| `false` — chọn item xong dán luôn | clipboard |
| `CLIPBOARD_OPEN_AT_CURSOR` | `true` (mặc định) \| `false` — popup cạnh con trỏ thay vì thả từ panel | clipboard |
| `CLIPBOARD_EXT_UUID` | đổi sang extension khác, vd `clipboard-history@alexsaveau.dev` | clipboard |
| `DISKS` | `"/dev/sdb=Data;/dev/sdc=Media"` — bỏ trống thì hiện menu chọn ổ | disks |
| `DISK_FORMAT` | `never` (mặc định, chỉ mount ổ đã có filesystem) \| `empty` (format nếu ổ chưa có fs) \| `force` (format lại, hỏi gõ `yes`) | disks |
| `DISK_FS` | `ext4` (mặc định) \| `xfs` — chỉ dùng khi format | disks |
| `DISK_MOUNT_BASE` | mặc định `$HOME` → mount point là `$HOME/<Tên>` | disks |
| `DISK_BOOKMARK` | `true` (mặc định) — thêm vào sidebar của Files | disks |
| `DISK_REMOVE_LOST_FOUND` | `true` (mặc định) — xoá `lost+found` sau khi format | disks |

## Sau khi cài

- Group `docker`: `newgrp docker` (hoặc `su - $USER`) là dùng được ngay **trong terminal đó**. Các terminal/app đang mở sẵn và app mở từ GUI thì phải logout/reboot mới nhận.
- **Logout/reboot** để áp dụng: zsh mặc định, ibus engine, và group `docker` cho toàn bộ session.
- Bộ gõ tiếng Việt: script **tự thêm** engine vào Input Sources của GNOME (`org.gnome.desktop.input-sources sources`),
  **không cần** vào Settings → Keyboard bấm `+`. Chuyển bộ gõ bằng `Super+Space` (`Shift+Super+Space` để lùi).
  Engine được chèn **sau** layout `us` để lúc mới login vẫn đang ở chế độ tiếng Anh.
  Kiểm tra: `gsettings get org.gnome.desktop.input-sources sources` → phải thấy `('ibus', 'Bamboo')` hoặc `('ibus', 'Unikey')`.
- Powerlevel10k: font `JetBrainsMono Nerd Font Mono` và `~/.p10k.zsh` (rainbow, many icons, nerdfont-v3) được cài
  và set sẵn, **không cần chạy `p10k configure`**. Config cũ nếu có sẽ backup ra `~/.p10k.zsh.bak`.
  Terminal đã mở sẵn phải mở cửa sổ mới mới thấy font mới.
- `gh auth login` nếu đã cài GitHub CLI.
- Ổ phụ (`disks`): ghi vào fstab **theo UUID** chứ không phải `/dev/sdb1`, vì tên thiết bị do kernel
  cấp theo thứ tự phát hiện — cắm thêm ổ hoặc đổi khe M.2 là `nvme0n1` ↔ `nvme1n1` hoán vị nhau ngay,
  còn UUID nằm trong superblock nên không đổi. Có `nofail` để ổ hỏng/tháo ra máy vẫn boot bình thường
  thay vì rơi vào emergency shell. Kiểm tra: `findmnt --verify` và `lsblk -o NAME,LABEL,SIZE,MOUNTPOINT`.
  - Mục trong sidebar là **bookmark** (icon thư mục), không phải mục thiết bị có nút eject — mount
    option `x-gvfs-hide` giấu mục thiết bị đi để khỏi vừa trùng vừa dễ bấm nhầm eject. Chữ hiện trong
    mục thiết bị/Disks là **label của filesystem**, script đặt label trùng tên thư mục.
  - Nautilus giữ bookmarks trong bộ nhớ và ghi đè file khi thoát, nên script **tắt Nautilus** (`nautilus -q`)
    trước khi sửa `~/.config/gtk-3.0/bookmarks` — sửa lúc nó đang chạy là mất trắng.
- Clipboard: `Super+V` mở lịch sử Clipboard Indicator. **Bắt buộc logout/reboot** — Wayland
  không cho reload GNOME Shell tại chỗ nên extension chỉ nạp khi shell khởi động lại.
  GNOME mặc định chiếm `Super+V` cho notification tray — script tự gỡ, tray vẫn mở
  được bằng `Super+M`. Kiểm tra: `gnome-extensions info clipboard-indicator@tudmotu.com`
  (State phải là `ACTIVE`).
  - Dùng extension chứ không dùng app standalone vì Mutter **không** hỗ trợ
    `wlr-data-control`/`ext-data-control` ([mutter#524](https://gitlab.gnome.org/GNOME/mutter/-/work_items/524)),
    nên `cliphist`, `clipse`, `greenclip`... đều mù trên GNOME; app Qt/GTK standalone
    chỉ đọc được clipboard khi ép qua XWayland (`QT_QPA_PLATFORM=xcb`), đổi lại UI mờ
    và lạc lõng. Kiểm chứng: `wl-paste --watch echo x` → báo thiếu data-control protocol.

## Ghi chú khi lên 26.04

Repo bên thứ ba đôi khi publish trễ vài tuần sau khi Ubuntu ra bản mới. Docker thì script tự kiểm tra repo, không có thì tự lùi về `noble`; PPA ibus-bamboo thì dùng `VN_INPUT_PPA_CODENAME=noble`. Ngoài hai chỗ đó không có gì phụ thuộc version cụ thể.
