#!/bin/bash

action_uninstall_soft() {
    local p="$1"
    [ -z "$p" ] && return 1

    if ! gum_confirm "Полностью удалить $p?"; then
        return 0
    fi

    echo "Остановка сервиса zapret..."
    systemctl stop zapret.service >/dev/null 2>&1 || true
    systemctl disable zapret.service >/dev/null 2>&1 || true
    systemctl stop zapret-list-update.timer >/dev/null 2>&1 || true
    systemctl disable zapret-list-update.timer >/dev/null 2>&1 || true

    echo "Удаление файлов..."
    sudo rm -rf /opt/zapret
    sudo rm -f /opt/zapret-ver
    sudo rm -f /bin/zapret

    sudo rm -f /etc/systemd/system/zapret.service
    sudo rm -f /etc/systemd/system/zapret.service.d
    sudo rm -f /etc/systemd/system/zapret-list-update.timer
    sudo rm -f /etc/systemd/system/zapret-list-update.timer.d

    echo "Перезапуск демона systemd..."
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl reset-failed zapret.service >/dev/null 2>&1 || true

    gum_notify success "Продукт $p успешно удален"
}
