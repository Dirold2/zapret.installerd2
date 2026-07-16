ensure_cfgs_repo() {
    if [ -d "$PRODUCT_CFGS_DIR/.git" ]; then
        git -C "$PRODUCT_CFGS_DIR" pull --ff-only >/dev/null 2>&1 || return 1
        return 0
    fi

    rm -rf "$PRODUCT_CFGS_DIR" >/dev/null 2>&1 || true
    git clone --depth 1 "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" >/dev/null 2>&1 || return 1
}

validate_config() {
    local config_file="$1"
    local nfq_bin=""

    nfq_bin=$(find "$PRODUCT_DIR" -type f -name "$PRODUCT_BIN_NAME" 2>/dev/null | head -n1)

    [ -n "$nfq_bin" ] && [ -x "$nfq_bin" ] || {
        gum_notify warn "Бинарь $PRODUCT_BIN_NAME не найден, пропускаю проверку"
        return 0
    }

    if "$nfq_bin" --dry-run --qnum=100 "@$config_file" >/dev/null 2>&1; then
        gum_notify ok "Конфиг прошёл проверку"
        return 0
    else
        gum_notify error "Конфиг содержит ошибки!"
        "$nfq_bin" --dry-run --qnum=100 "@$config_file" 2>&1 | tail -5
        return 1
    fi
}

resolve_config_vars() {
    local config_file="$1"

    [ -f "$config_file" ] || return 1

    local tmp
    tmp=$(mktemp) || return 1
    cp -- "$config_file" "$tmp"

    if [ -n "$PRODUCT_PATH_BIN" ]; then
        sed -i \
            -e "s|%BIN%|$PRODUCT_PATH_BIN|g" \
            -e "s|@[Bb][Ii][Nn]|$PRODUCT_PATH_BIN|g" \
            "$tmp"
    fi

    if [ -n "$PRODUCT_PATH_LISTS" ]; then
        sed -i \
            -e "s|%LISTS%|$PRODUCT_PATH_LISTS|g" \
            -e "s|@[Ll][Ii][Ss][Tt][Ss]|$PRODUCT_PATH_LISTS|g" \
            -e "s|lists/|$PRODUCT_PATH_LISTS/|g" \
            "$tmp"
    fi

    if [ -n "$PRODUCT_PATH_LUA" ]; then
        sed -i \
            -e "s|%LUA%|$PRODUCT_PATH_LUA|g" \
            -e "s|@[Ll][Uu][Aa]|$PRODUCT_PATH_LUA|g" \
            -e "s|lua/|$PRODUCT_PATH_LUA/|g" \
            "$tmp"
    fi

    cp -- "$tmp" "$config_file"
    rm -f "$tmp"
}

preview_text_file() {
    local file="$1"

    if command -v bat >/dev/null 2>&1; then
        bat --style=plain "$file"
    elif command -v less >/dev/null 2>&1; then
        less "$file"
    elif command -v more >/dev/null 2>&1; then
        more "$file"
    else
        cat "$file"
        echo
        pause
    fi

    stty sane 2>/dev/null || true
}

pick_repo_file() {
    local dir="$1"
    local title="$2"
    local name_glob="${3:-*}"

    [ -d "$dir" ] || {
        gum_notify error "Папка не найдена: $dir"
        return 1
    }

    local items=()
    local f

    if [ "$name_glob" = "*" ]; then
        while IFS= read -r -d '' f; do
            items+=("${f##*/}")
        done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
    else
        while IFS= read -r -d '' f; do
            items+=("${f##*/}")
        done < <(find "$dir" -maxdepth 1 -type f -name "$name_glob" -print0 | sort -z)
    fi

    [ "${#items[@]}" -gt 0 ] || {
        gum_notify error "В $dir ничего не найдено"
        return 1
    }

    local choice
    choice="$(ui_choose_one "$title" "${items[@]}")" || return 1
    printf '%s\n' "$dir/$choice"
}

install_repo_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    backup_begin || true
    backup_path "$dst" || true

    cp -f -- "$src" "$dst" || {
        gum_notify error "Ошибка копирования: $label"
        return 1
    }

    gum_notify info "$label установлен"
    return 0
}

action_install_cfgs_config() {
    ensure_cfgs_repo || {
        gum_notify error "Не удалось обновить zapret.cfgs"
        return 1
    }

    [ -n "$PRODUCT_CFGS_CONFIG_DIR" ] && [ -d "$PRODUCT_CFGS_CONFIG_DIR" ] || {
        gum_notify error "Директория конфигов не найдена для $PRODUCT_ID"
        return 1
    }

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_CONFIG_DIR" "Выберите preset")" || return 1

    print_header "Предпросмотр config" "normal"
    preview_text_file "$imported"
    clear
    print_header "Подтверждение" "info"

    if ! gum_confirm "Установить этот config в $PRODUCT_CONFIG_FILE ?"; then
        return 1
    fi

    resolve_config_vars "$imported"

    validate_config "$imported" || {
        if ! gum_confirm "Конфиг содержит ошибки. Всё равно установить?"; then
            return 1
        fi
    }

    install_repo_file "$imported" "$PRODUCT_CONFIG_FILE" "Config" || return 1

    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi

    gum_pause
}

