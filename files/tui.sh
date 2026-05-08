#!/bin/bash

# Minimal dashboard-style TUI (no gum required)
# Controls: ↑/↓ navigate, Enter select, Esc/Back go back, Q quit.

tui_is_tty() {
    [ -t 0 ] && [ -t 1 ]
}

tui_cols() { tput cols 2>/dev/null || echo 80; }
tui_lines() { tput lines 2>/dev/null || echo 24; }

tui_has_color() {
    [ -t 1 ] || return 1
    local c
    c="$(tput colors 2>/dev/null || echo 0)"
    [ "$c" -ge 8 ]
}

tui_c_reset="\033[0m"
tui_c_dim="\033[2m"
tui_c_bold="\033[1m"
tui_c_red="\033[31m"
tui_c_green="\033[32m"
tui_c_yellow="\033[33m"
tui_c_blue="\033[34m"
tui_c_mag="\033[35m"
tui_c_cyan="\033[36m"
tui_c_gray="\033[90m"
tui_bg_sel="\033[48;5;236m"

tui_set_plain_palette() {
    tui_c_reset=""
    tui_c_dim=""
    tui_c_bold=""
    tui_c_red=""
    tui_c_green=""
    tui_c_yellow=""
    tui_c_blue=""
    tui_c_mag=""
    tui_c_cyan=""
    tui_c_gray=""
    tui_bg_sel=""
}

tui_init() {
    tui_has_color || tui_set_plain_palette
    stty -echo 2>/dev/null || true
}

tui_deinit() {
    stty echo 2>/dev/null || true
}

tui_clear() {
    clear
}

tui_hr() {
    local cols
    cols="$(tui_cols)"
    printf "%*s\n" "$cols" "" | tr ' ' '─'
}

tui_pad_right() {
    local s="$1" w="$2"
    printf "%-*s" "$w" "$s"
}

tui_center() {
    local s="$1" cols
    cols="$(tui_cols)"
    local len="${#s}"
    local pad=$(( (cols - len) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%*s%s\n" "$pad" "" "$s"
}

tui_footer_bar() {
    local cols
    cols="$(tui_cols)"
    printf "%s" "${tui_c_dim}"
    printf "%*s\r" "$cols" ""
    printf "  ↑↓ навигация   Enter выбрать   Esc/Back назад   Q выход"
    printf "%s\n" "${tui_c_reset}"
}

tui_read_key() {
    # Prints one token: up/down/enter/esc/back/q/other
    local k
    IFS= read -rsn1 k || { echo other; return 0; }
    case "$k" in
        "") echo enter ;;
        $'\x1b')
            # arrows or esc
            local rest
            IFS= read -rsn2 -t 0.01 rest 2>/dev/null || rest=""
            case "$rest" in
                "[A") echo up ;;
                "[B") echo down ;;
                "") echo esc ;;
                *) echo esc ;;
            esac
            ;;
        q|Q) echo q ;;
        b|B) echo back ;;
        *) echo other ;;
    esac
}

tui_draw_header() {
    state_load >/dev/null 2>&1 || true
    local mode="${INSTALL_MODE:-zapret}"
    local status="готов"
    # lightweight "needs attention" marker: missing hostlists for installed products
    local warn=0
    for p in zapret zapret2; do
        product_use "$p" >/dev/null 2>&1 || continue
        if [ -d "$PRODUCT_DIR" ] && [ -d "$PRODUCT_DIR/binaries" ]; then
            [ -f "$PRODUCT_LIST_FILE" ] || warn=1
            [ -f "$PRODUCT_EXCLUDE_FILE" ] || warn=1
        fi
    done
    [ "$warn" -eq 1 ] && status="нужна проверка"

    local cols
    cols="$(tui_cols)"
    local left="${tui_c_bold}${tui_c_cyan}zapret.installer${tui_c_reset}"
    local mid="режим: ${tui_c_bold}${tui_c_yellow}${mode}${tui_c_reset}"
    local right="статус: ${tui_c_bold}${tui_c_green}${status}${tui_c_reset}"
    [ "$status" = "нужна проверка" ] && right="статус: ${tui_c_bold}${tui_c_yellow}${status}${tui_c_reset}"
    local hint="${tui_c_dim}zapret / zapret2 / оба${tui_c_reset}"

    printf "%s  %s  %s\n" "$left" "$mid" "$right"
    printf "%s\n" "$hint"
    tui_hr
}

