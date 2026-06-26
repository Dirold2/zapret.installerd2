#!/bin/bash

ux_confirm() {
    gum_confirm "$1"
}

ux_choose_one() {
    gum_choose_one "$@"
}

ux_msg() {
    local msg="$1"
    if $GUM_AVAILABLE; then
        gum style --padding "0 1" "$msg"
    else
        echo "$msg"
    fi
}

pause() {
    gum_pause "Нажмите Enter для возврата в меню..."
}

print_header() {
    local title="${1:-}"
    local style="${2:-normal}"

    if [[ -z "$title" ]]; then
        if [[ -n "${NAME:-}" ]]; then
            title="$NAME"
        else
            title="ZAPRET CONTROL"
        fi
    fi

    gum_header "$title" "" "$style"
}

resolve_config_path() {
    local input="$1"

    input="${input/#\~/$HOME}"
    input="$(realpath -m "$input" 2>/dev/null || echo "$input")"

    if [ -f "$input" ]; then
        printf '%s\n' "$input"
        return 0
    fi

    for ext in "" ".conf" ".config" ".txt"; do
        if [ -f "${input}${ext}" ]; then
            printf '%s\n' "${input}${ext}"
            return 0
        fi
    done

    if [ -d "$input" ]; then

        local candidate

        for candidate in \
            config \
            *.conf \
            *.config \
            *.txt; do

            [ -f "$input/$candidate" ] || continue

            printf '%s\n' "$input/$candidate"
            return 0
        done
    fi

    return 1
}

ui_path_input() {
    local title="$1"
    local result

    while true; do
        clear
        print_header "$title" "normal"

        echo
        gum style --foreground 240 \
            "TAB → автодополнение | Ctrl+C → отмена"
        echo

        read -erp "path> " result

        result="${result/#\~/$HOME}"

        [ -z "$result" ] && continue

        printf '%s\n' "$result"
        return 0
    done
}

ui_refresh_layout() {
    UI_COLS="$(tput cols 2>/dev/null || echo 0)"
    UI_LINES="$(tput lines 2>/dev/null || echo 0)"

    if [ "$UI_LINES" -le 20 ]; then
        UI_COMPACT=true
    else
        UI_COMPACT=false
    fi

    if [ "$UI_LINES" -ge 30 ]; then
        GUM_MENU_HEIGHT=14
    elif [ "$UI_LINES" -ge 24 ]; then
        GUM_MENU_HEIGHT=10
    elif [ "$UI_LINES" -ge 18 ]; then
        GUM_MENU_HEIGHT=7
    else
        GUM_MENU_HEIGHT=5
    fi

    UI_DIRTY=false
}

ui_maybe_refresh() { [ "$UI_DIRTY" = true ] && ui_refresh_layout; }

ui_hr() {
    gum style --foreground 240 "$(printf '─%.0s' $(seq 1 "${COLUMNS:-80}"))"
}

ui_choose_one() {
    local title="$1"; shift
    ui_maybe_refresh

    if $GUM_AVAILABLE; then
        gum choose \
            --header "$(ui_header | tr '\n' ' ')" \
            --height "$GUM_MENU_HEIGHT" \
            "$@"
    else
        local result
        result=$(gum_choose_one "$title" "$@")
        echo "$result"
        return $?
    fi
}

ui_header() {
    local status
    status="$(ui_products_status_line || true)"

    echo
    echo "$status"
    echo
}

print_header() {
    ui_maybe_refresh
    clear

    local title="${1:-${NAME:-ZAPRET_INSTALLER}}"
    local style="${2:-normal}"

    if [ "$UI_COMPACT" = true ]; then
        gum style --bold --foreground 8 " $title"
        return 0
    fi

    gum_header "$title" "" "$style" || true
}

notify_ok() { gum_notify ok "$1"; }
notify_info() { gum_notify info "$1"; }
notify_warn() { gum_notify warn "$1"; }
notify_err() { gum_notify err "$1"; }