action_install_cfgs_list() {
    ensure_cfgs_repo || {
        gum_notify error "Не удалось обновить zapret.cfgs"
        return 1
    }

    [ -n "$PRODUCT_CFGS_LIST_DIR" ] && [ -d "$PRODUCT_CFGS_LIST_DIR" ] || {
        gum_notify error "Списки не поддерживаются для $PRODUCT_ID"
        pause
        return 1
    }

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_LIST_DIR" "Выберите hostlist" "list-*.txt")" || return 1

    print_header "Предпросмотр list" "normal"
    preview_text_file "$imported"
    clear
    print_header "Подтверждение" "info"

    if ! gum_confirm "Установить этот list в $PRODUCT_LIST_FILE ?"; then
        return 1
    fi

    install_repo_file "$imported" "$PRODUCT_LIST_FILE" "List" || return 1

    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi

    gum_pause
}

action_install_cfgs_ipset_list() {
    ensure_cfgs_repo || {
        gum_notify error "Не удалось обновить zapret.cfgs"
        return 1
    }

    [ -n "$PRODUCT_CFGS_LIST_DIR" ] && [ -d "$PRODUCT_CFGS_LIST_DIR" ] || {
        gum_notify error "Ipset-списки не поддерживаются для $PRODUCT_ID"
        pause
        return 1
    }

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_LIST_DIR" "Выберите ipset-list" "ipset-*.txt")" || return 1

    print_header "Предпросмотр ipset-list" "normal"
    preview_text_file "$imported"
    clear
    print_header "Подтверждение" "info"

    local dst="$PRODUCT_DIR/ipset/$(basename "$imported")"

    if ! gum_confirm "Установить этот ipset-list в $dst ?"; then
        return 1
    fi

    mkdir -p "$PRODUCT_DIR/ipset"
    install_repo_file "$imported" "$dst" "IPSet list" || return 1

    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi

    gum_pause
}

ensure_strategies_repo() {
    local dir="/opt/zapret.installer/strategies"

    if [ -d "$dir/.git" ]; then
        git -C "$dir" pull --ff-only >/dev/null 2>&1 || return 1
        return 0
    fi

    rm -rf "$dir" >/dev/null 2>&1 || true
    git clone --depth 1 "$PRODUCT_STRATEGIES_REPO" "$dir" >/dev/null 2>&1 || return 1
}

action_install_strategy() {
    local strategies_dir="/opt/zapret.installer/strategies/$PRODUCT_STRATEGIES_DIR"

    ensure_strategies_repo || {
        gum_notify error "Не удалось обновить zaprett-repo"
        return 1
    }

    [ -n "$PRODUCT_STRATEGIES_DIR" ] && [ -d "$strategies_dir" ] || {
        gum_notify error "Стратегии не поддерживаются для $PRODUCT_ID"
        pause
        return 1
    }

    local imported
    imported="$(pick_repo_file "$strategies_dir" "Выберите стратегию" "*.txt")" || return 1

    print_header "Предпросмотр стратегии" "normal"
    preview_text_file "$imported"
    clear
    print_header "Подтверждение" "info"

    if ! gum_confirm "Применить эту стратегию к $PRODUCT_CONFIG_FILE ?"; then
        return 1
    fi

    backup_begin || true
    backup_path "$PRODUCT_CONFIG_FILE" || true

    python3 <<PYEOF
import re
with open("$PRODUCT_CONFIG_FILE") as f:
    config = f.read()
with open("$imported") as f:
    strategy = f.read().rstrip('\n')

config = re.sub(
    r'(NFQWS_OPT="\n).*?(\n")',
    r'\1' + strategy + r'\2',
    config,
    flags=re.DOTALL
)

with open("$PRODUCT_CONFIG_FILE", 'w') as f:
    f.write(config)
PYEOF

    resolve_config_vars "$PRODUCT_CONFIG_FILE"

    validate_config "$PRODUCT_CONFIG_FILE" || {
        gum_notify error "Применённая стратегия сломала конфиг!"
        if [ -f "$BACKUP_DIR$PRODUCT_CONFIG_FILE" ]; then
            cp -f "$BACKUP_DIR$PRODUCT_CONFIG_FILE" "$PRODUCT_CONFIG_FILE"
            gum_notify info "Конфиг восстановлен из бэкапа"
        fi
        gum_pause
        return 1
    }

    gum_notify info "Стратегия применена к конфигу"

    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi

    gum_pause
}
