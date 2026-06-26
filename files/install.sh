#!/bin/bash


remote_latest_version() {
    rver=$(timeout 10s curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | \
          grep "tag_name" | \
          cut -d '"' -f 4 | \
          sed 's/^v//')
}

get_latest_version() {
    if [ -z "$rver" ]; then
        rver=$(timeout 10s curl -s -I https://github.com/bol-van/zapret/releases/latest | grep -i "location:" | cut -d' ' -f2 | tr -d '\r' | grep -o "tag/v[0-9.]\+" | cut -d'/' -f2 | sed 's/^v//')
        if [ -z "$rver" ]; then
            #error_exit "не удалось определить последнюю версию запрета. Проверьте соединение с сетью."
            echo "Неизвестно"
        else
            echo "$rver"
        fi
    else
        echo "$rver"
    fi
}

#zapret_update_check()
#{
#    if cmp -s <(get_latest_version) /opt/zapret-ver; then 
#        echo -e "0"
#    else
#        echo -e "1"
#    fi
#
#}
download_zapret_release()
{

    rm -rf /opt/zapret
    rm -rf /opt/zapret-v$(get_latest_version)
    TEMP_DIR_BIN=$(mktemp -d)
    local download_url=""
    local tar_flags="-xzf $TEMP_DIR_BIN/latest.tar.gz -C /opt/"

    if [ "$SYSTEM" = "openwrt" ]; then
        download_url=$(curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | grep "browser_download_url.*openwrt.*tar.gz" | head -n 1 | cut -d '"' -f 4)
        tar_flags="-xzf $TEMP_DIR_BIN/latest.tar.gz -C /opt/ --strip-components=1"
    else
        download_url=$(curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | grep "browser_download_url.*tar.gz" | grep -v "openwrt" | head -n 1 | cut -d '"' -f 4)
    fi

    [ -z "$download_url" ] && { rm -rf "$TEMP_DIR_BIN"; return 1; }

    if ! curl -fL -o "$TEMP_DIR_BIN/latest.tar.gz" "$download_url"; then
        rm -rf "$TEMP_DIR_BIN"
        return 1
    fi

    if ! tar $tar_flags; then
        rm -rf "$TEMP_DIR_BIN" "/opt/zapret-v$(get_latest_version)"
        return 1
    fi
    mv "/opt/zapret-v$(get_latest_version)" /opt/zapret
    get_latest_version > /opt/zapret-ver
    echo "Клонирую репозиторий конфигураций..."
    git clone https://github.com/Snowy-Fluffy/zapret.cfgs /opt/zapret/zapret.cfgs || { echo "Не удалось клонировать конфиги"; return 1; }
    echo "Клонирование успешно завершено."

}

download_zapret_git() {
    rm -rf /opt/zapret
    echo "Клонирую репозиторий bol-van/zapret..."
    if ! git clone --depth 1 https://github.com/bol-van/zapret /opt/zapret; then
        echo "Не удалось клонировать zapret" >&2
        return 1
    fi
    echo "git" > /opt/zapret-ver
    echo "Клонирую репозиторий конфигураций..."
    if ! git clone --depth 1 https://github.com/Snowy-Fluffy/zapret.cfgs /opt/zapret/zapret.cfgs; then
        echo "Не удалось клонировать конфиги" >&2
        return 1
    fi
    echo "Клонирование успешно завершено."
}


install_dependencies() {
    kernel="$(uname -s)"
    if [ "$kernel" = "Linux" ]; then
        [ -f /etc/os-release ] || error_exit "Не найден /etc/os-release"
        . /etc/os-release

        case "${ID:-}" in
            arch|artix|cachyos|endeavouros|manjaro)   pacman -S --noconfirm --needed ipset ;;
            debian|ubuntu|mint|altlinux)               apt-get install -y iptables ipset ;;
            fedora|almalinux|rocky)                    dnf install -y iptables ipset ;;
            centos)                                    yum install -y ipset iptables ;;
            void)                                      xbps-install -y iptables ipset ;;
            gentoo)                                    emerge --noreplace net-firewall/iptables net-firewall/ipset ;;
            opensuse)                                  zypper install -y iptables ipset ;;
            openwrt)                                   opkg install iptables ipset ;;
            alpine)                                     apk add iptables ipset ;;
            *)
                for like in ${ID_LIKE:-}; do
                    case "$like" in
                        debian|ubuntu) apt-get install -y iptables ipset; break ;;
                        fedora|rhel)   dnf install -y iptables ipset; break ;;
                    esac
                done
                ;;
        esac
    elif [ "$kernel" = "Darwin" ]; then
        error_exit "macOS не поддерживается на данный момент."
    fi
}

