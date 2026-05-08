#!/bin/bash

ensure_gum_best_effort() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi

    # Best effort install via package manager. If it fails, we still keep fallback UX.
    [ -f /etc/os-release ] && . /etc/os-release
    case "${ID:-}" in
        arch|artix|cachyos|endeavouros|manjaro|garuda)
            $SUDO pacman -S --noconfirm --needed gum >/dev/null 2>&1 || true
            ;;
        debian|ubuntu|mint)
            $SUDO apt-get update -y >/dev/null 2>&1 || true
            $SUDO apt-get install -y gum >/dev/null 2>&1 || true
            ;;
        fedora|almalinux|rocky|rhel|centos|oracle|redos)
            if command -v dnf >/dev/null 2>&1; then
                $SUDO dnf install -y gum >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then
                $SUDO yum install -y gum >/dev/null 2>&1 || true
            fi
            ;;
        opensuse)
            $SUDO zypper install -y gum >/dev/null 2>&1 || true
            ;;
        alpine)
            $SUDO apk add gum >/dev/null 2>&1 || true
            ;;
    esac

    command -v gum >/dev/null 2>&1
}

ui_header() {
    local mode_txt
    mode_txt="$(state_load >/dev/null 2>&1; echo "$INSTALL_MODE")"
    echo "zapret.installer  |  режим: $mode_txt  |  zapret / zapret2 / оба"
}

draw_header() {
    ui_header
    echo ""
}


term_too_small() {
    local cols lines
    cols="$(tput cols 2>/dev/null || echo 0)"
    lines="$(tput lines 2>/dev/null || echo 0)"
    [ "$cols" -gt 0 ] && [ "$cols" -lt 70 ] && return 0
    [ "$lines" -gt 0 ] && [ "$lines" -lt 18 ] && return 0
    return 1
}

product_detect_installed() {
    # Basic heuristic: directory + binaries folder + service presence (if detectable)
    if [ -d "$PRODUCT_DIR" ] && [ -d "$PRODUCT_DIR/binaries" ]; then
        if service_is_installed "$PRODUCT_SERVICE"; then
            return 0
        fi
        # For partially installed systems where init adapter can't detect units reliably
        return 0
    fi
    return 1
}

print_header() {
    local title="${1:-}"
    local style="${2:-normal}"
    
    clear
    
    # Если заголовок не передан, определяем автоматически
    if [[ -z "$title" ]]; then
        # Если определена переменная NAME из модуля - используем её
        if [[ -n "${NAME:-}" ]]; then
            title="$NAME"
        else
            # Иначе используем название проекта
            title="ZAPRET_INSTALLER"
        fi
    fi
    
    # Определяем цвет рамки в зависимости от стиля
    local border_color="$ACCENT"
    local text_color=""
    
    case "$style" in
        error|danger|red)
            border_color="$RED"
            text_color="$RED"
            ;;
        success|ok|green)
            border_color="$GREEN"
            text_color="$GREEN"
            ;;
        warning|warn|yellow)
            border_color="$YELLOW"
            text_color="$YELLOW"
            ;;
        info|blue)
            border_color="$CYAN"
            text_color="$CYAN"
            ;;
        accent|magenta)
            border_color="$MAGENTA"
            text_color="$MAGENTA"
            ;;
        normal|*)
            border_color="$ACCENT"
            text_color=""
            ;;
    esac
    
    # Выводим заголовок с цветом
    if [[ -n "$text_color" ]]; then
        gum style --border rounded --border-foreground "$border_color" \
            --foreground "$text_color" --bold \
            --padding "1 5" --margin "1 2" --align center "$title"
    else
        gum style --border rounded --border-foreground "$border_color" \
            --padding "1 5" --margin "1 2" --align center "$title"
    fi
}

gum_notify() {
    local level="$1"
    shift
    local msg="$*"
    
    if ! command -v gum >/dev/null 2>&1; then
        case "$level" in
            ok) echo "[✓] $msg" ;;
            info) echo "[ℹ] $msg" ;;
            warn) echo "[⚠] $msg" ;;
            err) echo "[✗] $msg" >&2 ;;
            *) echo "$msg" ;;
        esac
        return
    fi
    
    case "$level" in
        ok)
            gum style --foreground "$GREEN" "✓ $msg"
            ;;
        info)
            gum style --foreground "$BLUE" "ℹ $msg"
            ;;
        warn)
            gum style --foreground "$YELLOW" "⚠ $msg"
            ;;
        err)
            gum style --foreground "$RED" "✗ $msg"
            ;;
        *)
            echo "$msg"
            ;;
    esac
}