tui_bool_badge() {
    local v="$1" good="$2" bad="$3"
    if [ "$v" = "yes" ]; then
        printf "%s%s%s" "${tui_c_green}" "$good" "${tui_c_reset}"
    else
        printf "%s%s%s" "${tui_c_gray}" "$bad" "${tui_c_reset}"
    fi
}

tui_status_card() {
    # Uses current PRODUCT_* context
    local active="no" enabled="no" installed="no"
    [ -d "$PRODUCT_DIR" ] && installed="yes"
    service_is_active "$PRODUCT_SERVICE" && active="yes"
    service_is_enabled "$PRODUCT_SERVICE" && enabled="yes"

    local title="${tui_c_bold}${PRODUCT_ID}${tui_c_reset}"
    printf "%s\n" "$title"
    printf "  каталог:   %s\n" "${tui_c_dim}${PRODUCT_DIR}${tui_c_reset}"
    printf "  сервис:    %s\n" "${tui_c_dim}${PRODUCT_SERVICE}${tui_c_reset}"
    printf "  состояние: %s   автозапуск: %s   установлено: %s\n" \
        "$(tui_bool_badge "$active" "активно" "неактивно")" \
        "$(tui_bool_badge "$enabled" "вкл" "выкл")" \
        "$(tui_bool_badge "$installed" "да" "нет")"
}

tui_draw_dashboard_cards() {
    # Compact 2 cards one after another (no heavy boxes)
    product_use zapret >/dev/null 2>&1 && tui_status_card
    echo ""
    product_use zapret2 >/dev/null 2>&1 && tui_status_card
    tui_hr
}

tui_draw_menu_group() {
    local title="$1"
    printf "%s%s%s\n" "${tui_c_dim}" "$title" "${tui_c_reset}"
}

tui_draw_menu_items() {
    # args: selected_index, then N item labels
    local sel="$1"; shift
    local i=0
    for item in "$@"; do
        i=$((i+1))
        if [ "$i" -eq "$sel" ]; then
            printf " %s%s●%s %s%s%s\n" "$tui_bg_sel" "$tui_c_bold" "$tui_c_reset" "$tui_bg_sel" "$item" "$tui_c_reset"
        else
            printf "  %s◯%s %s\n" "${tui_c_gray}" "${tui_c_reset}" "$item"
        fi
    done
}

tui_confirm_screen() {
    # args: title, warning, details (multi-line ok)
    local title="$1" warn="$2" details="$3"
    local sel=2 # default No
    while true; do
        tui_clear
        tui_draw_header
        printf "%s%s%s\n" "${tui_c_bold}${tui_c_red}" "$title" "${tui_c_reset}"
        printf "%s%s%s\n\n" "${tui_c_yellow}" "$warn" "${tui_c_reset}"
        printf "%s\n" "$details"
        echo ""
        tui_draw_menu_items "$sel" "ДА, продолжить" "НЕТ, отмена"
        tui_footer_bar
        case "$(tui_read_key)" in
            up|down)
                if [ "$sel" -eq 1 ]; then sel=2; else sel=1; fi
                ;;
            enter)
                [ "$sel" -eq 1 ] && return 0
                return 1
                ;;
            esc|back) return 1 ;;
            q) return 2 ;;
        esac
    done
}

tui_pause_screen() {
    # args: title, body
    local title="$1" body="$2"
    tui_clear
    tui_draw_header
    [ -n "$title" ] && printf "%s%s%s\n\n" "${tui_c_bold}${tui_c_blue}" "$title" "${tui_c_reset}"
    printf "%s\n" "$body"
    echo ""
    printf "%sНажмите Enter чтобы вернуться...%s\n" "${tui_c_dim}" "${tui_c_reset}"
    while true; do
        case "$(tui_read_key)" in
            enter|esc|back) return 0 ;;
            q) return 2 ;;
        esac
    done
}

