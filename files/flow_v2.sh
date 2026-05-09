#!/bin/bash

# flow_v2.sh - Лаконичный интерактивный flow с gum
# Использует функции из gum_utils.sh

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

    if command -v bat >/dev/null 2>&1; then bat --style=plain --paging=always "$imported"
    elif command -v less >/dev/null 2>&1; then less "$imported"
    elif command -v more >/dev/null 2>&1; then more "$imported"
    else cat "$imported"; echo; pause; fi

    if ! grep -qE "NFQWS_OPT|MODE_FILTER|TPWS_OPT" "$imported"; then
        gum_notify warn "Файл не похож на zapret config"
        if ! gum_confirm "Всё равно импортировать?"; then return 1; fi
    fi

    if ! gum_confirm "Импортировать config в $PRODUCT_CONFIG_FILE ?"; then return 1; fi

    backup_begin || true
    backup_path "$PRODUCT_CONFIG_FILE" || true
    cp -f -- "$imported" "$PRODUCT_CONFIG_FILE"

    gum_notify info "Конфиг импортирован"
    if gum_confirm "Перезапустить $PRODUCT_ID ?"; then action_restart; fi
    gum_pause
}

config_import_pick() {
    local path
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
            gum_notify error "Файл не найден" >&2; pause >&2; continue
        fi
        if [ ! -f "$path" ]; then
            gum_notify error "Это не файл" >&2; pause >&2; continue
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
        ux_msg "Доступно только для systemd"; pause; return 1
    fi
    SYSTEMD_PAGER=cat systemctl status "$PRODUCT_SERVICE"
    echo; gum_pause
}

action_service_logs() {
    clear
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        ux_msg "Доступно только для systemd"; pause; return 1
    fi
    journalctl -u "$PRODUCT_SERVICE" -f
}

ui_footer() {
    ui_maybe_refresh
    local size="${UI_COLS}x${UI_LINES}"
    if [ "$UI_COMPACT" = true ]; then
        gum style --foreground 240 "[compact] $size"
    else
        gum style --foreground 240 "[full] terminal=$size | menu-height=$GUM_MENU_HEIGHT"
    fi
}

ui_refresh_layout() {
    UI_COLS="$(tput cols 2>/dev/null || echo 0)"
    UI_LINES="$(tput lines 2>/dev/null || echo 0)"
    local VISIBLE_LINES=$((UI_LINES - RESERVED_LINES))

    [ "$VISIBLE_LINES" -lt "${MENU_REQUIRED_LINES:-20}" ] && UI_COMPACT=true || UI_COMPACT=false

    if [ "$UI_LINES" -ge 30 ]; then GUM_MENU_HEIGHT=14
    elif [ "$UI_LINES" -ge 24 ]; then GUM_MENU_HEIGHT=10
    elif [ "$UI_LINES" -ge 18 ]; then GUM_MENU_HEIGHT=7
    else GUM_MENU_HEIGHT=5; fi

    UI_DIRTY=false
}

ui_maybe_refresh() { [ "$UI_DIRTY" = true ] && ui_refresh_layout; }

ui_choose_one() {
    local title="$1"; shift
    ui_maybe_refresh
    gum choose --header "$title" --height "$GUM_MENU_HEIGHT" "$@"
}

ui_header() {
    local mode_txt="$(state_load >/dev/null 2>&1; echo "$INSTALL_MODE")"
    if $GUM_AVAILABLE; then
        if [ "$UI_COMPACT" = true ]; then
            gum style --foreground "$COLOR_CYAN" "zapret.installer | $mode_txt"
        else
            gum style --foreground "$COLOR_CYAN" "zapret.installer  |  режим: $mode_txt  |  zapret / zapret2 / оба"
        fi
    else
        [ "$UI_COMPACT" = true ] && echo "zapret.installer | $mode_txt" || echo "zapret.installer  |  режим: $mode_txt  |  zapret / zapret2 / оба"
    fi
}