install_zapret() {
    local method="${1:-release}"
    install_dependencies

    if [[ $dir_exists == true ]]; then
        read -p "Найден /opt/zapret. Удалить и продолжить? (y/N): " answer
        [[ "$answer" =~ ^[Yy] ]] || return 0

        if [[ -f /opt/zapret/uninstall_easy.sh ]]; then
            cd /opt/zapret
            sed -i '/ask_yes_no N/s/ask_yes_no N/ask_yes_no Y/' /opt/zapret/common/installer.sh
            yes "" | ./uninstall_easy.sh
            sed -i '/ask_yes_no Y/s/ask_yes_no Y/ask_yes_no N/' /opt/zapret/common/installer.sh
        fi
        rm -rf /opt/zapret
        cd /
        sleep 3
    fi

    if [ "$method" = "release" ]; then
        download_zapret_release || { warn "Релиз не удался"; return 1; }
    else
        download_zapret_git || { warn "Git clone не удался"; return 1; }
    fi

    cd /opt/zapret
    sed -i '/ask_yes_no N/s/ask_yes_no N/ask_yes_no Y/' /opt/zapret/common/installer.sh
    yes "" | ./install_easy.sh 2>/dev/null || true
    sed -i '/ask_yes_no Y/s/ask_yes_no Y/ask_yes_no N/' /opt/zapret/common/installer.sh

    rm -f /bin/zapret /opt/zapret/config /opt/zapret/ipset/zapret-hosts-user.txt

    cp -r /opt/zapret/zapret.cfgs/configurations/general /opt/zapret/config || error_exit "не удалось скопировать конфиг"
    cp -r /opt/zapret/zapret.cfgs/bin/* /opt/zapret/files/fake 2>/dev/null || true
    touch /opt/zapret/ipset/ipset-game.txt || true
    cp -r /opt/zapret/zapret.cfgs/lists/list-basic.txt /opt/zapret/ipset/zapret-hosts-user.txt || error_exit "не удалось скопировать хостлист"
    cp -r /opt/zapret/zapret.cfgs/lists/ipset-discord.txt /opt/zapret/ipset/ipset-discord.txt || true
    ln -sf /opt/zapret.installer/zapret-control.sh /bin/zapret || error_exit "не удалось создать симлинк"

    if [[ "$INIT_SYSTEM" = "systemd" ]]; then
        systemctl daemon-reload
    fi
    if [[ "$INIT_SYSTEM" = "runit" ]]; then
        read -p "Для завершения установки нужно перезагрузить устройство. Сделать это сейчас? (Y/n): " answer
        case "$answer" in
            [Yy]* | "") reboot ;;
            *) $TPUT_E; exit 1 ;;
        esac
    else
        manage_service restart 2>/dev/null || true
        configure_zapret_conf
    fi
}


update_zapret() {
    LIST_EXISTS=0
    CONF_EXISTS=0
    TEMP_DIR_CONF=$(mktemp -d)
    if [[ -f /opt/zapret/config ]]; then
        cp -r /opt/zapret/config $TEMP_DIR_CONF/config
        CONF_EXISTS=1
    fi
    if [[ -f /opt/zapret/ipset/zapret-hosts-user.txt ]]; then
        cp -r /opt/zapret/ipset/zapret-hosts-user.txt $TEMP_DIR_CONF/zapret-hosts-user.txt
        LIST_EXISTS=1
    fi 
    #if [ $(zapret_update_check) = 0 ]; then
    #    echo "Актуальная версия уже установлена: нечего обновлять." 
    #    bash -c 'read -p "Нажмите Enter для продолжения..."' 
    
    local ver_content
    ver_content=$(cat /opt/zapret-ver 2>/dev/null || echo "")

    if [ -z "$ver_content" ] || [ "$ver_content" != "git" ]; then
        download_zapret_release || download_zapret_git || error_exit "не удалось обновить запрет"
        echo "Запрет обновлен до версии $(cat /opt/zapret-ver)"
    else
        cd /opt/zapret && git fetch origin && git checkout -B master origin/master && git reset --hard origin/master || error_exit "не удалось обновить zapret с помощью git. Попробуйте снова, вероятно это сетевая ошибка. Если не помогло - переустановите zapret."
        echo "Репозиторий запрета был обновлен."
    fi

    local zapret_cfgs_dir="/opt/zapret/zapret.cfgs"
    if [ -d "$zapret_cfgs_dir" ]; then
        git -C "$zapret_cfgs_dir" fetch origin && git -C "$zapret_cfgs_dir" checkout -B main origin/main && git -C "$zapret_cfgs_dir" reset --hard origin/main
    fi
    if [ -d /opt/zapret.installer ]; then
        git -C /opt/zapret.installer fetch origin && git -C /opt/zapret.installer checkout -B main origin/main && git -C /opt/zapret.installer reset --hard origin/main
        rm -f /bin/zapret
        ln -sf /opt/zapret.installer/zapret-control.sh /bin/zapret || error_exit "не удалось создать символическую ссылку"
    fi
    if [ "$CONF_EXISTS" = 1 ]; then
        rm -f /opt/zapret/config
        mv "$TEMP_DIR_CONF/config" /opt/zapret/config
    fi
    if [ "$LIST_EXISTS" = 1 ]; then
        rm -f /opt/zapret/ipset/zapret-hosts-user.txt
        mv "$TEMP_DIR_CONF/zapret-hosts-user.txt" /opt/zapret/ipset/zapret-hosts-user.txt
    fi
    rm -rf "$TEMP_DIR_CONF"
    rm -rf "${TEMP_DIR_BIN:-}"

    if [ "$CONF_EXISTS" = 0 ]; then
        cp -r "$zapret_cfgs_dir/configurations/general" /opt/zapret/config || error_exit "не удалось скопировать конфиг"
    fi
    if [ "$LIST_EXISTS" = 0 ]; then
        cp -r "$zapret_cfgs_dir/lists/list-basic.txt" /opt/zapret/ipset/zapret-hosts-user.txt || error_exit "не удалось скопировать хостлист"
    fi
    cp -r "$zapret_cfgs_dir/bin/"* /opt/zapret/files/fake/ 2>/dev/null || true
    touch /opt/zapret/ipset/ipset-game.txt 2>/dev/null || true
    cp -r "$zapret_cfgs_dir/lists/ipset-discord.txt" /opt/zapret/ipset/ipset-discord.txt 2>/dev/null || true
    configure_zapret_conf
    manage_service restart
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

update_script() {
    local cfgs_dir="/opt/zapret/zapret.cfgs"

    if [ -d "$cfgs_dir" ]; then
        git -C "$cfgs_dir" fetch origin && git -C "$cfgs_dir" checkout -B main origin/main && git -C "$cfgs_dir" reset --hard origin/main
    fi
    if [ -d /opt/zapret.installer ]; then
        git -C /opt/zapret.installer fetch origin && git -C /opt/zapret.installer checkout -B main origin/main && git -C /opt/zapret.installer reset --hard origin/main
    fi
    rm -f /bin/zapret
    ln -sf /opt/zapret.installer/zapret-control.sh /bin/zapret || error_exit "не удалось создать символическую ссылку"
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

update_installed_script() {
    local cfgs_dir="/opt/zapret/zapret.cfgs"

    if [ -d "$cfgs_dir" ]; then
        git -C "$cfgs_dir" fetch origin && git -C "$cfgs_dir" checkout -B main origin/main && git -C "$cfgs_dir" reset --hard origin/main
    fi
    if [ -d /opt/zapret.installer ]; then
        git -C /opt/zapret.installer fetch origin && git -C /opt/zapret.installer checkout -B main origin/main && git -C /opt/zapret.installer reset --hard origin/main
        rm -f /bin/zapret
        ln -sf /opt/zapret.installer/zapret-control.sh /bin/zapret || error_exit "не удалось создать символическую ссылку"
        manage_service restart 2>/dev/null || true
    fi
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

uninstall_zapret() {
    read -p "Вы действительно хотите удалить zapret? (y/N): " answer
    case "$answer" in
        [Yy]* )
            if [[ -f /opt/zapret/uninstall_easy.sh ]]; then
                cd /opt/zapret
                yes "" | ./uninstall_easy.sh 2>/dev/null || true
            fi
            rm -rf /opt/zapret
            rm -rf /opt/zapret.installer/
            rm -f /bin/zapret
            rm -f /opt/zapret-ver
            echo "Запрос удален"
            $TPUT_E
            exit
            ;;
    esac
} 