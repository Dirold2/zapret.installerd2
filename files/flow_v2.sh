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

# Dashboard-style TUI lives in files/tui.sh. This file keeps business actions.

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

action_show_status() {
    local active="no"
    local enabled="no"
    service_is_active "$PRODUCT_SERVICE" && active="yes"
    service_is_enabled "$PRODUCT_SERVICE" && enabled="yes"
    echo "Статус: $PRODUCT_ID"
    echo "Каталог:   $PRODUCT_DIR"
    echo "Сервис:    $PRODUCT_SERVICE"
    echo "Активен:   $active"
    echo "Автостарт: $enabled"
}

action_show_config_paths() {
    echo "Конфигурация: $PRODUCT_ID"
    echo "config:  $PRODUCT_CONFIG_FILE"
    echo "list:    $PRODUCT_LIST_FILE"
    echo "exclude: $PRODUCT_EXCLUDE_FILE"
}

action_start() { service_manage start "$PRODUCT_SERVICE"; }
action_stop() { service_manage stop "$PRODUCT_SERVICE"; }
action_restart() { service_manage restart "$PRODUCT_SERVICE"; }

action_enable() { service_autostart enable "$PRODUCT_SERVICE" >/dev/null 2>&1 || true; }
action_disable() { service_autostart disable "$PRODUCT_SERVICE" >/dev/null 2>&1 || true; }

action_fix_units_zapret2() {
    product_use zapret2 || return 1
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        echo "Этот пункт актуален только для systemd."
        return 0
    fi
    ux_confirm "Создать/обновить systemd units для zapret2?" || return 1
    systemd_install_product_units || true
    systemctl enable "zapret2.service" >/dev/null 2>&1 || true
    systemctl enable "zapret2-list-update.timer" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    echo "Готово: units для zapret2 применены."
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
    echo "Сравнение режимов (что будет установлено)

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
}

main_menu_gum() { return 1; }

