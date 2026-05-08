#!/bin/bash

gh_api_latest_tarball_url() {
    # Prints first tar.gz download URL for repo, without openwrt special-casing.
    # Args: repo (e.g. bol-van/zapret)
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -E '"browser_download_url":' \
        | grep -E 'tar\.gz"' \
        | head -n 1 \
        | cut -d '"' -f 4
}

install_product_release() {
    local repo="$1"
    local dir="$2"
    local ver_file="$3"

    local tmp
    tmp="$(mktemp -d)" || return 1
    local url
    url="$(gh_api_latest_tarball_url "$repo")"
    if [ -z "$url" ]; then
        rm -rf "$tmp"
        return 1
    fi
    curl -fL -o "$tmp/latest.tar.gz" "$url" || { rm -rf "$tmp"; return 1; }

    rm -rf "$dir" || true
    tar -xzf "$tmp/latest.tar.gz" -C /opt/ || { rm -rf "$tmp"; return 1; }

    # Try to normalize extracted folder name: /opt/<name>-vX.Y -> /opt/<dirbase>
    local base
    base="$(basename "$dir")"
    local extracted
    extracted="$(ls -1 /opt | grep -E "^${base}-v" | sort -V | tail -n 1)"
    if [ -n "$extracted" ] && [ -d "/opt/$extracted" ]; then
        mv -f "/opt/$extracted" "$dir" || { rm -rf "$tmp"; return 1; }
    fi

    rm -rf "$tmp"
    echo "release" >"$ver_file" 2>/dev/null || true
    return 0
}

install_product_git() {
    local repo="$1"
    local dir="$2"
    local ver_file="$3"
    rm -rf "$dir" || true
    git clone "https://github.com/$repo" "$dir" || return 1
    echo "git" >"$ver_file" 2>/dev/null || true
    return 0
}

install_cfgs_repo() {
    [ -d "$PRODUCT_CFGS_DIR" ] && return 0
    git clone "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" || return 1
}

ensure_file() {
    local p="$1"
    [ -f "$p" ] && return 0
    mkdir -p "$(dirname "$p")" 2>/dev/null || true
    touch "$p" 2>/dev/null || true
}

ensure_hostlist_files() {
    # Prevent journal spam "cannot access hostlist file".
    ensure_file "$PRODUCT_LIST_FILE"
    ensure_file "$PRODUCT_EXCLUDE_FILE"

    # zapret uses extra lists in configs; create them if missing.
    if [ "$PRODUCT_ID" = "zapret" ]; then
        ensure_file "$PRODUCT_DIR/ipset/ipset-discord.txt"
    fi
}

systemd_install_product_units() {
    # Creates isolated systemd units for the active product context.
    # For zapret we rely on upstream units; for zapret2 we create our own to avoid conflicts.
    [ "$INIT_SYSTEM" = "systemd" ] || return 0

    if [ "$PRODUCT_ID" = "zapret" ]; then
        return 0
    fi

    if [ "$PRODUCT_ID" != "zapret2" ]; then
        return 0
    fi

    # Backup potential existing units with same name (rare but safe)
    backup_begin || true
    backup_path "/etc/systemd/system/${PRODUCT_SERVICE}.service" || true
    backup_path "/etc/systemd/system/${PRODUCT_SERVICE}-list-update.service" || true
    backup_path "/etc/systemd/system/${PRODUCT_SERVICE}-list-update.timer" || true

    mkdir -p /etc/systemd/system >/dev/null 2>&1 || true

    cat >"/etc/systemd/system/${PRODUCT_SERVICE}.service" <<EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutSec=120sec
ExecStart=${PRODUCT_DIR}/init.d/sysv/${PRODUCT_SERVICE} start
ExecStop=${PRODUCT_DIR}/init.d/sysv/${PRODUCT_SERVICE} stop

[Install]
WantedBy=multi-user.target
EOF

    cat >"/etc/systemd/system/${PRODUCT_SERVICE}-list-update.service" <<EOF
[Unit]
Description=${PRODUCT_SERVICE} ip/host list update

[Service]
Type=oneshot
TimeoutSec=120sec
ExecStart=${PRODUCT_DIR}/ipset/get_config.sh

[Install]
WantedBy=timers.target
EOF

    cat >"/etc/systemd/system/${PRODUCT_SERVICE}-list-update.timer" <<EOF
[Unit]
Description=${PRODUCT_SERVICE} ip/host list update timer

[Timer]
OnCalendar=*-*-2,4,6,8,10,12,14,16,18,20,22,24,26,28,30 00:00:00
RandomizedDelaySec=86400
Persistent=true
Unit=${PRODUCT_SERVICE}-list-update.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    return 0
}

