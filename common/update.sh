#!/bin/bash

# common/update.sh — Update logic for installer, products, and configs

INSTALLER_DIR="/opt/zapret.installer"
INSTALLER_REPO="https://github.com/Dirold2/zapret.installerd2"

check_installer_update() {
    [ ! -d "$INSTALLER_DIR/.git" ] && { echo "not_git"; return 0; }

    git -C "$INSTALLER_DIR" fetch --quiet origin 2>/dev/null || { echo "noconnect"; return 0; }

    local behind
    behind=$(git -C "$INSTALLER_DIR" rev-list --count HEAD..@{u} 2>/dev/null \
        || git -C "$INSTALLER_DIR" rev-list --count HEAD..origin/main 2>/dev/null \
        || git -C "$INSTALLER_DIR" rev-list --count HEAD..origin/master 2>/dev/null \
        || echo "0")

    if [ "${behind:-0}" -gt 0 ]; then
        echo "$behind"
    else
        echo "current"
    fi
}

update_installer() {
    local istat
    istat=$(check_installer_update)

    case "$istat" in
        not_git)
            if gum_confirm "Клонировать установщик в $INSTALLER_DIR?"; then
                gum_spin "Клонирование..." "rm -rf $INSTALLER_DIR && git clone $INSTALLER_REPO $INSTALLER_DIR"
            fi
            ;;
        noconnect)
            gum_notify error "Нет соединения"
            ;;
        current)
            gum_notify info "Установщик актуален"
            ;;
        *)
            gum_spin "Обновление установщика..." "cd $INSTALLER_DIR && git pull --rebase || { cd / && rm -rf $INSTALLER_DIR && git clone $INSTALLER_REPO $INSTALLER_DIR; }"
            exec "$0" "$@"
            ;;
    esac
}

action_perform_updates() {
    local updated=false

    for p in "${PRODUCTS_LIST[@]}"; do
        is_product_installed "$p" || continue
        local status
        status=$(check_product_update "$p")

        case "$status" in
            current|git|not_installed|noconnect)
                continue
                ;;
            *)
                gum_notify info "Обновляю $p: $status..."
                product_use "$p" || continue
                main_update 2>&1 | gum_spin "Обновление $p..."
                updated=true
                ;;
        esac
    done

    if $updated; then
        gum_notify success "Обновление завершено"
    else
        ux_msg "Нечего обновлять"
    fi

    manage_service restart 2>/dev/null || true
}

update_configs() {
    if gum_confirm "Обновить конфиги из cfgs?"; then
        for p in "${PRODUCTS_LIST[@]}"; do
            local cfgs_dir="/opt/$p/zapret.cfgs"
            if [ -d "$cfgs_dir" ]; then
                gum_spin "Обновление конфигов для $p..." "git -C \"$cfgs_dir\" pull --ff-only 2>/dev/null || true"
            fi
        done
        gum_notify success "Конфиги обновлены"
    fi
}

check_all_updates() {
    local products_update=false has_product_updates=false has_installer_updates=false

    for p in "${PRODUCTS_LIST[@]}"; do
        is_product_installed "$p" || continue
        local status
        status=$(check_product_update "$p")
        local lv
        lv=$(cat "/opt/$p-ver" 2>/dev/null || echo "—")
        case "$status" in
            current)    gum style --foreground 2 "$p: актуально ($lv)" ;;
            git)        gum style --foreground 3 "$p: установлен из git" ;;
            noconnect)  gum style --foreground 1 "$p: ошибка проверки" ;;
            not_installed) ;;
            *)
                products_update=true
                has_product_updates=true
                gum style --foreground 1 "$p: $lv → $status"
                ;;
        esac
    done

    local installer_status
    installer_status=$(check_installer_update)
    case "$installer_status" in
        current|not_git)
            gum style --foreground 2 "установщик: актуально"
            ;;
        noconnect)
            gum style --foreground 1 "установщик: ошибка проверки"
            ;;
        *)
            gum style --foreground 1 "установщик: есть обновления (+$installer_status коммитов)"
            products_update=true
            has_installer_updates=true
            ;;
    esac

    echo
    if $products_update && gum_confirm "Установить обновления?"; then
        if $has_installer_updates; then
            gum_notify info "Обновляю установщик..."
            gum_spin "git pull..." "cd $INSTALLER_DIR && git pull --rebase || { cd / && rm -rf $INSTALLER_DIR && git clone $INSTALLER_REPO $INSTALLER_DIR; }"
        fi
        if $has_product_updates; then
            action_perform_updates
        fi
        if $has_installer_updates; then
            exec "$0" "$@"
        fi
        gum_notify success "Обновлений нет"
    fi
}

menu_update() {
    while true; do
        clear
        local act
        act="$(ui_choose_one "ОБНОВЛЕНИЕ" \
            "Проверить обновления" \
            "Обновить установщик" \
            "Обновить конфиги" \
            "Назад")" || return 0

        case "$act" in
            "Проверить обновления")
                print_header "Проверка обновлений" "info"
                check_all_updates
                pause
                ;;
            "Обновить установщик")
                update_installer
                pause
                ;;
            "Обновить конфиги")
                update_configs
                pause
                ;;
            "Назад") return 0 ;;
        esac
    done
}
