#!/bin/bash

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

source "$BASE_DIR/files/utils.sh"
source "$BASE_DIR/files/init.sh"
source "$BASE_DIR/files/gum_utils.sh"
source "$BASE_DIR/files/ux_gum.sh"
source "$BASE_DIR/files/snow.sh"
source "$BASE_DIR/files/service.sh"
source "$BASE_DIR/files/install.sh"
source "$BASE_DIR/files/install_ctx.sh"
source "$BASE_DIR/files/state.sh"
source "$BASE_DIR/files/products.sh"
source "$BASE_DIR/files/service_ctx.sh"
source "$BASE_DIR/files/flow_v2.sh"

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

check_sudo
trap fast_exit SIGINT

check_openwrt
check_tput && tput bold || true
check_fs
detect_init

main_menu_gum || true