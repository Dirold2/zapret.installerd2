#!/bin/bash

detect_init() {
    GET_LIST_PREFIX=/ipset/get_

    SYSTEMD_DIR=/lib/systemd
    [ -d "$SYSTEMD_DIR" ] || SYSTEMD_DIR=/usr/lib/systemd
    [ -d "$SYSTEMD_DIR" ] && SYSTEMD_SYSTEM_DIR="$SYSTEMD_DIR/system"

    INIT_SCRIPT=/etc/init.d/zapret
    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ "${SYSTEM:-}" = "openwrt" ]; then
        INIT_SYSTEM="procd"
    elif command -v openrc >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    elif command -v runit >/dev/null 2>&1; then
        INIT_SYSTEM="runit"
        [ -f /etc/os-release ] && . /etc/os-release
        if [ "${ID:-}" = "artix" ]; then
            INIT_SYSTEM="runit-artix"
        fi
    elif [ -x /sbin/init ] && /sbin/init --version 2>&1 | grep -qi "sysv init"; then
        INIT_SYSTEM="sysvinit"
    else
        error_exit "Не удалось определить init."
    fi
}
