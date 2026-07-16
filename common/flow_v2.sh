#!/bin/bash

# flow_v2.sh - Cleaned interactive flow with gum
# Relies on helpers from common/ modules and product-specific init/health/install

# Auto-discover products from products/ directory
PRODUCTS_LIST=()
for _p_dir in "$BASE_DIR"/products/*/; do
    [ -f "$_p_dir/product.env" ] && PRODUCTS_LIST+=("$(basename "$_p_dir")")
done
unset _p_dir

product_use() {
    source "$BASE_DIR/products/$1/product.env"
    source "$BASE_DIR/products/$1/init.sh"
}

UI_DIRTY=true
UI_COMPACT=false
UI_COLS=0
UI_LINES=0
GUM_MENU_HEIGHT=10

on_resize() { UI_DIRTY=true; }
trap 'on_resize' WINCH

action_import_config() {
    local imported
    imported="$(config_import_pick)" || return 1

    print_header "Предпросмотр config" "normal"

    if command -v bat >/dev/null 2>&1; then
        bat --style=plain "$imported"
    elif command -v less >/dev/null 2>&1; then
        less "$imported"
    elif command -v more >/dev/null 2>&1; then
        more "$imported"
    else
        cat "$imported"
        echo
        pause
    fi

    stty sane 2>/dev/null || true
    clear
    print_header "Импорт конфига" "info"

    if ! grep -qE "NFQWS_OPT|MODE_FILTER|TPWS_OPT" "$imported"; then
        gum_notify warn "Файл не похож на zapret config"
        if ! gum_confirm "Всё равно импортировать?"; then
            return 1
        fi
    fi

    if ! gum_confirm "Импортировать config в $PRODUCT_CONFIG_FILE ?"; then
        return 1
    fi

    resolve_config_vars "$imported"

    validate_config "$imported" || {
        if ! gum_confirm "Конфиг содержит ошибки. Всё равно импортировать?"; then
            return 1
        fi
    }

    backup_begin || true
    backup_path "$PRODUCT_CONFIG_FILE" || true

    cp -f -- "$imported" "$PRODUCT_CONFIG_FILE" \
        || { gum_notify error "Ошибка копирования конфига"; return 1; }

    gum_notify info "Конфиг импортирован"

    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi

    gum_pause
}

config_import_pick() {
    local path
    cd / 2>/dev/null || cd "$HOME" 2>/dev/null || true
    while true; do
        print_header "Импорт конфига" "normal" >&2
        echo "[TAB] автодополнение путей" >&2
        echo "" >&2
        read -e -p "Путь > " path
        [ -z "$path" ] && return 1

        path="${path/#\~/$HOME}"
        path="${path%\"}"
        path="${path#\"}"

        if [ ! -e "$path" ]; then
            gum_notify error "Файл не найден" >&2
            pause >&2
            continue
        fi
        if [ ! -f "$path" ]; then
            gum_notify error "Это не файл" >&2
            pause >&2
            continue
        fi

        printf '%s\n' "$path"
        return 0
    done
}

action_export_config() {
    local path
    path="$(ui_path_input "Куда сохранить config")" || return 1
    [ -z "$path" ] && return 1
    path="${path/#\~/$HOME}"
    cp -f "$PRODUCT_CONFIG_FILE" "$path"
    gum_notify info "Config сохранён"
    pause
}

action_service_status_live() {
    print_header "systemd status" "normal"
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        ux_msg "Доступно только для systemd"
        pause
        return 1
    fi
    SYSTEMD_PAGER=cat systemctl status "$PRODUCT_SERVICE"
    echo
    gum_pause
}

action_service_logs() {
    clear

    if [ "$INIT_SYSTEM" != "systemd" ]; then
        ux_msg "Доступно только для systemd"
        pause
        return 1
    fi

    print_header "$PRODUCT_ID logs" "normal"

    echo
    gum style --foreground 240 "Ctrl+C — выход"
    echo

    local old_trap
    old_trap=$(trap -p INT TERM 2>/dev/null || true)
    trap 'tput cnorm 2>/dev/null || true; echo; return 0' INT TERM
    tput civis 2>/dev/null || true

    journalctl -u "$PRODUCT_SERVICE" -f --no-pager -o cat 2>/dev/null |
    while IFS= read -r line; do
        case "$line" in
            *Applying*|*Creating*)
                gum style --foreground 3 "▶ $line"
                ;;
            *Inserting*|*Adding*)
                gum style --foreground 4 "➜ $line"
                ;;
            *Started*|*net.netfilter*)
                gum style --foreground 2 "✔ $line"
                ;;
            *error*|*ERROR*|*failed*|*FAILED*)
                gum style --foreground 1 "✖ $line"
                ;;
            *)
                gum style --faint "  $line"
                ;;
        esac
    done

    tput cnorm 2>/dev/null || true
    eval "$old_trap" 2>/dev/null || true
}

product_status_text() {
    local active="no" enabled="no"
    service_is_active "$PRODUCT_SERVICE" && active="yes"
    service_is_enabled "$PRODUCT_SERVICE" && enabled="yes"

    local local_ver
    local_ver=$(cat "$PRODUCT_VER_FILE" 2>/dev/null || echo "—")
    if [ "$local_ver" = "release" ]; then
        local_ver="релиз"
    elif [ "$local_ver" = "git" ]; then
        local_ver="git"
    fi

    local update_status
    update_status=$(check_product_update "$PRODUCT_ID")
    case "$update_status" in
        current) update_status="актуально" ;;
        git)     update_status="git (проверка вручную)" ;;
        noconnect) update_status="ошибка проверки" ;;
        not_installed) update_status="" ;;
        *)       update_status="доступно $update_status" ;;
    esac

    cat <<EOF
Продукт:   $PRODUCT_ID
Версия:    $local_ver
Обновление: $update_status
Каталог:   $PRODUCT_DIR
Сервис:    $PRODUCT_SERVICE
Активен:   $active
Автостарт: $enabled
EOF
}

ui_products_status_line() {
    for _p in "${PRODUCTS_LIST[@]}"; do
        if is_product_installed "$_p"; then
            if product_use "$_p" && product_health "$_p"; then
                echo "  $(gum style --foreground 2 "$_p: работает")"
            else
                echo "  $(gum style --foreground 1 "$_p: не работает")"
            fi
        fi
    done
}

action_show_status() {
    print_header "$PRODUCT_ID" "normal"

    local svc="$PRODUCT_SERVICE"
    local st
    st="$(service_state "$svc")"

    local icon st_color
    if [[ "$st" == "running" || "$st" == "запущен" ]]; then
        icon="🟢"
        st_color=2
    else
        icon="🔴"
        st_color=1
    fi

    local local_ver
    local_ver=$(cat "$PRODUCT_VER_FILE" 2>/dev/null || echo "—")
    [ "$local_ver" = "release" ] && local_ver="релиз"

    local update_status
    update_status=$(check_product_update "$PRODUCT_ID")
    case "$update_status" in
        current)   update_status="$(gum style --foreground 2 'актуально')" ;;
        git)       update_status="$(gum style --foreground 3 'git')" ;;
        noconnect) update_status="$(gum style --foreground 1 'ошибка')" ;;
        not_installed) update_status="" ;;
        *)         update_status="$(gum style --foreground 1 "→ $update_status")" ;;
    esac

    gum style "Версия:  $local_ver"
    gum style "Сервис:  $svc"
    gum style "Статус:  $(gum style --foreground "$st_color" "$st") $icon"
    [ -n "$update_status" ] && gum style "Обновление: $update_status"

    echo

    gum style --bold "Логи (последние события):"
    ui_hr

    journalctl -u "$svc" -n 50 --no-pager -o cat |
        grep -vE '^\s*--' |
        tail -15 |
        while IFS= read -r line; do
            case "$line" in
                *Applying*|*Creating*)
                    gum style --foreground 3 "▶ $line"
                    ;;
                *Inserting*|*Adding*)
                    gum style --foreground 4 "➜ $line"
                    ;;
                *Started*|*net.netfilter*)
                    gum style --foreground 2 "✔ $line"
                    ;;
                *error*|*ERROR*|*failed*|*FAILED*)
                    gum style --foreground 1 "✖ $line"
                    ;;
                "")
                    ;;
                *)
                    gum style --faint "  $line"
                    ;;
            esac
        done

    ui_hr
    pause
}

action_show_all_status() {
    print_header "Статус zapret" "normal"

    local shown=false

    for p in "${PRODUCTS_LIST[@]}"; do
        if is_product_installed "$p"; then
            product_use "$p" || continue
            product_status_text
            echo
            shown=true
        fi
    done

    [[ "$shown" == false ]] && echo "Нет установленных продуктов"

    pause
}

action_show_config_paths() {
    print_header "$PRODUCT_ID" "normal"

    cat <<EOF
Конфигурация: $PRODUCT_ID

config:              $PRODUCT_CONFIG_FILE
list:                $PRODUCT_LIST_FILE
exclude:             $PRODUCT_EXCLUDE_FILE
EOF

    pause
}

action_start()   { manage_service start; }
action_stop()    { manage_service stop; }
action_restart() { manage_service restart; }
action_enable()  { manage_autostart enable >/dev/null 2>&1 || true; }
action_disable() { manage_autostart disable >/dev/null 2>&1 || true; }

product_choose() {
    local which
    local _opts=("${PRODUCTS_LIST[@]}" "Назад")
    which="$(ui_choose_one "Выберите продукт" "${_opts[@]}")" || return 1
    [ "$which" = "Назад" ] && return 2
    product_use "$which" || return 1
    return 0
}

action_install_mode_choose() {
    local opts=()
    local not_installed=()

    for _p in "${PRODUCTS_LIST[@]}"; do
        if ! is_product_installed "$_p"; then
            opts+=("$_p")
            not_installed+=("$_p")
        fi
    done

    if [ "${#not_installed[@]}" -gt 1 ]; then
        opts+=("Установить все")
    fi

    opts+=("Назад")

    local mode
    mode="$(ui_choose_one "Что установить?" "${opts[@]}")" || return 1

    case "$mode" in
        "Установить все")
            INSTALL_MODE="all"
            ;;
        "Назад"|"")
            return 1
            ;;
        *)
            INSTALL_MODE="$mode"
            ;;
    esac

    return 0
}

menu_manage_product() {
    local available=()

    for _p in "${PRODUCTS_LIST[@]}"; do
        is_product_installed "$_p" && available+=("$_p")
    done

    [ "${#available[@]}" -eq 0 ] && {
        ux_msg "Нет установленных продуктов"
        pause
        return 0
    }

    local which
    if [ "${#available[@]}" -eq 1 ]; then
        which="${available[0]}"
    else
        which="$(ui_choose_one "Выберите продукт" "${available[@]}")" || return 0
    fi

    product_use "$which" || return 1

    while true; do
        clear
        ui_maybe_refresh
        print_header "Управление: $PRODUCT_ID" "normal"

        local has_bcw=false
        [ -x "$PRODUCT_DIR/blockcheckw/blockcheckw" ] && has_bcw=true

        local opts=()
        opts+=("Статус")
        opts+=("Сервис")
        opts+=("Конфиги")
        opts+=("Логи")
        if $has_bcw; then
            opts+=("Проверка стратегий (blockcheckw)")
            opts+=("Удалить blockcheckw")
        else
            opts+=("Проверка стратегий (blockcheck)")
            [ "$PRODUCT_ID" = "zapret2" ] && opts+=("Установить blockcheckw")
        fi
        opts+=("Назад")

        local act
        act="$(ui_choose_one "Раздел" "${opts[@]}")" || return 0

        case "$act" in
            "Статус") action_show_status ;;
            "Сервис") menu_service ;;
            "Конфиги") menu_config ;;
            "Логи") menu_logs ;;
            "Проверка стратегий (blockcheck)") action_run_blockcheck ;;
            "Проверка стратегий (blockcheckw)") action_run_blockcheckw ;;
            "Установить blockcheckw") action_install_blockcheckw ;;
            "Удалить blockcheckw") action_uninstall_blockcheckw ;;
            "Назад") return 0 ;;
        esac
    done
}

menu_service() {
    while true; do
        clear
        local act
        act="$(ui_choose_one "Сервис" \
            "Запустить" \
            "Остановить" \
            "Перезапустить" \
            "Автозагрузка" \
            "systemctl status" \
            "Назад")" || return 0

        case "$act" in
            "Запустить") action_start || { ux_msg "Ошибка"; pause; } ;;
            "Остановить") action_stop || { ux_msg "Ошибка"; pause; } ;;
            "Перезапустить") action_restart || { ux_msg "Ошибка"; pause; } ;;
            "Автозагрузка")
                local a
                a="$(ui_choose_one "Автозагрузка" "Включить" "Выключить")" || continue
                [ "$a" = "Включить" ] && action_enable
                [ "$a" = "Выключить" ] && action_disable
                pause
                ;;
            "systemctl status") action_service_status_live ;;
            "Назад") return 0 ;;
        esac
    done
}

action_run_blockcheck() {
    local script_name="" script_url=""
    case "$PRODUCT_ID" in
        zapret)
            script_name="blockcheck.sh"
            script_url="https://raw.githubusercontent.com/bol-van/zapret/master/blockcheck.sh"
            ;;
        zapret2)
            script_name="blockcheck2.sh"
            script_url="https://raw.githubusercontent.com/bol-van/zapret2/master/blockcheck2.sh"
            ;;
        *) gum_notify error "Неизвестный продукт: $PRODUCT_ID"; return 1 ;;
    esac

    local script_path="$PRODUCT_DIR/$script_name"

    if [ ! -f "$script_path" ]; then
        print_header "Загрузка $script_name" "info"
        if ! curl -fL --retry 3 --connect-timeout 10 --max-time 60 \
            "$script_url" -o "$script_path.tmp"; then
            rm -f "$script_path.tmp"
            gum_notify error "Не удалось загрузить $script_name"
            pause
            return 1
        fi
        mv "$script_path.tmp" "$script_path"
        chmod +x "$script_path"
        gum_notify info "$script_name загружен"
    fi

    print_header "Проверка стратегий обхода ($PRODUCT_ID)" "info"
    echo
    gum style --foreground 3 "Внимание! Тест может занять 5-15 минут."
    gum style --foreground 3 "Во время теста возможны временные проблемы с сетью."
    echo
    if ! gum_confirm "Запустить blockcheck?"; then
        return 1
    fi

    clear
    print_header "blockcheck ($PRODUCT_ID)" "normal"
    echo
    gum style --foreground 240 "Ctrl+C — прервать тест"
    echo

    local old_trap
    old_trap=$(trap -p INT TERM 2>/dev/null || true)
    trap 'echo; gum_notify warn "Тест прерван пользователем"; return 1' INT TERM

    cd "$PRODUCT_DIR"
    bash "$script_path" || {
        gum_notify warn "$script_name завершился с ошибкой"
        eval "$old_trap" 2>/dev/null || true
        pause
        return 1
    }

    eval "$old_trap" 2>/dev/null || true
    echo
    gum_notify info "Проверка завершена"

    if gum_confirm "Открыть конфиг для применения рекомендаций?"; then
        open_editor "$PRODUCT_CONFIG_FILE"
        if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
            action_restart
        fi
    fi
    pause
}

action_install_blockcheckw() {
    [ "$PRODUCT_ID" = "zapret2" ] || { gum_notify error "blockcheckw только для zapret2"; return 1; }

    local target_dir="$PRODUCT_DIR/blockcheckw"
    local bin_path="$target_dir/blockcheckw"

    [ -x "$bin_path" ] && { gum_notify info "blockcheckw уже установлен"; return 0; }

    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm" ;;
        i686|i386) arch="x86" ;;
        mips)    arch="mips" ;;
        mips64)  arch="mips64" ;;
        mipsel)  arch="mipsel" ;;
        ppc)     arch="ppc" ;;
        riscv64) arch="riscv64" ;;
        *)
            gum_notify error "Неизвестная архитектура: $arch"
            return 1
            ;;
    esac

    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/rcd27/blockcheckw/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | cut -d'"' -f4)
    [ -z "$tag" ] && { gum_notify error "Не удалось определить версию"; return 1; }

    local tarball="blockcheckw-linux-${arch}.tar.gz"
    local url="https://github.com/rcd27/blockcheckw/releases/download/${tag}/${tarball}"

    print_header "Установка blockcheckw" "normal"
    gum style "Версия:  $tag"
    gum style "Арх:     $arch"
    echo

    local tmp
    tmp=$(mktemp -d) || { gum_notify error "Ошибка tmpdir"; return 1; }

    echo -n "Загрузка $tarball... "
    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
        "$url" -o "$tmp/$tarball"; then
        rm -rf "$tmp"
        gum style --foreground 1 "Ошибка"
        gum_notify error "Не удалось скачать $tarball"
        return 1
    fi
    gum style --foreground 2 "OK"

    echo -n "Распаковка... "
    mkdir -p "$target_dir"
    if ! tar -xzf "$tmp/$tarball" -C "$target_dir" 2>/dev/null; then
        rm -rf "$tmp" "$target_dir"
        gum style --foreground 1 "Ошибка"
        gum_notify error "Не удалось распаковать архив"
        return 1
    fi
    rm -rf "$tmp"
    gum style --foreground 2 "OK"

    chmod +x "$bin_path" 2>/dev/null || true

    local arch_dir
    arch_dir="$(uname -m)"
    local bin_links=("$PRODUCT_DIR/nfq2/nfqws2" "$PRODUCT_DIR/binaries/nfqws2")
    local target_bin_dir="$PRODUCT_DIR/binaries/linux-${arch_dir}"
    mkdir -p "$target_bin_dir"
    for src in "${bin_links[@]}"; do
        if [ -f "$src" ] && [ ! -f "$target_bin_dir/nfqws2" ]; then
            ln -sf "$src" "$target_bin_dir/nfqws2" 2>/dev/null || true
            break
        fi
    done

    gum_notify info "blockcheckw $tag установлен"
}

action_uninstall_blockcheckw() {
    local target_dir="$PRODUCT_DIR/blockcheckw"

    [ -d "$target_dir" ] || { gum_notify info "blockcheckw не установлен"; return 0; }

    if gum_confirm "Удалить blockcheckw?"; then
        rm -rf "$target_dir"
        gum_notify info "blockcheckw удалён"
    fi
}

action_run_blockcheckw() {
    local bin_path="$PRODUCT_DIR/blockcheckw/blockcheckw"

    if [ ! -x "$bin_path" ]; then
        if gum_confirm "blockcheckw не установлен. Установить?"; then
            action_install_blockcheckw || return 1
        else
            return 1
        fi
    fi

    print_header "blockcheckw ($PRODUCT_ID)" "info"
    echo
    gum style --foreground 3 "Быстрый параллельный поиск стратегий (Rust)."
    gum style --foreground 3 "Для использования нужен список доменов (.txt)."
    echo
    gum style --bold "Примеры:"
    gum style "  $bin_path universal --domain-list blocked.txt"
    gum style "  $bin_path status --domain-list domains.txt"
    gum style "  $bin_path scan --domain example.com"
    echo

    local domain_list
    read -erp "Путь к списку доменов (пусто = ручной ввод): " domain_list
    domain_list="${domain_list/#\~/$HOME}"

    local subcmd
    subcmd="$(ui_choose_one "Команда" "universal" "status" "scan" "Назад")" || return 0
    [ "$subcmd" = "Назад" ] && return 0

    local cmd_args=("$subcmd")

    if [ "$subcmd" = "scan" ]; then
        local domain
        read -erp "Домен: " domain
        [ -z "$domain" ] && { gum_notify error "Укажите домен"; return 1; }
        cmd_args+=("--domain" "$domain")
    elif [ -n "$domain_list" ] && [ -f "$domain_list" ]; then
        cmd_args+=("--domain-list" "$domain_list")
    fi

    clear
    print_header "blockcheckw $subcmd" "normal"
    echo
    gum style --foreground 240 "Ctrl+C — прервать"
    echo

    local old_trap
    old_trap=$(trap -p INT TERM 2>/dev/null || true)
    trap 'echo; gum_notify warn "Прервано"; return 1' INT TERM

    cd "$PRODUCT_DIR"
    "$bin_path" "${cmd_args[@]}" || {
        gum_notify warn "blockcheckw завершился с ошибкой"
        eval "$old_trap" 2>/dev/null || true
        pause
        return 1
    }

    eval "$old_trap" 2>/dev/null || true
    echo
    gum_notify info "Выполнение завершено"
    pause
}

action_download_fake_bins() {
    local target_dir="$PRODUCT_DIR/files/fake"
    local base_url="https://github.com/Sergeydigl3/flowseal-strategies-backup/tree/master/bin"
    local files=(
        "quic_initial_dbankcloud_ru.bin"
        "tls_clienthello_max_ru.bin"
    )

    print_header "Загрузка fake-бинарников" "normal"

    if [ ! -d "$target_dir" ]; then
        if gum_confirm "Директория $target_dir не найдена. Создать?"; then
            mkdir -p "$target_dir" || { gum_notify error "Нет прав на создание папки"; return 1; }
        else
            return 1
        fi
    fi

    for file in "${files[@]}"; do
        echo -n "Загрузка $file... "
        local tmp="$target_dir/.${file}.tmp"

        if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
            "$base_url/$file" -o "$tmp" \
            && [ -s "$tmp" ]; then
            mv -f "$tmp" "$target_dir/$file"
            gum style --foreground 2 "OK"
        else
            rm -f "$tmp"
            gum style --foreground 1 "Ошибка"
            gum_notify error "Не удалось загрузить $file"
            return 1
        fi
    done

    gum_notify info "Файлы обновлены в $target_dir"
    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then
        action_restart
    fi
    pause
}

action_download_lists() {
    local target_dir="$PRODUCT_DIR/files/lists"
    local base_url="https://raw.githubusercontent.com/Sergeydigl3/flowseal-strategies-backup/master/lists"
    local files=(
        "ipset-all.txt"
        "ipset-exclude.txt"
        "list-exclude.txt"
        "list-general.txt"
        "list-google.txt"
    )

    print_header "Загрузка lists (Flowseal)" "normal"

    if [ ! -d "$target_dir" ]; then
        if gum_confirm "Директория $target_dir не найдена. Создать?"; then
            mkdir -p "$target_dir" || { gum_notify error "Нет прав на создание папки"; return 1; }
        else
            return 1
        fi
    fi
    chmod 755 "$target_dir" 2>/dev/null || true

    for file in "${files[@]}"; do
        echo -n "Загрузка $file... "
        local tmp="$target_dir/.${file}.tmp"

        if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
            "$base_url/$file" -o "$tmp" \
            && [ -s "$tmp" ]; then
            mv -f "$tmp" "$target_dir/$file"
            chmod 644 "$target_dir/$file" 2>/dev/null || true
            gum style --foreground 2 "OK"
        else
            rm -f "$tmp"
            gum style --foreground 1 "Ошибка"
            gum_notify error "Не удалось загрузить $file"
            return 1
        fi
    done

    gum_notify info "Lists обновлены в $target_dir"
    pause
}

menu_config() {
    while true; do
        clear
        local act
        act="$(ui_choose_one "КОНФИГУРАЦИЯ" \
            "Редактировать config" \
            "Редактировать list" \
            "Редактировать exclude" \
            "Импорт конфига" \
            "Экспорт конфига" \
            "Показать пути" \
            "Внешние источники" \
            "Назад")" || return 0

        case "$act" in
            "Редактировать config")          open_editor "$PRODUCT_CONFIG_FILE" ;;
            "Редактировать list")            open_editor "$PRODUCT_LIST_FILE" ;;
            "Редактировать exclude")         open_editor "$PRODUCT_EXCLUDE_FILE" ;;
            "Импорт конфига")        action_import_config ;;
            "Экспорт конфига")       action_export_config ;;
            "Показать пути")         action_show_config_paths ;;
            "Внешние источники")     menu_external_sources ;;
            "Назад")                 return 0 ;;
        esac
    done
}

menu_external_sources() {
    while true; do
        clear
        local ext_opts=()
        ext_opts+=("Скачать Fake бинарники (Flowseal)")
        ext_opts+=("Скачать Lists (Flowseal)")
        ext_opts+=("Установить preset")
        [ -n "${PRODUCT_STRATEGIES_DIR:-}" ] && ext_opts+=("Установить стратегию (zaprett-repo)")
        [ -n "${PRODUCT_CFGS_LIST_DIR:-}" ] && ext_opts+=("Установить list")
        [ -n "${PRODUCT_CFGS_LIST_DIR:-}" ] && ext_opts+=("Установить ipset list")
        ext_opts+=("Назад")

        local act
        act="$(ui_choose_one "Внешние источники (Download/Sync)" "${ext_opts[@]}")" || return 0

        case "$act" in
            "Скачать Fake бинарники (Flowseal)") action_download_fake_bins ;;
            "Скачать Lists (Flowseal)")         action_download_lists ;;
            "Установить preset")               action_install_cfgs_config ;;
            "Установить стратегию (zaprett-repo)") action_install_strategy ;;
            "Установить list")                  action_install_cfgs_list ;;
            "Установить ipset list")            action_install_cfgs_ipset_list ;;
            "Назад") return 0 ;;
        esac
    done
}

menu_logs() {
    while true; do
        clear
        local act
        act="$(ui_choose_one "Логи" \
            "systemctl status" \
            "journalctl live" \
            "Назад")" || return 0

        case "$act" in
            "systemctl status") action_service_status_live ;;
            "journalctl live") action_service_logs ;;
            "Назад") return 0 ;;
        esac
    done
}

main_menu_gum() {
    state_load
    gum_init
    ui_refresh_layout

    while true; do
        ui_maybe_refresh
        print_header "Главное меню" "normal"

        local has_any=false
        local installed_count=0

        for _p in "${PRODUCTS_LIST[@]}"; do
            if is_product_installed "$_p"; then
                has_any=true
                ((installed_count++))
            fi
        done

        local opts=()

        if $has_any; then
            opts+=("Управление")
        fi

        if [ "$installed_count" -lt "${#PRODUCTS_LIST[@]}" ]; then
            opts+=("Установка")
        fi

        opts+=(
            "Статус"
        )

        if $has_any; then
            opts+=("Обновление")
        fi

        if $has_any; then
            opts+=("$(gum style --foreground 1 'Удаление')")
        fi

        opts+=("Выход")

        local action
        action="$(ui_choose_one "Главное меню" "${opts[@]}")" || return 0

        case "$action" in
            "Управление")
                menu_manage_product
                ;;
            "Установка")
                action_install_mode_choose || continue
                print_header "Установка" "normal"
                gum_notify info "Выбран режим: $INSTALL_MODE"

                if gum_confirm "Начать установку сейчас?"; then
                    if [ "$INSTALL_MODE" = "all" ]; then
                        for _p in "${PRODUCTS_LIST[@]}"; do
                            product_use "$_p" && main_install
                        done
                    else
                        product_use "$INSTALL_MODE" && main_install
                    fi
                fi
                gum_pause
                ;;
            "Статус")
                action_show_all_status
                ;;
            "Обновление")
                menu_update
                ;;
            "Удаление")
                local del_opts=()

                for _p in "${PRODUCTS_LIST[@]}"; do
                    is_product_installed "$_p" && del_opts+=("$_p")
                done
                del_opts+=("Отмена")

                local whichu
                whichu="$(ui_choose_one "Что удалить?" "${del_opts[@]}")" || continue
                [ "$whichu" = "Отмена" ] && continue

                action_uninstall_soft "$whichu"
                gum_pause
                ;;
            "Выход"|"")
                clear
                return 0
                ;;
        esac
    done
}
