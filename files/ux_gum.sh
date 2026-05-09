#!/bin/bash

# ux_gum.sh - UI функции с использованием gum_utils.sh
# Этот файл обеспечивает обратную совместимость со старым кодом

# Обертки для обратной совместимости
ux_confirm() {
    gum_confirm "$1"
}

ux_choose_one() {
    local title="$1"
    shift
    gum choose --header "$title" "$@"
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

# Улучшенная функция заголовка
print_header() {
    local title="${1:-}"
    local style="${2:-normal}"

    # Если заголовок не передан, используем дефолтный
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

    # Если это уже файл
    if [ -f "$input" ]; then
        printf '%s\n' "$input"
        return 0
    fi

    # Популярные расширения
    for ext in "" ".conf" ".config" ".txt"; do
        if [ -f "${input}${ext}" ]; then
            printf '%s\n' "${input}${ext}"
            return 0
        fi
    done

    # Если это директория
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

# Быстрые уведомления
notify_ok() { gum_notify ok "$1"; }
notify_info() { gum_notify info "$1"; }
notify_warn() { gum_notify warn "$1"; }
notify_err() { gum_notify err "$1"; }