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

    if ! gum_confirm "Импортировать config в $PRODUCT_CONFIG_FILE ?"; then
        return 1
    fi

    local restart=false
    gum_confirm "Перезапустить $PRODUCT_ID после импорта?" && restart=true
    apply_product_config "$imported" "$restart" || return 1

    gum_pause
}

config_import_pick() {
    local path caller_home
    caller_home="$(config_import_caller_home)"
    local HOME="$caller_home"
    cd "$caller_home" 2>/dev/null || return 1

    print_header "Импорт конфига" "normal" >&2
    printf 'TAB — автодополнение. Пустой Enter — назад.\n' >&2
    printf 'Домашняя папка: %s\n\n' "$caller_home" >&2

    read -erp "Путь > " path || return 1
    [ -n "$path" ] || return 1

    path="${path%\"}"
    path="${path#\"}"
    case "$path" in
        "~") path="$caller_home" ;;
        "~/"*) path="$caller_home/${path:2}" ;;
    esac

    config_import_validate "$path" || return 1
    printf '%s\n' "$path"
}

config_import_caller_home() {
    local caller="${SUDO_USER:-}"
    if [ -n "$caller" ] && [ "$caller" != "root" ]; then
        getent passwd "$caller" 2>/dev/null | cut -d: -f6 && return 0
    fi
    printf '%s\n' "$HOME"
}

config_import_validate() {
    local path="$1"
    [ -f "$path" ] || { gum_notify error "Файл не найден: $path" >&2; pause >&2; return 1; }
    [ -s "$path" ] || { gum_notify error "Файл пустой: $path" >&2; pause >&2; return 1; }

    if ! grep -qE '^[[:space:]]*(NFQWS_OPT|MODE_FILTER|TPWS_OPT)=' "$path"; then
        gum_notify warn "Файл не похож на конфиг zapret" >&2
        gum_confirm "Импортировать всё равно?" >&2 || return 1
    fi
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
action_enable()  { manage_autostart enable; }
action_disable() { manage_autostart disable; }

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

        local act
        act="$(ui_choose_one "Раздел" \
            "Статус" \
            "Сервис" \
            "Конфигурация" \
            "Диагностика" \
            "Назад")" || return 0

        case "$act" in
            "Статус") action_show_status ;;
            "Сервис") menu_service ;;
            "Конфигурация") menu_config ;;
            "Диагностика") menu_diagnostics ;;
            "Назад") return 0 ;;
        esac
    done
}

check_site_connection() {
    local name="$1" url="$2" result code rc
    if result=$(curl --noproxy '*' --silent --show-error --location --max-redirs 5 \
        --connect-timeout 5 --max-time 12 --output /dev/null \
        --write-out '%{http_code}' "$url" 2>&1); then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        printf '[ОШИБКА] %s: curl %s (%s)\n' "$name" "$rc" "$result"
        return 1
    fi
    code="$result"
    case "$code" in
        2??|3??) printf '[OK] %s: HTTP %s\n' "$name" "$code" ;;
        *) printf '[ОТВЕТ] %s: HTTP %s (соединение установлено, сайт вернул ошибку)\n' "$name" "$code"; return 1 ;;
    esac
}

action_check_sites() {
    print_header "Проверка доступности" "normal"
    if ! command -v curl >/dev/null 2>&1; then
        gum_notify error "Для проверки требуется curl"
        gum_pause
        return 1
    fi
    printf 'Прямые HTTPS-запросы без прокси; проверяется сетевое соединение и HTTP-ответ.\n\n'
    check_site_connection "Discord" "https://discord.com/api/v10/gateway" || :
    check_site_connection "Discord Gateway (HTTPS)" "https://gateway.discord.gg/" || :
    check_site_connection "YouTube" "https://www.youtube.com/" || :
    printf '\nGateway может вернуть ошибку HTTP: это не проверка WebSocket. Воспроизведение видео и голос здесь не проверяются.\n'
    gum_pause
}

menu_diagnostics() {
    while true; do
        clear
        print_header "Диагностика: $PRODUCT_ID" "normal"

        local opts=("Проверить доступность сайтов" "Проверка стратегий (blockcheck)")
        [ "$PRODUCT_ID" = "zapret2" ] && opts+=("blockcheckw")
        opts+=("Назад")

        local act
        act="$(ui_choose_one "Инструмент" "${opts[@]}")" || return 0

        case "$act" in
            "Проверить доступность сайтов") action_check_sites ;;
            "Проверка стратегий (blockcheck)") action_run_blockcheck ;;
            "blockcheckw") menu_blockcheckw ;;
            "Назад") return 0 ;;
        esac
    done
}

