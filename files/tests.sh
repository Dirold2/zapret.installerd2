#!/usr/bin/env bash

require_cmd() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        gum_notify error "$cmd не найден в PATH"
        return 1
    fi

    return 0
}

get_strategy_name() {
    local strategy="unknown"

    if grep -q "discord" "$PRODUCT_CONFIG_FILE" 2>/dev/null; then
        strategy="DiscordFix"
    fi

    if grep -q "youtube" "$PRODUCT_CONFIG_FILE" 2>/dev/null; then
        strategy="$strategy + YouTubeFix"
    fi

    echo "$strategy"
}

action_show_strategy() {
    print_header "Текущая стратегия"

    local strategy
    strategy="$(get_strategy_name)"

    echo
    gum style --foreground 6 "Стратегия:"
    gum style --foreground 2 "$strategy"
    echo

    pause
}

action_run_tests() {
    print_header "Проверка конфигурации"

    require_cmd curl || {
        pause
        return 1
    }

    require_cmd grep || {
        pause
        return 1
    }

    echo
    gum style --foreground 6 "Проверка config..."
    echo

    if grep -qE "NFQWS_OPT|TPWS_OPT|MODE_FILTER" "$PRODUCT_CONFIG_FILE"; then
        gum_notify ok "config валиден"
    else
        gum_notify error "config выглядит повреждённым"
    fi

    echo

    gum style --foreground 6 "Проверка list..."
    echo

    if [ -s "$PRODUCT_LIST_FILE" ]; then
        gum_notify ok "hostlist найден"
    else
        gum_notify warn "hostlist пуст"
    fi

    echo

    gum style --foreground 6 "Проверка сервиса..."
    echo

    if service_is_active "$PRODUCT_SERVICE"; then
        gum_notify ok "$PRODUCT_SERVICE работает"
    else
        gum_notify error "$PRODUCT_SERVICE остановлен"
    fi

    echo

    local strategy
    strategy="$(get_strategy_name)"

    gum style --foreground 2 "Текущая стратегия: $strategy"

    echo
    pause
}