action_show_status() {
    local active="no"
    local enabled="no"
    service_is_active "$PRODUCT_SERVICE" && active="yes"
    service_is_enabled "$PRODUCT_SERVICE" && enabled="yes"
    print_header
    ux_msg "Статус: $PRODUCT_ID
Каталог:   $PRODUCT_DIR
Сервис:    $PRODUCT_SERVICE
Активен:   $active
Автостарт: $enabled"
    pause
}

action_show_config_paths() {
    print_header
    ux_msg "Конфигурация: $PRODUCT_ID
config:   $PRODUCT_CONFIG_FILE
list:     $PRODUCT_LIST_FILE
exclude:  $PRODUCT_EXCLUDE_FILE"
    pause
}

action_start() { service_manage start "$PRODUCT_SERVICE"; }
action_stop() { service_manage stop "$PRODUCT_SERVICE"; }
action_restart() { service_manage restart "$PRODUCT_SERVICE"; }

action_enable() { service_autostart enable "$PRODUCT_SERVICE" >/dev/null 2>&1 || true; }
action_disable() { service_autostart disable "$PRODUCT_SERVICE" >/dev/null 2>&1 || true; }

product_choose() {
    local which
    which="$(ux_choose_one "Выберите продукт" "zapret" "zapret2" "Назад")" || return 1
    [ "$which" = "Назад" ] && return 2
    product_use "$which" || return 1
    return 0
}

menu_manage_product() {
    product_choose || return 0

    while true; do
        print_header
        local act
        act="$(ux_choose_one "Управление: $PRODUCT_ID" \
            "Статус" \
            "Запустить" \
            "Остановить" \
            "Перезапустить" \
            "Включить автозагрузку" \
            "Выключить автозагрузку" \
            "Показать пути конфигурации" \
            "Редактировать config" \
            "Редактировать list" \
            "Редактировать exclude" \
            "Назад")" || return 0

        case "$act" in
            "Статус") action_show_status ;;
            "Запустить")
                ensure_hostlist_files >/dev/null 2>&1 || true
                action_start || { ux_msg "Не удалось запустить $PRODUCT_ID"; pause; }
                ;;
            "Остановить") action_stop || { ux_msg "Не удалось остановить $PRODUCT_ID"; pause; } ;;
            "Перезапустить")
                ensure_hostlist_files >/dev/null 2>&1 || true
                action_restart || { ux_msg "Не удалось перезапустить $PRODUCT_ID"; pause; }
                ;;
            "Включить автозагрузку") action_enable; ux_msg "Готово"; pause ;;
            "Выключить автозагрузку") action_disable; ux_msg "Готово"; pause ;;
            "Показать пути конфигурации") action_show_config_paths ;;
            "Редактировать config") open_editor "$PRODUCT_CONFIG_FILE" ;;
            "Редактировать list") open_editor "$PRODUCT_LIST_FILE" ;;
            "Редактировать exclude") open_editor "$PRODUCT_EXCLUDE_FILE" ;;
            "Назад") return 0 ;;
        esac
    done
}

action_fix_units_zapret2() {
    product_use zapret2 || return 1
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        print_header
        ux_msg "Этот пункт актуален только для systemd."
        pause
        return 0
    fi
    ux_confirm "Создать/обновить systemd units для zapret2?" || return 1
    systemd_install_product_units || true
    systemctl enable "zapret2.service" >/dev/null 2>&1 || true
    systemctl enable "zapret2-list-update.timer" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    print_header
    ux_msg "Готово: units для zapret2 применены."
    pause
}

action_uninstall_soft() {
    # Does not touch other products. Backs up before removal.
    backup_begin || true
    backup_path "$PRODUCT_CONFIG_FILE" || true
    backup_path "$PRODUCT_LIST_FILE" || true
    backup_path "$PRODUCT_EXCLUDE_FILE" || true
    backup_path "$PRODUCT_GAME_IPSET_FILE" || true
    backup_path "$PRODUCT_VER_FILE" || true
    backup_path "$PRODUCT_BINLINK" || true
    backup_path "$STATE_FILE" || true

    ux_confirm "Удалить $PRODUCT_ID из $PRODUCT_DIR и убрать $PRODUCT_BINLINK?" || return 1
    service_manage stop "$PRODUCT_SERVICE" >/dev/null 2>&1 || true

    if [ -f "$PRODUCT_DIR/uninstall_easy.sh" ]; then
        (cd "$PRODUCT_DIR" && yes "" | ./uninstall_easy.sh) >/dev/null 2>&1 || true
    fi
    rm -rf "$PRODUCT_DIR" || true
    rm -f "$PRODUCT_BINLINK" || true
    rm -f "$PRODUCT_VER_FILE" || true
    ux_msg "Готово. $(backup_done_msg)"
}

