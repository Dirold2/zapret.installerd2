#!/bin/bash

gum_has() {
    command -v gum >/dev/null 2>&1
}

ux_confirm() {
    local prompt="$1"
    if gum_has; then
        gum confirm "$prompt"
        return $?
    fi
    echo "$prompt (y/N): "
    read -r ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

ux_choose_one() {
    local title="$1"
    shift
    if gum_has; then
        gum choose --header "$title" "$@"
        return $?
    fi
    echo "$title"
    local i=0
    for opt in "$@"; do
        i=$((i+1))
        echo "  $i) $opt"
    done
    echo "Введите номер: "
    read -r n
    i=0
    for opt in "$@"; do
        i=$((i+1))
        [ "$i" = "$n" ] && { echo "$opt"; return 0; }
    done
    return 1
}

ux_msg() {
    local msg="$1"
    if gum_has; then
        # Keep output compact: no heavy box drawing.
        gum style --padding "0 1" "$msg"
    else
        echo "$msg"
    fi
}

pause() {
    printf "\nНажмите Enter для возврата в меню..."
    read -r _ || true
}

