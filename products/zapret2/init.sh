#!/bin/bash

check_zapret_exist() {
    case "$INIT_SYSTEM" in
        systemd)
            if [ -f /etc/systemd/system/timers.target.wants/zapret2-list-update.timer ]; then
                service_exists=true
            else
                service_exists=false
            fi
            ;;
        procd)
            if [ -f /etc/init.d/zapret2 ]; then
                service_exists=true
            else
                service_exists=false
            fi
            ;;
        runit)
            ls /var/service | grep -q "zapret2" && service_exists=true || service_exists=false
            ;;
        runit-artix)
            ls /run/runit/service | grep -q "zapret2" && service_exists=true || service_exists=false
            ;;
        openrc)
            rc-service -l | grep -q "zapret2" && service_exists=true || service_exists=false
            ;;
        sysvinit)
            [ -f /etc/init.d/zapret2 ] && service_exists=true || service_exists=false
            ;;
        *)
            ZAPRET_EXIST=false
            return
            ;;
    esac

    if [ -d /opt/zapret2 ]; then
        dir_exists=true
        [ -d /opt/zapret2/binaries ] && binaries_exists=true || binaries_exists=false
    else
        dir_exists=false
        binaries_exists=false
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
        ZAPRET_ACTIVE=$(systemctl show -p ActiveState zapret2 | cut -d= -f2 || true)
        ZAPRET_ENABLED=$(systemctl is-enabled zapret2 2>/dev/null || echo "false")
        ZAPRET_SUBSTATE=$(systemctl show -p SubState zapret2 | cut -d= -f2)
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
        if [[ "$ZAPRET_ENABLED" == "not-found" ]]; then
            ZAPRET_ENABLED=false
        fi
        ;;
        openrc)
            rc-service zapret2 status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            rc-update show | grep -q zapret2 && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        procd)
            if /etc/init.d/zapret2 status | grep -q "running"; then
                ZAPRET_ACTIVE=true
            else
                ZAPRET_ACTIVE=false
            fi
            if ls /etc/rc.d/ | grep -q zapret2 >/dev/null 2>&1; then
                ZAPRET_ENABLED=true
            else
                ZAPRET_ENABLED=false
            fi
            ;;
        runit)
            sv status zapret2 | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ls /var/service | grep -q "zapret2" && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        runit-artix)
            sv status zapret2 | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ls /run/runit/service | grep -q "zapret2" && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        sysvinit)
            service zapret2 status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ;;
    esac
}

product_health() {
    local running=0

    if pgrep -x nfqws2 >/dev/null 2>&1; then
        running=1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active zapret2 >/dev/null 2>&1 && running=1
    fi

    [[ $running -eq 1 ]]
}