print_header() {
    local title="${1:-${NAME:-ZAPRET_INSTALLER}}"
    local style="${2:-normal}"
    ui_maybe_refresh; clear
    gum_header "$title" "" "$style" >/dev/null 2>&1 || true
    [ "$UI_COMPACT" = true ] && echo || ui_footer
}

product_status_text() {
    local active="no" enabled="no"
    service_is_active "$PRODUCT_SERVICE" && active="yes"
    service_is_enabled "$PRODUCT_SERVICE" && enabled="yes"
    cat <<EOF
Продукт:   $PRODUCT_ID
Каталог:   $PRODUCT_DIR
Сервис:    $PRODUCT_SERVICE
Активен:   $active
Автостарт: $enabled
EOF
}

action_show_status() { print_header "$PRODUCT_ID" "normal"; ux_msg "$(product_status_text)"; pause; }

action_show_all_status() {
    local out=""
    print_header "Статус продуктов" "normal"
    for p in zapret zapret2; do
        product_use "$p" || continue
        out+="$(product_status_text)\n\n"
    done
    ux_msg "${out:-Статус недоступен}"; pause
}

action_show_config_paths() {
    print_header "$PRODUCT_ID" "normal"
    ux_msg "Конфигурация: $PRODUCT_ID\nconfig:   $PRODUCT_CONFIG_FILE\nlist:     $PRODUCT_LIST_FILE\nexclude:  $PRODUCT_EXCLUDE_FILE"
    pause
}

action_start()   { manage_service start; }
action_stop()    { manage_service stop; }
action_restart() { manage_service restart; }
action_enable()  { manage_autostart enable >/dev/null 2>&1 || true; }
action_disable() { manage_autostart disable >/dev/null 2>&1 || true; }

product_choose() {
    local which
    which="$(ui_choose_one "Выберите продукт" "zapret" "zapret2" "Назад")" || return 1
    [ "$which" = "Назад" ] && return 2
    product_use "$which" || return 1; return 0
}

# --- УНИВЕРСАЛЬНАЯ ПОЧИНКА UNITS (Для zapret и zapret2) ---
action_fix_units_universal() {
    if [ "$INIT_SYSTEM" != "systemd" ]; then return 0; fi

    local svc="$PRODUCT_SERVICE"
    
    # Жестко копируем из дистрибутива в систему
    if [ -d "$PRODUCT_DIR/init.d/systemd" ]; then
        cp -f "$PRODUCT_DIR/init.d/systemd/zapret.service" "/etc/systemd/system/${svc}.service" 2>/dev/null || true
        cp -f "$PRODUCT_DIR/init.d/systemd/zapret-list-update.service" "/etc/systemd/system/${svc}-list-update.service" 2>/dev/null || true
        cp -f "$PRODUCT_DIR/init.d/systemd/zapret-list-update.timer" "/etc/systemd/system/${svc}-list-update.timer" 2>/dev/null || true
    fi

    # Если это zapret2, меняем пути внутри файлов
    if [ "$PRODUCT_ID" != "zapret" ]; then
        sed -i "s|/opt/zapret|$PRODUCT_DIR|g" "/etc/systemd/system/${svc}.service" 2>/dev/null || true
        sed -i "s|/opt/zapret|$PRODUCT_DIR|g" "/etc/systemd/system/${svc}-list-update.service" 2>/dev/null || true
        sed -i "s|zapret\.service|${svc}.service|g" "/etc/systemd/system/${svc}-list-update.timer" 2>/dev/null || true
        sed -i "s|zapret\.service|${svc}.service|g" "/etc/systemd/system/${svc}-list-update.service" 2>/dev/null || true
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${svc}.service" >/dev/null 2>&1 || true
    systemctl enable "${svc}-list-update.timer" >/dev/null 2>&1 || true
}

