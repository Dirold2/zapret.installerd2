#!/bin/bash

# =========================
# GitHub helpers
# =========================
# GitHub requests are attempted directly first; the proxy is a fallback.
github_curl() {
    local url="$1" output; shift
    case "$url" in https://github.com/*|https://api.github.com/*) ;; *) return 1 ;; esac
    output=$(mktemp) || return 1
    if curl -fsSL --connect-timeout 8 --max-time 60 "$@" "$url" > "$output"; then
        cat "$output"; rm -f "$output"; return 0
    fi
    echo "GitHub недоступен, пробую cdn.gh-proxy.org" >&2
    if curl -fsSL --connect-timeout 8 --max-time 60 "$@" "https://cdn.gh-proxy.org/$url" > "$output"; then
        cat "$output"; rm -f "$output"; return 0
    fi
    rm -f "$output"
    return 1
}

github_git() {
    local url="$1"; shift
    GIT_TERMINAL_PROMPT=0 git -c http.connectTimeout=8 -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 "$@" "$url" && return 0
    case "$url" in https://github.com/*) ;; *) return 1 ;; esac
    echo "GitHub недоступен, пробую cdn.gh-proxy.org" >&2
    GIT_TERMINAL_PROMPT=0 git -c http.connectTimeout=8 -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 "$@" "https://cdn.gh-proxy.org/$url"
}

gh_latest_tag() {
    local repo="$1"
    github_curl "https://api.github.com/repos/$repo/releases/latest" | \
        python3 -c 'import sys, json; print(json.load(sys.stdin)["tag_name"])'
}

gh_release_url() {
    local repo="$1" tag="$2" commit
    commit=$(github_git "https://github.com/$repo.git" ls-remote --exit-code | awk -v tag="$tag" '$2 == "refs/tags/" tag "^{}" { peeled=$1 } $2 == "refs/tags/" tag { direct=$1 } END { print peeled ? peeled : direct }')
    [ -n "$commit" ] || return 1
    printf 'https://github.com/%s/archive/%s.tar.gz\n' "$repo" "$commit"
}

get_latest_version() {
    github_curl "https://api.github.com/repos/$PRODUCT_REPO/releases/latest" 2>/dev/null | \
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
    github_curl "$url" -o "$tmp/release.tar.gz" || { rm -rf "$tmp" "$fake_backup"; return 1; }

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
    local url="https://github.com/$PRODUCT_REPO"
    if ! GIT_TERMINAL_PROMPT=0 git -c http.connectTimeout=8 -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 clone --depth 1 "$url" "$PRODUCT_DIR"; then
        rm -rf "$PRODUCT_DIR"
        warn "GitHub недоступен, пробую cdn.gh-proxy.org"
        GIT_TERMINAL_PROMPT=0 git -c http.connectTimeout=8 -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 clone --depth 1 "https://cdn.gh-proxy.org/$url" "$PRODUCT_DIR" || return 1
        git -C "$PRODUCT_DIR" remote set-url origin "$url" || return 1
    fi
    echo "git" > "$PRODUCT_VER_FILE"
    log "$PRODUCT_ID установлен из git"
}

