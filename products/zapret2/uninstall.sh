#!/bin/bash

action_uninstall_soft() {
    local p="$1"
    [ -z "$p" ] && return 1

    if ! gum_confirm "Полностью удалить $p?"; then
        return 0
    fi

    echo "Остановка сервиса zapret2..."
    systemctl stop zapret2.service >/dev/null 2>&1 || true
    systemctl disable zapret2.service >/dev/null 2>&1 || true

    echo "Удаление файлов..."
    sudo rm -rf /opt/zapret2
    sudo rm -f /opt/zapret2-ver
    sudo rm -f /bin/zapret2

    sudo rm -f /etc/systemd/system/zapret2.service
    sudo rm -f /etc/systemd/system/zapret2.service.d

    echo "Перезапуск демона systemd..."
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl reset-failed zapret2.service >/dev/null 2>&1 || true

    gum_notify success "Продукт $p успешно удален"
}