action_switch_mode() {
    backup_begin || true
    backup_path "$STATE_FILE" || true

    local mode
    mode="$(ux_choose_one "Переключить режим (без переустановки)" "zapret" "zapret2" "both")" || return 1
    INSTALL_MODE="$mode"
    ACTIVE_PRODUCT="$mode"
    state_save || true
    ux_msg "Режим сохранён: $INSTALL_MODE. $(backup_done_msg)"
}

action_install_mode_choose() {
    local mode
    mode="$(ux_choose_one "Выберите режим установки" "Установить только zapret" "Установить только zapret2" "Установить оба (изолированно)")" || return 1
    case "$mode" in
        "Установить только zapret") INSTALL_MODE="zapret" ;;
        "Установить только zapret2") INSTALL_MODE="zapret2" ;;
        "Установить оба (изолированно)") INSTALL_MODE="both" ;;
        *) return 1 ;;
    esac
    ACTIVE_PRODUCT="$INSTALL_MODE"
    state_save || true
}

screen_compare_modes() {
    print_header
    ux_msg "Сравнение режимов (что будет установлено)

zapret:
  - каталог: /opt/zapret
  - сервис:  zapret
  - конфиг:  /opt/zapret/config  (совместимо со старыми установками)

zapret2:
  - каталог: /opt/zapret2
  - сервис:  zapret2  (units создаём, если их нет)
  - конфиг:  /opt/zapret2/config (отдельно, не конфликтует с zapret)

оба:
  - два изолированных каталога и сервиса
  - конфиги/листы живут параллельно
  - можно управлять каждым независимо"
    pause
}

main_menu_gum() {
    state_load
    ensure_gum_best_effort >/dev/null 2>&1 || true

    while true; do
        print_header
        if term_too_small; then
            ux_msg "Внимание: терминал маленький. Если меню отображается плохо — увеличьте окно."
            echo ""
        fi
        local action
        action="$(ux_choose_one "Главное меню" \
            "Установка / переустановка" \
            "Управление продуктом" \
            "Статус (оба продукта)" \
            "Сравнение режимов" \
            "Переключить режим (без переустановки)" \
            "Починить/создать systemd units (zapret2)" \
            "Проверка файлов hostlist" \
            "Просмотр логов" \
            "Удаление" \
            "Выход")" || return 0

        case "$action" in
            "Установка / переустановка")
                action_install_mode_choose || continue
                print_header
                ux_msg "Выбран режим: $INSTALL_MODE"
                if ux_confirm "Начать установку сейчас?"; then
                    case "$INSTALL_MODE" in
                        zapret)
                            product_use zapret && product_install_default
                            ;;
                        zapret2)
                            product_use zapret2 && product_install_default
                            ;;
                        both)
                            product_use zapret && product_install_default
                            product_use zapret2 && product_install_default
                            ;;
                    esac
                fi
                pause
                ;;
            "Управление продуктом")
                menu_manage_product
                ;;
            "Статус (оба продукта)")
                for p in zapret zapret2; do
                    product_use "$p" || continue
                    action_show_status
                done
                ;;
            "Сравнение режимов")
                screen_compare_modes
                ;;
            "Переключить режим без переустановки")
                action_switch_mode
                pause
                ;;
            "Починить/создать systemd units (zapret2)")
                action_fix_units_zapret2
                ;;
            "Проверка файлов hostlist")
                print_header
                ux_msg "Проверка hostlist-файлов (пока базовая):
zapret:
  /opt/zapret/ipset/zapret-hosts-user.txt
  /opt/zapret/ipset/zapret-hosts-user-exclude.txt
  /opt/zapret/ipset/ipset-discord.txt
zapret2:
  /opt/zapret2/ipset/zapret-hosts-user.txt
  /opt/zapret2/ipset/zapret-hosts-user-exclude.txt"
                ux_msg "Подсказка: в установке/repair мы автоматически создаём отсутствующие файлы."
                pause
                ;;
            "Просмотр логов")
                print_header
                ux_msg "Логи установщика:
  $(state_log_path)

Состояние:
  $STATE_FILE

Backups:
  $BACKUP_ROOT"
                pause
                ;;
            "Удаление")
                local whichu
                whichu="$(ux_choose_one "Что удалить?" "zapret" "zapret2" "Отмена")" || continue
                [ "$whichu" = "Отмена" ] && continue
                product_use "$whichu" || continue
                action_uninstall_soft || true
                pause
                ;;
            "Выход")
                clear
                return 0
                ;;
        esac
    done
}