# Download a pinned external strategy without replacing upstream or user Lua files.
install_zapret2_lua() {
    [ "$PRODUCT_ID" = zapret2 ] || return 0
    local revision=7d5aec1bc7a8693dd20628f36ed40fb3d6897fc5
    local checksum=689077e30bb6dd4dbce037c7d81ea5e653966abb06eb881cb500f4055e823e5c
    local target="$PRODUCT_DIR/lua/zapret-installer-multishake.lua" tmp url host downloaded=false
    mkdir -p "$PRODUCT_DIR/lua" || return 1
    tmp=$(mktemp "$PRODUCT_DIR/lua/.multishake.XXXXXX") || return 1
    log "Скачиваю Lua-стратегию zapret2..."
    for host in git3.zapret.moe git2.zapret.moe git4.zapret.moe git5.zapret.moe git6.zapret.moe git.zapret.moe cwdnvtsqdc.zapret.moe; do
        url="https://$host/api/v1/repos/zapretdiscordyoutube/zapret2-youtube-discord/contents/lua/zapret-multishake.lua?ref=$revision"
        if curl -fsSL --connect-timeout 5 --max-time 20 "$url" | \
        python3 -c 'import base64, hashlib, json, sys
try:
    data = base64.b64decode(json.load(sys.stdin)["content"], validate=False)
    if hashlib.sha256(data).hexdigest() != sys.argv[1]:
        raise ValueError("SHA-256 mismatch")
    with open(sys.argv[2], "wb") as out:
        out.write(data)
except (ValueError, KeyError, OSError) as exc:
    print("Lua download validation failed:", exc, file=sys.stderr)
    sys.exit(1)' "$checksum" "$tmp"; then
            downloaded=true
            break
        fi
        echo "Зеркало $host недоступно или файл не прошёл проверку; пробую следующее" >&2
    done
    if [ "$downloaded" != true ]; then
        rm -f "$tmp"
        warn "Не удалось скачать или проверить Lua-стратегию zapret2"
        return 1
    fi
    chmod 644 "$tmp" && mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

install_cfgs() {
    [ -n "${PRODUCT_CFGS_REPO:-}" ] || return 0
    [ -d "$PRODUCT_CFGS_DIR" ] && return 0
    [ -n "$PRODUCT_CFGS_REPO" ] && GIT_TERMINAL_PROMPT=0 git clone "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" || warn "Не удалось клонировать конфиги: проверьте доступ к $PRODUCT_CFGS_REPO"
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

    if [ "$PRODUCT_ID" = "zapret2" ]; then
        source_config="$BASE_DIR/products/zapret2/default.conf"
        [ -f "$source_config" ] || { warn "Встроенный профиль zapret2 не найден: $source_config"; return 1; }
        bash -n "$source_config" || return 1
        cp -f "$source_config" "$PRODUCT_CONFIG_FILE" || return 1
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
    find "$PRODUCT_DIR" -name "*.sh" -exec chmod +x {} + || return 1
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
    manage_autostart enable || warn "Автозапуск $PRODUCT_ID не включён; проверьте другую службу и включите его вручную."
}

# =========================
# SAFE PRODUCT SWITCH (systemd)
# =========================
restore_legacy_service() {
    [ "${switch_pending:-false}" = true ] || return 0
    warn "Переключение не завершено; восстанавливаю состояние zapret"
    manage_service stop || warn "Не удалось остановить zapret2; проверьте службы вручную"
    manage_autostart disable || warn "Не удалось отключить автозапуск zapret2"
    if [ "$legacy_enabled" = true ]; then
        PRODUCT_SERVICE=zapret manage_autostart enable || warn "Не удалось восстановить автозапуск zapret"
    fi
    if [ "$legacy_active" = true ]; then
        PRODUCT_SERVICE=zapret manage_service start || warn "Не удалось запустить zapret; проверьте службы вручную"
    fi
}

prepare_legacy_switch() {
    [ "$PRODUCT_ID" = zapret2 ] || return 0
    legacy_active=false
    legacy_enabled=false
    service_is_active zapret && legacy_active=true
    service_is_enabled zapret && legacy_enabled=true
    if [ "$legacy_active" = false ] && [ "$legacy_enabled" = false ]; then
        return 0
    fi
    if [ "$INIT_SYSTEM" != systemd ]; then
        warn "Автоматическое переключение поддерживается только для systemd. Остановите zapret и отключите его автозапуск вручную."
        return 1
    fi
    echo "Для перехода zapret будет остановлен, а его автозапуск отключён. Файлы сохранятся."
    read -r -p "Переключиться на zapret2? (y/N): " answer
    [[ "$answer" =~ ^[Yy] ]] || return 1
    switch_pending=true
    if [ "$legacy_active" = true ]; then
        PRODUCT_SERVICE=zapret manage_service stop || return 1
    fi
    if [ "$legacy_enabled" = true ]; then
        PRODUCT_SERVICE=zapret manage_autostart disable || return 1
    fi
}

# =========================
# MAIN INSTALL
# =========================
main_install() (
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

    local switch_pending=false legacy_active=false legacy_enabled=false
    trap 'restore_legacy_service' EXIT
    prepare_legacy_switch || return 1

    [ -f "$PRODUCT_DIR/install_easy.sh" ] && {
        cd "$PRODUCT_DIR"
        sed -i 's/ask_yes_no N/ask_yes_no Y/g' common/installer.sh 2>/dev/null || true
        yes "" | ./install_easy.sh || true
        sed -i 's/ask_yes_no Y/ask_yes_no N/g' common/installer.sh 2>/dev/null || true
    }

    install_zapret2_lua || return 1
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
    ensure_scripts_executable || { warn "Не удалось настроить права скриптов $PRODUCT_ID"; return 1; }
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

    if service_is_active "$PRODUCT_SERVICE" && pgrep -x "$PRODUCT_BIN_NAME" >/dev/null 2>&1; then
        switch_pending=false
        log "$PRODUCT_ID успешно установлен и работает!"
    else
        warn "$PRODUCT_ID установлен, но не активен (проверьте nft/ipset)"
        return 1
    fi
)

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
        find "$staged" -type f -name "$PRODUCT_BIN_NAME" -executable | grep -q . || exit 1
        install_zapret2_lua || exit 1
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