product_install_default() {
    backup_begin || true
    backup_path "$PRODUCT_DIR" || true
    backup_path "$PRODUCT_VER_FILE" || true
    backup_path "$PRODUCT_BINLINK" || true
    backup_path "$STATE_FILE" || true

    ux_msg "План установки"
    product_print_plan
    ux_confirm "Продолжить установку $PRODUCT_ID?" || return 1

    install_dependencies >/dev/null 2>&1 || true

    if ! install_product_release "$PRODUCT_REPO" "$PRODUCT_DIR" "$PRODUCT_VER_FILE"; then
        install_product_git "$PRODUCT_REPO" "$PRODUCT_DIR" "$PRODUCT_VER_FILE" || {
            ux_msg "Не удалось установить $PRODUCT_ID (release/git)."
            return 1
        }
    fi

    # zapret upstream installer expects to be run in its dir
    if [ -f "$PRODUCT_DIR/install_easy.sh" ]; then
        (cd "$PRODUCT_DIR" && sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$PRODUCT_DIR/common/installer.sh" 2>/dev/null || true)
        (cd "$PRODUCT_DIR" && yes "" | ./install_easy.sh) || return 1
        (cd "$PRODUCT_DIR" && sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$PRODUCT_DIR/common/installer.sh" 2>/dev/null || true)
    fi

    systemd_install_product_units || true

    install_cfgs_repo || true

    # Seed config/list if missing (do not overwrite existing)
    if [ ! -f "$PRODUCT_CONFIG_FILE" ] && [ -d "$PRODUCT_CFGS_DIR/configurations" ]; then
        cp -f "$PRODUCT_CFGS_DIR/configurations/general" "$PRODUCT_CONFIG_FILE" 2>/dev/null || true
    fi
    if [ ! -f "$PRODUCT_LIST_FILE" ] && [ -d "$PRODUCT_CFGS_DIR/lists" ]; then
        mkdir -p "$(dirname "$PRODUCT_LIST_FILE")" || true
        cp -f "$PRODUCT_CFGS_DIR/lists/list-basic.txt" "$PRODUCT_LIST_FILE" 2>/dev/null || true
    fi
    [ -f "$PRODUCT_EXCLUDE_FILE" ] || { mkdir -p "$(dirname "$PRODUCT_EXCLUDE_FILE")" || true; touch "$PRODUCT_EXCLUDE_FILE" 2>/dev/null || true; }
    [ -f "$PRODUCT_GAME_IPSET_FILE" ] || { mkdir -p "$(dirname "$PRODUCT_GAME_IPSET_FILE")" || true; touch "$PRODUCT_GAME_IPSET_FILE" 2>/dev/null || true; }

    ensure_hostlist_files

    ln -sf /opt/zapret.installer/zapret-control.sh "$PRODUCT_BINLINK" || true

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable "${PRODUCT_SERVICE}.service" >/dev/null 2>&1 || true
        systemctl enable "${PRODUCT_SERVICE}-list-update.timer" >/dev/null 2>&1 || true
    fi
    service_manage restart "$PRODUCT_SERVICE" >/dev/null 2>&1 || true

    ux_msg "Установка завершена: $PRODUCT_ID. $(backup_done_msg)"
    return 0
}

