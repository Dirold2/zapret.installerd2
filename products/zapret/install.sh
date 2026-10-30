#!/bin/bash

# =========================
# GitHub helpers
# =========================
gh_latest_tag() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | \
        python3 -c 'import sys, json; print(json.load(sys.stdin)["tag_name"])'
}

gh_release_url() {
    local repo="$1" tag="$2" commit
    commit=$(git ls-remote "https://github.com/$repo.git" "refs/tags/$tag^{}" "refs/tags/$tag" | \
        awk 'NR == 1 { print $1 }')
    [ -n "$commit" ] || return 1
    printf 'https://github.com/%s/archive/%s.tar.gz\n' "$repo" "$commit"
}

get_latest_version() {
    curl -fsSL "https://api.github.com/repos/$PRODUCT_REPO/releases/latest" 2>/dev/null | \
    grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//' || echo "unknown"
}

# =========================
# INSTALL CORE
# =========================
install_release() {
    local tmp tag url extracted fake_backup ver
    tmp=$(mktemp -d) || return 1
    fake_backup=$(mktemp -d)
    tag=$(gh_latest_tag "$PRODUCT_REPO") || { rm -rf "$tmp" "$fake_backup"; return 1; }
    url=$(gh_release_url "$PRODUCT_REPO" "$tag") || { rm -rf "$tmp" "$fake_backup"; return 1; }

    [ -z "$tag" ] || [ -z "$url" ] && { rm -rf "$tmp" "$fake_backup"; return 1; }

    [ -d "$PRODUCT_DIR/files/fake" ] && cp -r "$PRODUCT_DIR/files/fake"/* "$fake_backup/" 2>/dev/null || true

    log "Скачиваю релиз $PRODUCT_ID..."
    curl -fL "$url" -o "$tmp/release.tar.gz" || { rm -rf "$tmp" "$fake_backup"; return 1; }

    mkdir -p /opt

    tar -xzf "$tmp/release.tar.gz" -C /opt || {
        rm -rf "$tmp" "$fake_backup"
        return 1
    }

    extracted=$(tar -tzf "$tmp/release.tar.gz" | head -1 | cut -d/ -f1)
    extracted="/opt/$extracted"

    rm -rf "$tmp"
    [ -z "$extracted" ] || [ ! -d "$extracted" ] || [ ! -f "$extracted/Makefile" ] && {
        rm -rf "$extracted" "$fake_backup"
        return 1
    }

    rm -rf "$PRODUCT_DIR" || { rm -rf "$extracted" "$fake_backup"; return 1; }
    mv "$extracted" "$PRODUCT_DIR" || { rm -rf "$fake_backup"; return 1; }

    [ -d "$fake_backup" ] && [ "$(ls -A "$fake_backup" 2>/dev/null)" ] &&
        cp -r "$fake_backup"/* "$PRODUCT_DIR/files/fake/" 2>/dev/null || true
    rm -rf "$fake_backup"

    ver=${tag#v}
    echo "${ver:-release}" > "$PRODUCT_VER_FILE"
    log "$PRODUCT_ID установлен из релиза"
}

install_git() {
    rm -rf "$PRODUCT_DIR"
    log "Клонирую git-репозиторий $PRODUCT_REPO..."
    git clone --depth 1 "https://github.com/$PRODUCT_REPO" "$PRODUCT_DIR" || return 1
    echo "git" > "$PRODUCT_VER_FILE"
    log "$PRODUCT_ID установлен из git"
}

install_cfgs() {
    [ -d "$PRODUCT_CFGS_DIR" ] && return 0
    [ -n "$PRODUCT_CFGS_REPO" ] && git clone "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" 2>/dev/null || warn "Не удалось клонировать конфиги"
}

install_product_config() {
    local default_config="${PRODUCT_DEFAULT_CONFIG:-}"
    local config_file

    config_file="$PRODUCT_CONFIG_FILE"

    # Keep installation independent from the interactive snow module.
    resolve_installed_config_paths() {
        local file="$1"
        [ -f "$file" ] || return 1
        [ -n "${PRODUCT_PATH_BIN:-}" ] && sed -i \
            -e "s|%BIN%|$PRODUCT_PATH_BIN|g" \
            -e "s|@[Bb][Ii][Nn]|$PRODUCT_PATH_BIN|g" "$file"
        [ -n "${PRODUCT_PATH_LISTS:-}" ] && sed -i \
            -e "s|%LISTS%|$PRODUCT_PATH_LISTS|g" \
            -e "s|@[Ll][Ii][Ss][Tt][Ss]|$PRODUCT_PATH_LISTS|g" \
            -e "s|lists/|$PRODUCT_PATH_LISTS/|g" "$file"
        [ -n "${PRODUCT_PATH_LUA:-}" ] && sed -i \
            -e "s|%LUA%|$PRODUCT_PATH_LUA|g" \
            -e "s|@[Ll][Uu][Aa]|$PRODUCT_PATH_LUA|g" \
            -e "s|lua/|$PRODUCT_PATH_LUA/|g" "$file"
    }
    local source_config=""

    mkdir -p "$(dirname "$PRODUCT_CONFIG_FILE")" || return 1

    if [ "$PRODUCT_ID" = "zapret2" ] && [ -f "$PRODUCT_DIR/config.default" ]; then
        source_config="$PRODUCT_DIR/config.default"
        [ -n "$default_config" ] && [ -f "$PRODUCT_CFGS_CONFIG_DIR/$default_config" ] && {
            cp -f "$source_config" "$PRODUCT_CONFIG_FILE" || return 1
            printf '\n# Installer configuration: %s\n' "$default_config" >> "$PRODUCT_CONFIG_FILE"
            cat "$PRODUCT_CFGS_CONFIG_DIR/$default_config" >> "$PRODUCT_CONFIG_FILE" || return 1
        } || cp -f "$source_config" "$PRODUCT_CONFIG_FILE" || return 1
        resolve_installed_config_paths "$config_file" || return 1
        bash -n "$config_file" || return 1
        return 0
    fi

    [ -n "$PRODUCT_CFGS_CONFIG_DIR" ] || return 0
    [ -n "$default_config" ] || default_config=$(find "$PRODUCT_CFGS_CONFIG_DIR" -maxdepth 1 -type f -printf '%f\n' | head -n1)
    [ -n "$default_config" ] || return 0
    source_config="$PRODUCT_CFGS_CONFIG_DIR/$default_config"
    [ -f "$source_config" ] || return 0
    cp -f "$source_config" "$PRODUCT_CONFIG_FILE"
}

ensure_lists() {
    local ipset_dir="$PRODUCT_DIR/ipset"
    mkdir -p "$ipset_dir"
    chmod 755 "$ipset_dir" 2>/dev/null || true
    for f in zapret-hosts-user.txt ipset-game.txt ipset-discord.txt ipset-exclude-user.txt ipset-include-user.txt; do
        touch "$ipset_dir/$f" 2>/dev/null || true
        chmod 644 "$ipset_dir/$f" 2>/dev/null || true
    done
}

prepare_product_tmpdir() {
    [ "$PRODUCT_ID" = "zapret2" ] || return 0
    local tmpdir="${TMPDIR:-${PRODUCT_TMPDIR:-}}"
    [ -n "$tmpdir" ] || return 0
    mkdir -p -- "$tmpdir" || return 1
    if id -u "${WS_USER:-zapret2}" >/dev/null 2>&1; then
        chown "${WS_USER:-zapret2}:" "$tmpdir" 2>/dev/null || true
        chmod 700 "$tmpdir" 2>/dev/null || true
    fi
}

ensure_scripts_executable() {
    find "$PRODUCT_DIR" -name "*.sh" -exec chmod +x {} \\; 2>/dev/null || true
    [ -d "$PRODUCT_DIR/init.d" ] && chmod -R +x "$PRODUCT_DIR/init.d/" 2>/dev/null || true
    [ -d "$PRODUCT_DIR/ipset" ] && chmod -R 755 "$PRODUCT_DIR/ipset/" 2>/dev/null || true
    [ -d "$PRODUCT_DIR/files" ] && chmod -R 755 "$PRODUCT_DIR/files/" 2>/dev/null || true
}

# =========================
# SYSTEMD
# =========================
systemd_install() {
    [ "$INIT_SYSTEM" = "systemd" ] || return 0

    mkdir -p /etc/systemd/system

    local unit_path="/etc/systemd/system/${PRODUCT_SERVICE}.service"
    local script_path="${PRODUCT_DIR}/init.d/sysv/${PRODUCT_SERVICE}"

    cat > "$unit_path" <<EOF
[Unit]
Description=$PRODUCT_ID network filtering service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
Restart=no
TimeoutSec=30
KillMode=control-group
GuessMainPID=no

ExecStart=/bin/bash $script_path start
ExecStop=/bin/bash $script_path stop

RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${PRODUCT_SERVICE}.service" >/dev/null 2>&1 || true
}

# =========================
# MAIN INSTALL
# =========================
main_install() {
    read -p "Установить $PRODUCT_ID? (y/N): " answer
    [[ "$answer" =~ ^[Yy] ]] || return 0

    [ -d "$PRODUCT_DIR" ] && {
        read -p "Найден $PRODUCT_DIR. Удалить? (y/N): " answer
        [[ "$answer" =~ ^[Yy] ]] || return 0
        rm -rf "$PRODUCT_DIR"
    }

    command -v iptables >/dev/null 2>/dev/null || apt-get install -y iptables ipset 2>/dev/null || true

    if ! install_release; then
        warn "Релиз не удалось установить, использую git"
        install_git || error "Не удалось установить $PRODUCT_ID"
    fi

    log "Сборка $PRODUCT_ID..."
    cd "$PRODUCT_DIR" || error "Не удалось открыть $PRODUCT_DIR"
    make -j"$(nproc)" || error "Ошибка сборки $PRODUCT_ID"

    local nfq_bin
    nfq_bin=$(find "$PRODUCT_DIR" -type f -name "$PRODUCT_BIN_NAME" | head -n1)

    [ -n "$nfq_bin" ] || error "$PRODUCT_BIN_NAME binary не найден"
    [ -x "$nfq_bin" ] || error "$PRODUCT_BIN_NAME binary не executable"

    [ -f "$PRODUCT_DIR/install_easy.sh" ] && {
        cd "$PRODUCT_DIR"
        sed -i 's/ask_yes_no N/ask_yes_no Y/g' common/installer.sh 2>/dev/null || true
        yes "" | ./install_easy.sh || true
        sed -i 's/ask_yes_no Y/ask_yes_no N/g' common/installer.sh 2>/dev/null || true
    }

    install_cfgs
    install_product_config || {
        warn "Не удалось подготовить конфигурацию $PRODUCT_ID"
        return 1
    }
    if [ -n "${PRODUCT_CFGS_BIN_DIR:-}" ] && [ -d "$PRODUCT_CFGS_DIR/$PRODUCT_CFGS_BIN_DIR" ]; then
        mkdir -p "$PRODUCT_DIR/files/fake"
        cp "$PRODUCT_CFGS_DIR/$PRODUCT_CFGS_BIN_DIR/"* "$PRODUCT_DIR/files/fake/" 2>/dev/null || true
    fi

    ensure_lists
    ensure_scripts_executable
    prepare_product_tmpdir || {
        warn "Не удалось подготовить TMPDIR для $PRODUCT_ID"
        return 1
    }
    ln -sf "/opt/zapret.installer/zapret-control.sh" "/bin/$PRODUCT_ID" 2>/dev/null || true

    systemd_install
    manage_service restart 2>/dev/null || {
        warn "$PRODUCT_ID установлен, но сервис не удалось запустить"
        return 1
    }

    if product_health "$PRODUCT_SERVICE"; then
        log "$PRODUCT_ID успешно установлен и работает!"
    else
        warn "$PRODUCT_ID установлен, но не активен (проверьте nft/ipset)"
        return 1
    fi
}

# =========================
# UPDATE
# =========================
main_update() (
    # Stage beside the installation so directory renames stay on one filesystem.
    local live_dir="$PRODUCT_DIR" workspace staged old_dir was_running=false
    local ver_file_content tag_version
    workspace=$(mktemp -d "${live_dir}.update.XXXXXX") || return 1
    staged="$workspace/new"
    old_dir="$workspace/previous"
    trap 'if [ -d "$old_dir" ]; then warn "Предыдущая установка сохранена: $old_dir"; else rm -rf -- "$workspace"; fi' EXIT
    ver_file_content=$(cat "$PRODUCT_VER_FILE" 2>/dev/null || true)
    service_is_active "$PRODUCT_SERVICE" && was_running=true

    # Download helpers may replace PRODUCT_DIR and write PRODUCT_VER_FILE.
    # Keep both writes inside staging until the new binary is built.
    if ! (
        PRODUCT_DIR="$staged"
        PRODUCT_VER_FILE="$workspace/version"
        if [ "$ver_file_content" = "git" ]; then
            install_git || exit 1
        else
            install_release || exit 1
        fi
        cd "$staged" || exit 1
        make -j"$(nproc)" || exit 1
        find "$staged" -type f -name "$PRODUCT_BIN_NAME" -executable | grep -q .
    ); then
        warn "Подготовка обновления не удалась; текущая установка сохранена"
        return 1
    fi

    # Preserve user-managed data, not old executables or init scripts.
    local path
    for path in config ipset files/fake blockcheckw zapret.cfgs; do
        if [ -e "$live_dir/$path" ]; then
            if [ -d "$live_dir/$path" ]; then
                mkdir -p "$staged/$path" || return 1
                cp -a "$live_dir/$path/." "$staged/$path/" || return 1
            else
                cp -a "$live_dir/$path" "$staged/$path" || return 1
            fi
        fi
    done
    if [ "$PRODUCT_ID" = "zapret2" ] && [ -f "$staged/config" ]; then
        bash -n "$staged/config" || return 1
    fi
    tag_version=$(cat "$workspace/version") || return 1
    $was_running && manage_service stop || {
        if $was_running; then
            warn "Не удалось остановить сервис; обновление отменено"
            return 1
        fi
    }
    mv "$live_dir" "$old_dir" || return 1
    if ! mv "$staged" "$live_dir"; then
        mv "$old_dir" "$live_dir" || return 1
        $was_running && manage_service start
        return 1
    fi
    ensure_scripts_executable
    if $was_running && { ! manage_service start || ! product_health "$PRODUCT_SERVICE"; }; then
        warn "Новая версия не запустилась; восстанавливаю предыдущую"
        manage_service stop >/dev/null 2>&1 || true
        mv "$live_dir" "$workspace/failed" || return 1
        mv "$old_dir" "$live_dir" || return 1
        if ! manage_service start; then
            warn "Предыдущая версия восстановлена, но сервис не запущен"
        fi
        return 1
    fi
    printf '%s\n' "$tag_version" > "$PRODUCT_VER_FILE" || return 1
    rm -rf -- "$old_dir"
    log "$PRODUCT_ID обновлён; пользовательские настройки сохранены"
)
