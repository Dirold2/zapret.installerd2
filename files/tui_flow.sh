#!/bin/bash

# Pure UI flow built on files/tui.sh, calling existing business actions.

tui_screen_logs() {
    state_load >/dev/null 2>&1 || true
    tui_pause_screen "Логи и состояние" "Логи:
  $(state_log_path)

Состояние:
  $STATE_FILE

Backups:
  $BACKUP_ROOT"
}

tui_screen_compare() {
    tui_pause_screen "Сравнение режимов" "$(screen_compare_modes)"
}

tui_screen_hostlists_check() {
    local body=""
    for p in zapret zapret2; do
        product_use "$p" >/dev/null 2>&1 || continue
        body="${body}${p}:\n"
        body="${body}  list:    ${PRODUCT_LIST_FILE}  $([ -f "$PRODUCT_LIST_FILE" ] && echo OK || echo MISSING)\n"
        body="${body}  exclude: ${PRODUCT_EXCLUDE_FILE}  $([ -f "$PRODUCT_EXCLUDE_FILE" ] && echo OK || echo MISSING)\n"
        if [ "$p" = "zapret" ]; then
            local d="$PRODUCT_DIR/ipset/ipset-discord.txt"
            body="${body}  discord: ${d}  $([ -f "$d" ] && echo OK || echo MISSING)\n"
        fi
        body="${body}\n"
    done
    tui_pause_screen "Проверка hostlist-файлов" "$(printf "%b" "$body")"
}

tui_action_install() {
    # choose mode
    local sel=1
    local opts=("только zapret" "только zapret2" "оба (изолированно)" "назад")
    while true; do
        tui_clear; tui_draw_header; tui_draw_dashboard_cards
        tui_draw_menu_group "Установка"
        tui_draw_menu_items "$sel" "${opts[@]}"
        tui_footer_bar
        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#opts[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#opts[@]} ] && sel=1 ;;
            esc|back) return 0 ;;
            q) return 2 ;;
            enter)
                case "$sel" in
                    1) INSTALL_MODE="zapret" ;;
                    2) INSTALL_MODE="zapret2" ;;
                    3) INSTALL_MODE="both" ;;
                    4) return 0 ;;
                esac
                ACTIVE_PRODUCT="$INSTALL_MODE"
                state_save >/dev/null 2>&1 || true
                local details="Режим: $INSTALL_MODE\n"
                details="${details}\nБудет установлено:\n"
                if [ "$INSTALL_MODE" = "zapret" ] || [ "$INSTALL_MODE" = "both" ]; then
                    product_use zapret >/dev/null 2>&1 && details="${details}  - zapret в ${PRODUCT_DIR}\n"
                fi
                if [ "$INSTALL_MODE" = "zapret2" ] || [ "$INSTALL_MODE" = "both" ]; then
                    product_use zapret2 >/dev/null 2>&1 && details="${details}  - zapret2 в ${PRODUCT_DIR}\n"
                fi
                if tui_confirm_screen "Подтверждение установки" "Это изменит файлы в /opt и может перезапустить сервисы." "$(printf "%b" "$details")"; then
                    case "$INSTALL_MODE" in
                        zapret) product_use zapret && product_install_default ;;
                        zapret2) product_use zapret2 && product_install_default ;;
                        both) product_use zapret && product_install_default; product_use zapret2 && product_install_default ;;
                    esac
                    tui_pause_screen "Готово" "Установка завершена (если не было ошибок)."
                fi
                return 0
                ;;
        esac
    done
}

tui_action_switch_mode() {
    local sel=1
    local opts=("zapret" "zapret2" "both" "назад")
    while true; do
        tui_clear; tui_draw_header; tui_draw_dashboard_cards
        tui_draw_menu_group "Переключение режима"
        tui_draw_menu_items "$sel" "${opts[@]}"
        tui_footer_bar
        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#opts[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#opts[@]} ] && sel=1 ;;
            esc|back) return 0 ;;
            q) return 2 ;;
            enter)
                [ "$sel" -eq 4 ] && return 0
                INSTALL_MODE="${opts[$((sel-1))]}"
                ACTIVE_PRODUCT="$INSTALL_MODE"
                backup_begin >/dev/null 2>&1 || true
                backup_path "$STATE_FILE" >/dev/null 2>&1 || true
                state_save >/dev/null 2>&1 || true
                tui_pause_screen "Режим сохранён" "Новый режим: $INSTALL_MODE\n\n$(backup_done_msg)"
                return 0
                ;;
        esac
    done
}

tui_manage_product_menu() {
    local sel=1
    local opts=("zapret" "zapret2" "назад")
    while true; do
        tui_clear; tui_draw_header; tui_draw_dashboard_cards
        tui_draw_menu_group "Управление"
        tui_draw_menu_items "$sel" "${opts[@]}"
        tui_footer_bar
        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#opts[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#opts[@]} ] && sel=1 ;;
            esc|back) return 0 ;;
            q) return 2 ;;
            enter)
                [ "$sel" -eq 3 ] && return 0
                product_use "${opts[$((sel-1))]}" || return 0
                tui_manage_product_actions
                ;;
        esac
    done
}

