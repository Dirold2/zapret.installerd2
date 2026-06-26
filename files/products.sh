#!/bin/bash

# Product context variables (set by product_use)
PRODUCT_ID=""
PRODUCT_REPO=""
PRODUCT_DIR=""
PRODUCT_SERVICE=""
PRODUCT_BINLINK=""
PRODUCT_VER_FILE=""
PRODUCT_CFGS_REPO=""
PRODUCT_CFGS_DIR=""
PRODUCT_CFGS_CONFIG_DIR=""
PRODUCT_CFGS_LIST_DIR=""
PRODUCT_CONFIG_FILE=""
PRODUCT_LIST_FILE=""
PRODUCT_EXCLUDE_FILE=""
PRODUCT_GAME_IPSET_FILE=""

product_use() {
    case "$1" in
        zapret)
            PRODUCT_ID="zapret"
            PRODUCT_REPO="bol-van/zapret"
            PRODUCT_DIR="/opt/zapret"
            PRODUCT_SERVICE="zapret"
            PRODUCT_BINLINK="/bin/zapret"
            PRODUCT_VER_FILE="/opt/zapret-ver"
            PRODUCT_CFGS_REPO="https://github.com/Snowy-Fluffy/zapret.cfgs"
            PRODUCT_CFGS_DIR="/opt/zapret/zapret.cfgs"
            PRODUCT_CFGS_CONFIG_DIR="$PRODUCT_CFGS_DIR/configurations"
            PRODUCT_CFGS_LIST_DIR="$PRODUCT_CFGS_DIR/lists"
            PRODUCT_CONFIG_FILE="/opt/zapret/config"
            PRODUCT_LIST_FILE="/opt/zapret/ipset/zapret-hosts-user.txt"
            PRODUCT_EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
            PRODUCT_GAME_IPSET_FILE="/opt/zapret/ipset/ipset-game.txt"
            ;;
        zapret2)
            PRODUCT_ID="zapret2"
            PRODUCT_REPO="bol-van/zapret2"
            PRODUCT_DIR="/opt/zapret2"
            PRODUCT_SERVICE="zapret2"
            PRODUCT_BINLINK="/bin/zapret2"
            PRODUCT_VER_FILE="/opt/zapret2-ver"
            PRODUCT_CFGS_REPO="https://github.com/lastharbor/zapret2.cfgs"
            PRODUCT_CFGS_DIR="/opt/zapret2/zapret.cfgs"
            PRODUCT_CFGS_CONFIG_DIR="$PRODUCT_CFGS_DIR/presets"
            PRODUCT_CFGS_LIST_DIR=""
            PRODUCT_CONFIG_FILE="/opt/zapret2/config"
            PRODUCT_LIST_FILE="/opt/zapret2/ipset/zapret-hosts-user.txt"
            PRODUCT_EXCLUDE_FILE="/opt/zapret2/ipset/zapret-hosts-user-exclude.txt"
            PRODUCT_GAME_IPSET_FILE="/opt/zapret2/ipset/ipset-game.txt"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

get_product_file() {
    case "$1" in
        config) echo "$PRODUCT_CONFIG_FILE" ;;
        list)   echo "$PRODUCT_LIST_FILE" ;;
        exclude) echo "$PRODUCT_EXCLUDE_FILE" ;;
    esac
}

product_print_plan() {
    echo "Будет использовано:"
    echo "  - продукт: $PRODUCT_ID"
    echo "  - каталог: $PRODUCT_DIR"
    echo "  - сервис:  $PRODUCT_SERVICE"
    echo "  - конфиг:  $PRODUCT_CONFIG_FILE"
    echo "  - лист:    $PRODUCT_LIST_FILE"
    echo "  - бинарь:  $PRODUCT_BINLINK"
}

