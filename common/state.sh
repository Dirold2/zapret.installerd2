#!/bin/bash

STATE_DIR="/etc/zapret.installer"
STATE_FILE="$STATE_DIR/state.env"
BACKUP_ROOT="$STATE_DIR/backups"
LOG_DIR="$STATE_DIR/logs"
BACKUP_DIR="$BACKUP_ROOT"

state_mkdirs() {
    mkdir -p "$STATE_DIR" "$BACKUP_ROOT" "$LOG_DIR" || return 1
}

state_now_ts() {
    date +"%Y%m%d-%H%M%S"
}

state_load() {
    INSTALL_MODE=""
    ACTIVE_PRODUCT=""
    ACTIVE_PROFILE=""
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi
    [ -n "$INSTALL_MODE" ] || INSTALL_MODE="zapret"
    [ -n "$ACTIVE_PRODUCT" ] || ACTIVE_PRODUCT="$INSTALL_MODE"
    return 0
}

backup_begin() {
    state_mkdirs || return 1
    BACKUP_ID="$(state_now_ts)"
    BACKUP_DIR="$BACKUP_ROOT/$BACKUP_ID"
    mkdir -p "$BACKUP_DIR" || return 1
}

backup_path() {
    local p="$1"
    [ -e "$p" ] || return 0
    local dst="$BACKUP_DIR${p}"
    mkdir -p "$(dirname "$dst")" || return 1
    if [ -d "$p" ]; then
        cp -a "$p" "$dst" || return 1
    else
        cp -a "$p" "$dst" || return 1
    fi
}