menu_blockcheckw() {
    while true; do
        clear
        print_header "blockcheckw" "normal"

        local act
        if [ -x "$PRODUCT_DIR/blockcheckw/blockcheckw" ]; then
            act="$(ui_choose_one "Действие" \
                "Подобрать стратегию для домена" \
                "Проверить домен или список" \
                "Проверить сохранённый отчёт" \
                "Посмотреть отчёты" \
                "Задать число воркеров (сейчас $(_bcw_workers))" \
                "Подобрать число воркеров (benchmark)" \
                "Удалить blockcheckw" \
                "Назад")" || return 0
        else
            act="$(ui_choose_one "Действие" \
                "Установить blockcheckw" \
                "Назад")" || return 0
        fi

        case "$act" in
            "Установить blockcheckw") action_install_blockcheckw ;;
            "Проверить домен или список") action_run_blockcheckw ;;
            "Подобрать стратегию для домена") action_auto_strategy ;;
            "Проверить сохранённый отчёт") action_check_bcw_report ;;
            "Посмотреть отчёты") action_view_bcw_results ;;
            "Задать число воркеров (сейчас $(_bcw_workers))") action_set_bcw_workers ;;
            "Подобрать число воркеров (benchmark)") action_bench_blockcheckw ;;
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

_download_from_group() {
    local grp="$1" _v name base_url target_subdir files_var
    _v="DL_${grp}_NAME"; local name="${!_v:-}"
    _v="DL_${grp}_URL"; local base_url="${!_v:-}"
    _v="DL_${grp}_TARGET"; local target_subdir="${!_v:-}"
    files_var="DL_${grp}_FILES[@]"
    local files=("${!files_var}")
    local target_dir="$PRODUCT_DIR/files/$target_subdir"

    [ -n "$base_url" ] && [ -n "$target_subdir" ] && [ "${#files[@]}" -gt 0 ] || {
        gum_notify error "Некорректная группа загрузки: $grp"
        return 1
    }

    print_header "Загрузка: $name" "normal"
    mkdir -p "$target_dir" || { gum_notify error "Не удалось создать $target_dir"; return 1; }
    chmod 755 "$target_dir" 2>/dev/null || true

    local file tmp ok=0 fail=0
    for file in "${files[@]}"; do
        printf '  %s ... ' "$file"
        tmp="$target_dir/.${file}.tmp"
        if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
            "$base_url/$file" -o "$tmp" && [ -s "$tmp" ]; then
            mv -f "$tmp" "$target_dir/$file"
            chmod 644 "$target_dir/$file" 2>/dev/null || true
            gum style --foreground 2 "OK"
            ((ok += 1))
        else
            rm -f "$tmp"
            gum style --foreground 1 "Ошибка"
            ((fail += 1))
        fi
    done

    gum_notify info "Загружено: $ok, ошибок: $fail — $target_dir"
    if [ "$target_subdir" = "fake" ] && [ "$ok" -gt 0 ] && gum_confirm "Перезапустить $PRODUCT_ID?"; then
        action_restart
    fi
    pause
}

action_download_group() {
    local target="$1" title="$2" all_label="$3" opts=() grp _v group_target name
    for grp in "${DL_GROUPS[@]}"; do
        _v="DL_${grp}_TARGET"; group_target="${!_v:-}"
        [ "$group_target" = "$target" ] || continue
        _v="DL_${grp}_NAME"; name="${!_v:-Группа $grp}"
        opts+=("$name")
    done
    [ "${#opts[@]}" -gt 0 ] || { gum_notify warn "Нет источников: $title"; return 0; }
    opts+=("$all_label" "Назад")

    local act
    act="$(ui_choose_one "$title" "${opts[@]}")" || return 0
    case "$act" in
        "$all_label")
            for grp in "${DL_GROUPS[@]}"; do
                _v="DL_${grp}_TARGET"; [ "${!_v:-}" = "$target" ] && _download_from_group "$grp"
            done
            ;;
        "Назад") return 0 ;;
        *)
            for grp in "${DL_GROUPS[@]}"; do
                _v="DL_${grp}_NAME"; [ "${!_v:-}" = "$act" ] && { _download_from_group "$grp"; break; }
            done
            ;;
    esac
}

action_download_fake_bins() { action_download_group "fake" "Fake бинарники" "Все fake-группы"; }
action_download_lists() { action_download_group "lists" "Lists" "Все list-группы"; }

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
        ext_opts+=("Скачать Fake бинарники")
        ext_opts+=("Скачать Lists")
        ext_opts+=("Установить preset")
        [ -n "${PRODUCT_STRATEGIES_DIR:-}" ] && ext_opts+=("Установить стратегию (zaprett-repo)")
        [ -n "${PRODUCT_CFGS_LIST_DIR:-}" ] && ext_opts+=("Установить list")
        [ -n "${PRODUCT_CFGS_LIST_DIR:-}" ] && ext_opts+=("Установить ipset list")
        ext_opts+=("Назад")

        local act
        act="$(ui_choose_one "Внешние источники (Download/Sync)" "${ext_opts[@]}")" || return 0

        case "$act" in
            "Скачать Fake бинарники")      action_download_fake_bins ;;
            "Скачать Lists")               action_download_lists ;;
            "Установить preset")           action_install_cfgs_config ;;
            "Установить стратегию (zaprett-repo)") action_install_strategy ;;
            "Установить list")             action_install_cfgs_list ;;
            "Установить ipset list")       action_install_cfgs_ipset_list ;;
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
            opts+=($'\033[1;38;2;168;93;93mУдаление\033[0m')
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
                            action_install_product "$_p"
                        done
                    else
                        action_install_product "$INSTALL_MODE"
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
            "Удаление"|$'\033[1;38;2;168;93;93mУдаление\033[0m')
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