tui_manage_product_actions() {
    local sel=1
    local opts=("Статус" "Запустить" "Остановить" "Перезапустить" "Автозагрузка: вкл" "Автозагрузка: выкл" "Пути конфигов" "Редактировать config" "Редактировать list" "Редактировать exclude" "назад")
    while true; do
        tui_clear; tui_draw_header
        tui_status_card
        tui_hr
        tui_draw_menu_items "$sel" "${opts[@]}"
        tui_footer_bar
        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#opts[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#opts[@]} ] && sel=1 ;;
            esc|back) return 0 ;;
            q) return 2 ;;
            enter)
                case "$sel" in
                    1) tui_pause_screen "Статус" "$(action_show_status 2>&1)" ;;
                    2) ensure_hostlist_files >/dev/null 2>&1 || true; action_start >/dev/null 2>&1; tui_pause_screen "Готово" "Запуск выполнен." ;;
                    3) action_stop >/dev/null 2>&1; tui_pause_screen "Готово" "Остановка выполнена." ;;
                    4) ensure_hostlist_files >/dev/null 2>&1 || true; action_restart >/dev/null 2>&1; tui_pause_screen "Готово" "Перезапуск выполнен." ;;
                    5) action_enable; tui_pause_screen "Готово" "Автозагрузка включена (если поддерживается init)." ;;
                    6) action_disable; tui_pause_screen "Готово" "Автозагрузка выключена (если поддерживается init)." ;;
                    7) tui_pause_screen "Пути конфигов" "$(action_show_config_paths)" ;;
                    8) tui_deinit; open_editor "$PRODUCT_CONFIG_FILE"; tui_init ;;
                    9) tui_deinit; open_editor "$PRODUCT_LIST_FILE"; tui_init ;;
                    10) tui_deinit; open_editor "$PRODUCT_EXCLUDE_FILE"; tui_init ;;
                    11) return 0 ;;
                esac
                ;;
        esac
    done
}

tui_action_repair_units() {
    product_use zapret2 >/dev/null 2>&1 || return 0
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        tui_pause_screen "Repair units" "Только для systemd."
        return 0
    fi
    if tui_confirm_screen "Repair systemd units" "Будут перезаписаны файлы /etc/systemd/system/zapret2*.{service,timer}" "Продукт: zapret2\nФайлы:\n  zapret2.service\n  zapret2-list-update.service\n  zapret2-list-update.timer"; then
        systemd_install_product_units >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable zapret2.service >/dev/null 2>&1 || true
        systemctl enable zapret2-list-update.timer >/dev/null 2>&1 || true
        tui_pause_screen "Готово" "Units для zapret2 обновлены."
    fi
}

tui_action_uninstall() {
    local sel=1
    local opts=("zapret" "zapret2" "назад")
    while true; do
        tui_clear; tui_draw_header; tui_draw_dashboard_cards
        tui_draw_menu_group "Опасные действия"
        tui_draw_menu_items "$sel" "${opts[@]}"
        tui_footer_bar
        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#opts[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#opts[@]} ] && sel=1 ;;
            esc|back) return 0 ;;
            q) return 2 ;;
            enter)
                [ "$sel" -eq 3 ] && return 0
                product_use "${opts[$((sel-1))]}" || return 0
                local details="Будет удалено:\n  каталог: $PRODUCT_DIR\n  ссылка:  $PRODUCT_BINLINK\n  верcия:  $PRODUCT_VER_FILE\n\nBackup будет создан в:\n  $BACKUP_ROOT/<timestamp>"
                if tui_confirm_screen "Удаление ${PRODUCT_ID}" "Опасно: действие необратимо без backup." "$(printf "%b" "$details")"; then
                    action_uninstall_soft >/dev/null 2>&1 || true
                    tui_pause_screen "Готово" "Удаление выполнено.\n$(backup_done_msg)"
                fi
                return 0
                ;;
        esac
    done
}

main_menu_tui() {
    tui_is_tty || return 1
    ensure_gum_best_effort >/dev/null 2>&1 || true
    tui_init
    trap 'tui_deinit; exit 0' INT TERM

    local sel=1
    local items=(
        "Установка"
        "Управление"
        "Проверка"
        "Логи"
        "Опасные действия"
        "Выход"
    )

    while true; do
        tui_clear
        tui_draw_header
        tui_draw_dashboard_cards

        tui_draw_menu_items "$sel" "${items[@]}"
        tui_footer_bar

        case "$(tui_read_key)" in
            up) sel=$((sel-1)); [ "$sel" -lt 1 ] && sel=${#items[@]} ;;
            down) sel=$((sel+1)); [ "$sel" -gt ${#items[@]} ] && sel=1 ;;
            q) tui_deinit; return 0 ;;
            esc|back) : ;;
            enter)
                case "$sel" in
                    1) tui_action_install || { tui_deinit; return 0; } ;;
                    2) tui_manage_product_menu || { tui_deinit; return 0; } ;;
                    3)
                        # “Проверка” submenu (short)
                        local s2=1
                        local o2=("Проверка hostlists" "Repair units (zapret2)" "Сравнение режимов" "назад")
                        while true; do
                            tui_clear; tui_draw_header; tui_draw_dashboard_cards
                            tui_draw_menu_group "Проверка"
                            tui_draw_menu_items "$s2" "${o2[@]}"
                            tui_footer_bar
                            case "$(tui_read_key)" in
                                up) s2=$((s2-1)); [ "$s2" -lt 1 ] && s2=${#o2[@]} ;;
                                down) s2=$((s2+1)); [ "$s2" -gt ${#o2[@]} ] && s2=1 ;;
                                esc|back) break ;;
                                q) tui_deinit; return 0 ;;
                                enter)
                                    case "$s2" in
                                        1) tui_screen_hostlists_check ;;
                                        2) tui_action_repair_units ;;
                                        3) tui_screen_compare ;;
                                        4) break ;;
                                    esac
                                    ;;
                            esac
                        done
                        ;;
                    4) tui_screen_logs ;;
                    5) tui_action_uninstall || { tui_deinit; return 0; } ;;
                    6) tui_deinit; return 0 ;;
                esac
                ;;
        esac
    done
}

