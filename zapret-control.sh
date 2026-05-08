#!/bin/bash

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

source "$BASE_DIR/files/utils.sh"
source "$BASE_DIR/files/config.sh"
source "$BASE_DIR/files/init.sh"
source "$BASE_DIR/files/menu.sh"
source "$BASE_DIR/files/service.sh"
source "$BASE_DIR/files/install.sh"
source "$BASE_DIR/files/install_ctx.sh"
source "$BASE_DIR/files/state.sh"
source "$BASE_DIR/files/products.sh"
source "$BASE_DIR/files/service_ctx.sh"
source "$BASE_DIR/files/ux_gum.sh"
source "$BASE_DIR/files/flow_v2.sh"
source "$BASE_DIR/files/tui.sh"
source "$BASE_DIR/files/tui_flow.sh"

set -e  

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo > /dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas > /dev/null 2>&1; then
        SUDO="doas"
    else
        echo "Скрипт не может быть выполнен не от имени суперпользователя."
        exit 1
    fi
fi

if [[ $EUID -ne 0 ]]; then
    exec $SUDO "$0" "$@"
fi
trap fast_exit SIGINT
check_openwrt
check_tput
$TPUT_B
check_fs
detect_init
remote_latest_version

# Новый интерактивный flow с gum (fallback: старое меню).
if main_menu_tui; then
    :
elif main_menu_gum; then
    :
else
    main_menu
fi