action_uninstall_soft() {
    for f in "$PRODUCT_CONFIG_FILE" "$PRODUCT_LIST_FILE" "$PRODUCT_EXCLUDE_FILE" "$PRODUCT_GAME_IPSET_FILE" "$PRODUCT_VER_FILE" "$PRODUCT_BINLINK" "$STATE_FILE"; do
        backup_path "$f" || true
    done
    ux_confirm "Удалить $PRODUCT_ID из $PRODUCT_DIR и убрать $PRODUCT_BINLINK?" || return 1
    manage_service stop >/dev/null 2>&1 || true
    [ -f "$PRODUCT_DIR/uninstall_easy.sh" ] && (cd "$PRODUCT_DIR" && yes "" | ./uninstall_easy.sh) >/dev/null 2>&1 || true
    rm -rf "$PRODUCT_DIR" "$PRODUCT_BINLINK" "$PRODUCT_VER_FILE" "/etc/systemd/system/${PRODUCT_SERVICE}.service" || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    ux_msg "Готово. $(backup_done_msg)"
}

action_switch_mode() {
    backup_begin || true; backup_path "$STATE_FILE" || true
    local mode
    mode="$(ui_choose_one "Переключить режим (без переустановки)" "zapret" "zapret2" "both")" || return 1
    INSTALL_MODE="$mode"; ACTIVE_PRODUCT="$mode"
    state_save || true
    ux_msg "Режим сохранён: $INSTALL_MODE. $(backup_done_msg)"
}

action_install_mode_choose() {
    local title="Выберите режим установки"
    local opts=("Установить только zapret" "Установить только zapret2" "Установить оба (изолированно)")
    if [ "$UI_COMPACT" = true ]; then
        title="Режим установки"
        opts=("zapret" "zapret2" "both")
    fi

    local mode
    # Правильный вызов (ESC выходит)
    mode="$(ui_choose_one "$title" "${opts[@]}")" || return 1

    case "$mode" in
        "Установить только zapret"|"zapret") INSTALL_MODE="zapret" ;;
        "Установить только zapret2"|"zapret2") INSTALL_MODE="zapret2" ;;
        "Установить оба (изолированно)"|"both") INSTALL_MODE="both" ;;
        *) return 1 ;;
    esac
    ACTIVE_PRODUCT="$INSTALL_MODE"; state_save || true
}

screen_compare_modes() {
    print_header "Сравнение режимов" "normal"
    ux_msg "Сравнение режимов (что будет установлено)\n\nzapret:\n  - каталог: /opt/zapret\n  - сервис:  zapret\n\nzapret2:\n  - каталог: /opt/zapret2\n  - сервис:  zapret2\n\nоба:\n  - два изолированных каталога и сервиса"
    pause
}

menu_manage_product() {
    product_choose || return 0
    while true; do
        ui_maybe_refresh
        print_header "Управление: $PRODUCT_ID" "normal"

        local title="Управление: $PRODUCT_ID"
        local opts=(
            "Статус" "Запустить" "Остановить" "Перезапустить" 
            "Включить автозагрузку" "Выключить автозагрузку" "Показать пути конфигурации" 
            "Редактировать config" "Редактировать list" "Редактировать exclude" 
            "Импортировать config" "Экспортировать config" "systemctl status" "journalctl logs" "Назад"
        )
        if [ "$UI_COMPACT" = true ]; then
            title="Управление"
            opts=(
                "Статус" "Запустить" "Остановить" "Перезапустить" 
                "Автозагрузка +" "Автозагрузка -" "Конфиг" 
                "edit config" "edit list" "edit exclude" 
                "import cfg" "export cfg" "statusctl" "logs" "Назад"
            )
        fi

        local act
        # Правильный вызов с обработкой ESC
        act="$(ui_choose_one "$title" "${opts[@]}")" || return 0

        case "$act" in
            "Статус") action_show_status ;;
            "Запустить") action_start || { ux_msg "Ошибка запуска"; pause; } ;;
            "Остановить") action_stop || { ux_msg "Ошибка остановки"; pause; } ;;
            "Перезапустить") action_restart || { ux_msg "Ошибка"; pause; } ;;
            "Включить автозагрузку"|"Автозагрузка +") action_enable; ux_msg "Готово"; pause ;;
            "Выключить автозагрузку"|"Автозагрузка -") action_disable; ux_msg "Готово"; pause ;;
            "Показать пути конфигурации"|"Конфиг") action_show_config_paths ;;
            "Редактировать config"|"edit config") open_editor "$PRODUCT_CONFIG_FILE" ;;
            "Редактировать list"|"edit list") open_editor "$PRODUCT_LIST_FILE" ;;
            "Редактировать exclude"|"edit exclude") open_editor "$PRODUCT_EXCLUDE_FILE" ;;
            "Импортировать config"|"import cfg") action_import_config ;;
            "Экспортировать config"|"export cfg") action_export_config ;;
            "systemctl status"|"statusctl") action_service_status_live ;;
            "journalctl logs"|"logs") action_service_logs ;;
            "Назад"|"") return 0 ;;
        esac
    done
}

