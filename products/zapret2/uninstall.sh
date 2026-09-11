#!/bin/bash

local_uninstall() {
    local p="$1"
    [ -z "$p" ] && return 1

    if ! gum_confirm "Полностью удалить $p?"; then
        return 0
    fi

    echo "Остановка сервиса zapret2..."
    manage_service stop >/dev/null 2>&1 || true
    manage_autostart disable >/dev/null 2>&1 || true

    if [ "${INIT_SYSTEM:-}" = "systemd" ]; then
        echo "Остановка таймера обновления списков..."
        systemctl stop zapret2-list-update.timer >/dev/null 2>&1 || true
        systemctl disable zapret2-list-update.timer >/dev/null 2>&1 || true
    fi

    echo "Остановка процесса nfqws2..."
    if [ -f /var/run/nfqws2_1.pid ]; then
        sudo kill "$(cat /var/run/nfqws2_1.pid)" 2>/dev/null || true
        sudo rm -f /var/run/nfqws2_1.pid
    fi
    sudo pkill -f nfqws2 2>/dev/null || true

    echo "Удаление nftables правил..."
    sudo nft delete table inet zapret2 2>/dev/null || true

    echo "Удаление cron задач..."
    crontab -l 2>/dev/null | grep -v zapret | crontab - 2>/dev/null || true

    echo "Удаление файлов..."
    sudo rm -rf /opt/zapret2
    sudo rm -f /opt/zapret2-ver
    sudo rm -f /bin/zapret2

    sudo rm -f /etc/systemd/system/zapret2.service
    sudo rm -f /etc/systemd/system/zapret2.service.d
    sudo rm -f /etc/systemd/system/zapret2-list-update.timer

    if [ "${INIT_SYSTEM:-}" = "systemd" ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed zapret2.service >/dev/null 2>&1 || true
    fi

    gum_notify success "Продукт $p успешно удален"
}
