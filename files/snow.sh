ensure_cfgs_repo() {
    if [ -d "$PRODUCT_CFGS_DIR/.git" ]; then
        git -C "$PRODUCT_CFGS_DIR" pull --ff-only >/dev/null 2>&1 || return 1
        return 0
    fi

    rm -rf "$PRODUCT_CFGS_DIR" >/dev/null 2>&1 || true
    git clone --depth 1 "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" >/dev/null 2>&1 || return 1
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

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_DIR/configurations" "Выберите config из Snowy-Fluffy")" || return 1

    print_header "Предпросмотр config" "normal"
    preview_text_file "$imported"
    clear
    print_header "Подтверждение" "info"

    if ! gum_confirm "Установить этот config в $PRODUCT_CONFIG_FILE ?"; then
        return 1
    fi

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

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_DIR/lists" "Выберите hostlist из Snowy-Fluffy" "list-*.txt")" || return 1

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

    local imported
    imported="$(pick_repo_file "$PRODUCT_CFGS_DIR/lists" "Выберите ipset-list из Snowy-Fluffy" "ipset-*.txt")" || return 1

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