menu_extra_tools() {
    while true; do
        ui_maybe_refresh
        print_header "Дополнительно" "normal"

        local title="Дополнительно"
        local opts=(
            "Сравнение режимов" "Переключить режим без переустановки" 
            "Починить/создать systemd units (для выбранного)" "Просмотр логов и состояния" "Назад"
        )
        if [ "$UI_COMPACT" = true ]; then
            title="Инструменты"
            opts=("Сравнение" "Режим" "Починить Units" "Логи" "Назад")
        fi

        local act
        act="$(ui_choose_one "$title" "${opts[@]}")" || return 0

        case "$act" in
            "Сравнение режимов"|"Сравнение") screen_compare_modes ;;
            "Переключить режим без переустановки"|"Режим") action_switch_mode; gum_pause ;;
            "Починить/создать systemd units (для выбранного)"|"Починить Units") 
                product_choose || continue
                action_fix_units_universal
                ux_msg "Готово: units для $PRODUCT_ID обновлены/применены."
                pause
                ;;
            "Просмотр логов и состояния"|"Логи")
                print_header "Логи и состояние" "normal"
                gum_panel "Логи" "Логи установщика: $(state_log_path)\nСостояние: $STATE_FILE" "info"
                gum_pause ;;
            "Назад"|"") return 0 ;;
        esac
    done
}

main_menu_gum() {
    state_load; gum_init; ui_refresh_layout

    while true; do
        ui_maybe_refresh
        print_header "Главное меню" "normal"

        local title="Главное меню"
        local opts=("Установка / переустановка" "Управление продуктом" "Статус" "Дополнительно" "Удаление" "Выход")
        if [ "$UI_COMPACT" = true ]; then
            title="Меню"
            opts=("Установка" "Управление" "Статус" "Дополнительно" "Удаление" "Выход")
        fi

        local action
        action="$(ui_choose_one "$title" "${opts[@]}")" || return 0

        case "$action" in
            "Установка"|"Установка / переустановка")
                action_install_mode_choose || continue
                print_header "Установка" "normal"
                gum_notify info "Выбран режим: $INSTALL_MODE"
                
                if gum_confirm "Начать установку сейчас?"; then
                    case "$INSTALL_MODE" in
                        zapret) 
                            product_use zapret && product_install_default
                            action_fix_units_universal # Вызываем починку сразу после установки
                            ;;
                        zapret2) 
                            product_use zapret2 && product_install_default
                            action_fix_units_universal
                            ;;
                        both) 
                            product_use zapret && product_install_default
                            action_fix_units_universal
                            product_use zapret2 && product_install_default
                            action_fix_units_universal
                            ;;
                        Назад) continue ;;
                    esac
                fi
                gum_pause ;;
            "Управление"|"Управление продуктом") menu_manage_product ;;
            "Статус") action_show_all_status ;;
            "Дополнительно") menu_extra_tools ;;
            "Удаление")
                local whichu
                whichu="$(ui_choose_one "Что удалить?" "zapret" "zapret2" "Отмена")" || continue
                [ "$whichu" = "Отмена" -|| -z "$whichu" ] && continue
                product_use "$whichu" || continue
                action_uninstall_soft || true
                gum_pause ;;
            "Выход"|"") clear; return 0 ;;
        esac
    done
}