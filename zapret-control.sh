#!/bin/bash

BASE_DIR="$(dirname "$(readlink -f "$0")")"

# Load state first (for ACTIVE_PRODUCT)
source "$BASE_DIR/common/state.sh"

# Determine active product (from state or first argument)
PRODUCT_ID="${1:-${ACTIVE_PRODUCT:-zapret}}"

# Validate product exists
if [ ! -d "$BASE_DIR/products/$PRODUCT_ID" ] || [ ! -f "$BASE_DIR/products/$PRODUCT_ID/product.env" ]; then
    echo "Unknown product: $PRODUCT_ID"
    echo "Available products:"
    for d in "$BASE_DIR"/products/*/; do
        [ -f "$d/product.env" ] && echo "  - $(basename "$d")"
    done
    exit 1
fi

# Load common modules
source "$BASE_DIR/common/utils.sh"
source "$BASE_DIR/common/init_common.sh"
source "$BASE_DIR/common/gum_utils.sh"
source "$BASE_DIR/common/ux_gum.sh"
source "$BASE_DIR/common/snow.sh"
source "$BASE_DIR/common/service_common.sh"
source "$BASE_DIR/common/update.sh"

# Load product-specific modules
source "$BASE_DIR/products/$PRODUCT_ID/product.env"
source "$BASE_DIR/products/$PRODUCT_ID/init.sh"
source "$BASE_DIR/products/$PRODUCT_ID/health.sh"
source "$BASE_DIR/products/$PRODUCT_ID/install.sh"
source "$BASE_DIR/products/$PRODUCT_ID/uninstall.sh"

# Load UI
source "$BASE_DIR/common/flow_v2.sh"

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
