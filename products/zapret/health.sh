#!/bin/bash

check_product_update() {
    local name="$1"
    local ver_file="/opt/$name-ver"
    local remote_repo=""

    case "$name" in
        zapret)  remote_repo="bol-van/zapret"  ;;
        zapret2) remote_repo="bol-van/zapret2" ;;
        *) return 1 ;;
    esac

    local local_ver
    local_ver=$(cat "$ver_file" 2>/dev/null || echo "")

    [ -z "$local_ver" ] && { echo "not_installed"; return 0; }
    [ "$local_ver" = "git" ] && { echo "git"; return 0; }

    local remote_ver
    remote_ver=$(timeout 10 curl -s "https://api.github.com/repos/$remote_repo/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//' || echo "")

    [ -z "$remote_ver" ] && { echo "noconnect"; return 0; }
    [ "$local_ver" != "$remote_ver" ] && { echo "$remote_ver"; return 0; }
    echo "current"
}
