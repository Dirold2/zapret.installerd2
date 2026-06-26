#!/bin/bash

systemd_unit_exists() {
    local unit="${1%.service}.service"
    systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$unit"
}

systemd_timer_exists() {
    local unit="${1%.timer}.timer"
    systemctl list-unit-files --type=timer --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$unit"
}

manage_service() {
    local cmd="${1:-}"
    local unit="${PRODUCT_SERVICE}.service"

    case "$INIT_SYSTEM" in
        systemd)
            if ! systemd_unit_exists "$unit"; then
                gum_notify warn "Unit $unit не найден. Сначала установите/почините systemd units."
                return 1
            fi

            case "$cmd" in
                status)
                    SYSTEMD_PAGER=cat systemctl status "$unit"
                    ;;
                start|stop|restart|enable|disable)
                    systemctl "$cmd" "$unit"
                    ;;
                *)
                    gum_notify warn "Неизвестная команда для сервиса: $cmd"
                    return 1
                    ;;
            esac
            ;;
        openrc)
            rc-service "${PRODUCT_SERVICE:-zapret}" "$cmd"
            ;;
        runit|runit-artix)
            sv "$cmd" "${PRODUCT_SERVICE:-zapret}"
            ;;
        sysvinit)
            service "${PRODUCT_SERVICE:-zapret}" "$cmd"
            ;;
        procd)
            service "${PRODUCT_SERVICE:-zapret}" "$cmd"
            ;;
        *)
            gum_notify warn "Неизвестная init-система: $INIT_SYSTEM"
            return 1
            ;;
    esac
}

manage_autostart() {
    local cmd="${1:-}"
    local unit="${PRODUCT_SERVICE}.service"

    case "$INIT_SYSTEM" in
        systemd)
            if ! systemd_unit_exists "$unit"; then
                gum_notify warn "Unit $unit не найден. Сначала установите/почините systemd units."
                return 1
            fi

            case "$cmd" in
                enable|disable)
                    systemctl "$cmd" "$unit"
                    ;;
                *)
                    gum_notify warn "Неизвестная команда автозагрузки: $cmd"
                    return 1
                    ;;
            esac
            ;;
        runit)
            if [[ "$cmd" == "enable" ]]; then
                ln -fs "${PRODUCT_DIR:-/opt/zapret}/init.d/runit/${PRODUCT_SERVICE:-zapret}" /var/service/
            else
                rm -f "/var/service/${PRODUCT_SERVICE:-zapret}"
            fi
            ;;
        runit-artix)
            if [[ "$cmd" == "enable" ]]; then
                ln -fs "${PRODUCT_DIR:-/opt/zapret}/init.d/runit/${PRODUCT_SERVICE:-zapret}" /run/runit/service/
            else
                rm -f "/run/runit/service/${PRODUCT_SERVICE:-zapret}"
            fi
            ;;
        sysvinit)
            if [[ "$cmd" == "enable" ]]; then
                update-rc.d "${PRODUCT_SERVICE:-zapret}" defaults
            else
                update-rc.d -f "${PRODUCT_SERVICE:-zapret}" remove
            fi
            ;;
        openrc)
            if [[ "$cmd" == "enable" ]]; then
                rc-update add "${PRODUCT_SERVICE:-zapret}" default
            else
                rc-update del "${PRODUCT_SERVICE:-zapret}"
            fi
            ;;
        procd)
            service "${PRODUCT_SERVICE:-zapret}" "$cmd"
            ;;
        *)
            gum_notify warn "Неизвестная init-система: $INIT_SYSTEM"
            return 1
            ;;
    esac
}

toggle_service() {
    while true; do
        clear
        check_zapret_status

        print_header "УПРАВЛЕНИЕ СЕРВИСОМ" "info"

        if [[ $ZAPRET_ACTIVE == true ]]; then
            gum_status_block "Статус" "Активен" "green"
        else
            gum_status_block "Статус" "Неактивен" "red"
        fi

        if [[ $ZAPRET_ENABLED == true ]]; then
            gum_status_block "Автозагрузка" "Включена" "green"
        else
            gum_status_block "Автозагрузка" "Отключена" "yellow"
        fi

        gum_divider

        local action
        action="$(gum_choose_one "Выберите действие" \
            "⚡ $( [[ $ZAPRET_ENABLED == true ]] && echo 'Убрать из автозагрузки' || echo 'Добавить в автозагрузку' )" \
            "▶️  $( [[ $ZAPRET_ACTIVE == true ]] && echo 'Выключить Запрет' || echo 'Включить Запрет' )" \
            "📊 Посмотреть статус" \
            "🔄 Перезапустить" \
            "↩️  Назад")" || return 0

        case "$action" in
            "⚡ Убрать из автозагрузки")
                manage_autostart disable || true
                ;;
            "⚡ Добавить в автозагрузку")
                manage_autostart enable || true
                ;;
            "▶️  Выключить Запрет")
                manage_service stop || true
                ;;
            "▶️  Включить Запрет")
                manage_service start || true
                ;;
            "📊 Посмотреть статус")
                manage_service status || true
                gum_pause
                ;;
            "🔄 Перезапустить")
                manage_service restart || true
                ;;
            "↩️  Назад")
                return 0
                ;;
            *)
                gum_notify warn "Неверный ввод! Попробуйте снова."
                sleep 2
                ;;
        esac
    done
}

