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
            rc-service zapret "$cmd"
            ;;
        runit|runit-artix)
            sv "$cmd" zapret
            ;;
        sysvinit)
            service zapret "$cmd"
            ;;
        procd)
            service zapret "$cmd"
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
                ln -fs /opt/zapret/init.d/runit/zapret /var/service/
            else
                rm -f /var/service/zapret
            fi
            ;;
        runit-artix)
            if [[ "$cmd" == "enable" ]]; then
                ln -fs /opt/zapret/init.d/runit/zapret /run/runit/service/
            else
                rm -f /run/runit/service/zapret
            fi
            ;;
        sysvinit)
            if [[ "$cmd" == "enable" ]]; then
                update-rc.d zapret defaults
            else
                update-rc.d -f zapret remove
            fi
            ;;
        openrc)
            if [[ "$cmd" == "enable" ]]; then
                rc-update add zapret default
            else
                rc-update del zapret
            fi
            ;;
        procd)
            service zapret "$cmd"
            ;;
        *)
            gum_notify warn "Неизвестная init-система: $INIT_SYSTEM"
            return 1
            ;;
    esac
}

check_zapret_exist() {
    local service_exists=false
    local dir_exists=false
    local binaries_exists=false

    case "$INIT_SYSTEM" in
        systemd)
            if systemd_unit_exists "zapret.service" || systemd_timer_exists "zapret-list-update.timer"; then
                service_exists=true
            fi
            ;;
        procd)
            [ -f /etc/init.d/zapret ] && service_exists=true
            ;;
        runit)
            [ -e /var/service/zapret ] && service_exists=true
            ;;
        runit-artix)
            [ -e /run/runit/service/zapret ] && service_exists=true
            ;;
        openrc)
            rc-service -l 2>/dev/null | grep -Fxq "zapret" && service_exists=true
            ;;
        sysvinit)
            [ -f /etc/init.d/zapret ] && service_exists=true
            ;;
        *)
            ZAPRET_EXIST=false
            return
            ;;
    esac

    if [ -d /opt/zapret ]; then
        dir_exists=true
        [ -d /opt/zapret/binaries ] && binaries_exists=true || binaries_exists=false
    fi

    if [ "$service_exists" = true ] && [ "$dir_exists" = true ] && [ "$binaries_exists" = true ]; then
        ZAPRET_EXIST=true
    else
        ZAPRET_EXIST=false
    fi
}

check_zapret_status() {
    case "$INIT_SYSTEM" in
        systemd)
            if ! systemd_unit_exists "zapret.service"; then
                ZAPRET_ACTIVE=false
                ZAPRET_ENABLED=false
                ZAPRET_SUBSTATE="not-found"
                return
            fi

            ZAPRET_ACTIVE="$(systemctl show -p ActiveState --value zapret.service 2>/dev/null || echo "inactive")"
            ZAPRET_SUBSTATE="$(systemctl show -p SubState --value zapret.service 2>/dev/null || echo "dead")"
            ZAPRET_ENABLED="$(systemctl is-enabled zapret.service 2>/dev/null || echo "disabled")"

            if [[ "$ZAPRET_ACTIVE" == "active" && "$ZAPRET_SUBSTATE" == "running" ]]; then
                ZAPRET_ACTIVE=true
            else
                ZAPRET_ACTIVE=false
            fi

            if [[ "$ZAPRET_ENABLED" == "enabled" ]]; then
                ZAPRET_ENABLED=true
            else
                ZAPRET_ENABLED=false
            fi
            ;;
        openrc)
            rc-service zapret status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            rc-update show 2>/dev/null | grep -q "zapret" && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        procd)
            /etc/init.d/zapret status 2>/dev/null | grep -q "running" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            [ -f /etc/rc.d/zapret ] && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        runit)
            sv status zapret 2>/dev/null | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            [ -e /var/service/zapret ] && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        runit-artix)
            sv status zapret 2>/dev/null | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            [ -e /run/runit/service/zapret ] && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        sysvinit)
            service zapret status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ;;
        *)
            ZAPRET_ACTIVE=false
            ZAPRET_ENABLED=false
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

detect_init() {
    GET_LIST_PREFIX=/ipset/get_

    SYSTEMD_DIR=/lib/systemd
    [ -d "$SYSTEMD_DIR" ] || SYSTEMD_DIR=/usr/lib/systemd
    [ -d "$SYSTEMD_DIR" ] && SYSTEMD_SYSTEM_DIR="$SYSTEMD_DIR/system"

    INIT_SCRIPT=/etc/init.d/zapret

    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ "${SYSTEM:-}" = "openwrt" ]; then
        INIT_SYSTEM="procd"
    elif command -v openrc >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    elif command -v runit >/dev/null 2>&1; then
        INIT_SYSTEM="runit"
        [ -f /etc/os-release ] && . /etc/os-release
        if [ "${ID:-}" = "artix" ]; then
            INIT_SYSTEM="runit-artix"
        fi
    elif [ -x /sbin/init ] && /sbin/init --version 2>&1 | grep -qi "sysv init"; then
        INIT_SYSTEM="sysvinit"
    else
        error_exit "Не удалось определить init."
    fi
}