#!/bin/sh
set -e

REPO_URL="https://github.com/Dirold2/zapret.installerd2"
INSTALL_DIR="/opt/zapret.installer"
BIN_LINK="/usr/local/bin/zapret"

install_dependencies() {
    kernel="$(uname -s)"

    [ -f /etc/os-release ] && . /etc/os-release || {
        echo "Не удалось определить ОС"
        exit 1
    }

    SUDO="${SUDO:-}"

    case "$ID" in
        arch|manjaro|endeavouros|garuda|cachyos|artix)
            $SUDO pacman -Sy --noconfirm git
            ;;
        debian|ubuntu|mint)
            $SUDO apt update -y && $SUDO apt install -y git
            ;;
        fedora|rhel|centos|rocky|almalinux|oracle|redos)
            if command -v dnf >/dev/null 2>&1; then
                $SUDO dnf install -y git
            else
                $SUDO yum install -y git
            fi
            ;;
        alpine)
            $SUDO apk add git
            ;;
        openwrt)
            $SUDO opkg update && $SUDO opkg install git git-http
            ;;
        *)
            echo "Установите git вручную"
            exit 1
            ;;
    esac
}

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    else
        echo "Нужен root/sudo/doas"
        exit 1
    fi
}

install_git_if_needed() {
    command -v git >/dev/null 2>&1 || install_dependencies
}

clone_or_update() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo "[INFO] update repo"
        cd "$INSTALL_DIR"
        $SUDO git pull --rebase || {
            echo "[WARN] reset repo"
            cd /
            $SUDO rm -rf "$INSTALL_DIR"
            $SUDO git clone "$REPO_URL" "$INSTALL_DIR"
        }
    else
        echo "[INFO] clone repo"
        $SUDO rm -rf "$INSTALL_DIR"
        $SUDO git clone "$REPO_URL" "$INSTALL_DIR"
    fi
}

create_link() {
    echo "[INFO] creating command: zapret"

    $SUDO rm -f "$BIN_LINK"

    $SUDO ln -s "$INSTALL_DIR/zapret-control.sh" "$BIN_LINK"

    $SUDO chmod +x "$INSTALL_DIR/zapret-control.sh"
    $SUDO chmod +x "$BIN_LINK"
}

main() {
    need_sudo

    echo "[INFO] checking git"
    install_git_if_needed

    echo "[INFO] installing to $INSTALL_DIR"

    clone_or_update

    create_link

    echo ""
    echo "[OK] installed successfully"
    echo "[INFO] run: zapret"
}

main "$@"