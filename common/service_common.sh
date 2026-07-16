#!/bin/bash

service_manage() {
    local action="$1"
    local name="$2"
    case "$INIT_SYSTEM" in
        systemd)
            if systemctl cat "$name" >/dev/null 2>&1; then
                SYSTEMD_PAGER=cat systemctl "$action" "$name"
            else
                if [ -n "$PRODUCT_DIR" ] && [ -x "$PRODUCT_DIR/init.d/sysv/$name" ]; then
                    "$PRODUCT_DIR/init.d/sysv/$name" "$action"
                else
                    return 1
                fi
            fi
            ;;
        openrc)
            rc-service "$name" "$action"
            ;;
        runit|runit-artix)
            sv "$action" "$name"
            ;;
        sysvinit)
            service "$name" "$action"
            ;;
        procd)
            service "$name" "$action"
            ;;
        *)
            return 1
            ;;
    esac
}

service_autostart() {
    local action="$1"
    local name="$2"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl "$action" "$name"
            ;;
        runit)
            if [ "$action" = "enable" ]; then
                ln -fs "$PRODUCT_DIR/init.d/runit/$name" /var/service/
            else
                rm -f "/var/service/$name"
            fi
            ;;
        runit-artix)
            if [ "$action" = "enable" ]; then
                ln -fs "$PRODUCT_DIR/init.d/runit/$name" /run/runit/service/
            else
                rm -f "/run/runit/service/$name"
            fi
            ;;
        sysvinit)
            if [ "$action" = "enable" ]; then
                update-rc.d "$name" defaults
            else
                update-rc.d -f "$name" remove
            fi
            ;;
        openrc)
            if [ "$action" = "enable" ]; then
                rc-update add "$name" default
            else
                rc-update del "$name"
            fi
            ;;
        procd)
            service "$name" "$action"
            ;;
        *)
            return 1
            ;;
    esac
}

service_is_installed() {
    local name="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl cat "$name" >/dev/null 2>&1 && return 0
            [ -n "$PRODUCT_DIR" ] && [ -x "$PRODUCT_DIR/init.d/sysv/$name" ] && return 0
            ;;
        procd)
            [ -f "/etc/init.d/$name" ] && return 0
            ;;
        runit)
            [ -d "/var/service/$name" ] && return 0
            ;;
        runit-artix)
            [ -d "/run/runit/service/$name" ] && return 0
            ;;
        openrc)
            rc-service -l 2>/dev/null | grep -q "^$name$" && return 0
            ;;
        sysvinit)
            [ -f "/etc/init.d/$name" ] && return 0
            ;;
    esac
    return 1
}

service_is_active() {
    local name="$1"
    case "$INIT_SYSTEM" in
        systemd)
            if systemctl cat "$name" >/dev/null 2>&1; then
                [ "$(systemctl show -p ActiveState "$name" 2>/dev/null | cut -d= -f2)" = "active" ] && return 0
            else
                return 1
            fi
            ;;
        openrc)
            rc-service "$name" status >/dev/null 2>&1 && return 0
            ;;
        procd)
            /etc/init.d/"$name" status 2>/dev/null | grep -q "running" && return 0
            ;;
        runit|runit-artix)
            sv status "$name" 2>/dev/null | grep -q "run" && return 0
            ;;
        sysvinit)
            service "$name" status >/dev/null 2>&1 && return 0
            ;;
    esac
    return 1
}

service_is_enabled() {
    local name="$1"
    case "$INIT_SYSTEM" in
        systemd)
            [ "$(systemctl is-enabled "$name" 2>/dev/null || echo "no")" = "enabled" ] && return 0
            ;;
        openrc)
            rc-update show 2>/dev/null | grep -q "$name" && return 0
            ;;
        procd)
            ls /etc/rc.d/ 2>/dev/null | grep -q "$name" && return 0
            ;;
        runit)
            [ -e "/var/service/$name" ] && return 0
            ;;
        runit-artix)
            [ -e "/run/runit/service/$name" ] && return 0
            ;;
        sysvinit)
            return 1
            ;;
    esac
    return 1
}

service_state() {
    local svc="$1"
    local st
    st="$(systemctl show -p ActiveState --value "$svc" 2>/dev/null || echo unknown)"
    case "$st" in
        active|activating)
            echo "running"
            ;;
        inactive|failed)
            echo "stopped"
            ;;
        *)
            echo "$st"
            ;;
    esac
}

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
            rc-service "${PRODUCT_SERVICE}" "$cmd"
            ;;
        runit|runit-artix)
            sv "$cmd" "${PRODUCT_SERVICE}"
            ;;
        sysvinit)
            service "${PRODUCT_SERVICE}" "$cmd"
            ;;
        procd)
            service "${PRODUCT_SERVICE}" "$cmd"
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
                ln -fs "${PRODUCT_DIR}/init.d/runit/${PRODUCT_SERVICE}" /var/service/
            else
                rm -f "/var/service/${PRODUCT_SERVICE}"
            fi
            ;;
        runit-artix)
            if [[ "$cmd" == "enable" ]]; then
                ln -fs "${PRODUCT_DIR}/init.d/runit/${PRODUCT_SERVICE}" /run/runit/service/
            else
                rm -f "/run/runit/service/${PRODUCT_SERVICE}"
            fi
            ;;
        sysvinit)
            if [[ "$cmd" == "enable" ]]; then
                update-rc.d "${PRODUCT_SERVICE}" defaults
            else
                update-rc.d -f "${PRODUCT_SERVICE}" remove
            fi
            ;;
        openrc)
            if [[ "$cmd" == "enable" ]]; then
                rc-update add "${PRODUCT_SERVICE}" default
            else
                rc-update del "${PRODUCT_SERVICE}"
            fi
            ;;
        procd)
            service "${PRODUCT_SERVICE}" "$cmd"
            ;;
        *)
            gum_notify warn "Неизвестная init-система: $INIT_SYSTEM"
            return 1
            ;;
    esac
}

is_product_installed() {
    local name="$1"
    [ -f "/etc/systemd/system/${name}.service" ] && return 0
    [ -f "/etc/init.d/${name}" ] && return 0
    [ -d "/var/service/${name}" ] && return 0
    [ -d "/run/runit/service/${name}" ] && return 0
    [ -d "/opt/${name}" ] && return 0
    return 1
}
