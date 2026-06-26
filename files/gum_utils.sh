#!/bin/bash
# gum_utils.sh - Расширенные утилиты для красивого TUI с gum (fallback на стандартные средства)

GUM_AVAILABLE=false

# Инициализация gum (best effort)
gum_init() {
    if command -v gum >/dev/null 2>&1; then
        GUM_AVAILABLE=true
        return 0
    fi

    echo "==> Инструмент 'gum' не найден. Он необходим для работы интерфейса."
    read -p "Попробовать установить его автоматически? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ && ! -z $REPLY ]]; then
        GUM_AVAILABLE=false
        return 1
    fi

    local SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
        elif command -v doas >/dev/null 2>&1; then SUDO="doas"
        fi
    fi

    [ -f /etc/os-release ] && . /etc/os-release
    
    echo "Подготовка к установке gum для $ID..."

    case "${ID:-}" in
        debian|ubuntu|mint)
            $SUDO mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list >/dev/null

            if $SUDO apt-get update && $SUDO apt-get install -y gum; then
                :
            else
                echo "⚠️ Установка через repo.charm.sh не удалась, пробую go install..."
                install_gum_with_go || return 1
            fi
            ;;

        fedora|almalinux|rocky|rhel|centos|oracle|redos)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | $SUDO tee /etc/yum.repos.d/charm.repo
            $SUDO rpm --import https://repo.charm.sh/yum/gpg.key
            if command -v dnf >/dev/null 2>&1; then
                $SUDO dnf install -y gum
            else
                $SUDO yum install -y gum
            fi
            ;;

        opensuse*|suse)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | $SUDO tee /etc/zypp/repos.d/charm.repo
            $SUDO rpm --import https://repo.charm.sh/yum/gpg.key
            $SUDO zypper refresh
            $SUDO zypper install -y gum
            ;;

        arch|artix|cachyos|endeavouros|manjaro|garuda)
            $SUDO pacman -Sy --noconfirm --needed gum
            ;;

        alpine)
            $SUDO apk add gum
            ;;

        freebsd)
            $SUDO pkg install gum
            ;;

        *)
            # Если Brew установлен на Linux
            if command -v brew >/dev/null 2>&1; then
                brew install gum
            else
                echo "✖ ОС '$ID' не поддерживается автоматически."
                return 1
            fi
            ;;
    esac

    if command -v gum >/dev/null 2>&1; then
        echo "✔ Gum успешно установлен!"
        GUM_AVAILABLE=true
    else
        echo "✖ Ошибка при установке gum."
        GUM_AVAILABLE=false
        return 1
    fi
}

install_gum_with_go() {
    if ! command -v go >/dev/null 2>&1; then
        echo "✖ Go не установлен, не могу поставить gum через go install."
        return 1
    fi

    export GOBIN="${GOBIN:-$HOME/go/bin}"
    mkdir -p "$GOBIN"

    if go install github.com/charmbracelet/gum@latest; then
        export PATH="$GOBIN:$PATH"
        if command -v gum >/dev/null 2>&1; then
            echo "✔ Gum успешно установлен через Go!"
            return 0
        fi
    fi

    echo "✖ Не удалось установить gum через Go."
    return 1
}

# ============================================================================
# Цвета и стили
# ============================================================================

COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_MAGENTA="\033[35m"
COLOR_CYAN="\033[36m"
COLOR_WHITE="\033[37m"
COLOR_BOLD="\033[1m"
COLOR_RESET="\033[0m"

# ============================================================================
# Уведомления (Toast/Notify)
# ============================================================================

gum_notify() {
    local level="$1"
    shift
    local msg="$*"

    if $GUM_AVAILABLE; then
        case "$level" in
            ok|success)
                gum style --foreground "#4CAF50" "✓ $msg"
                ;;
            info)
                gum style --foreground "#2196F3" "ℹ $msg"
                ;;
            warn|warning)
                gum style --foreground "#FFC107" "⚠ $msg"
                ;;
            err|error)
                gum style --foreground "#F44336" "✗ $msg"
                ;;
            *)
                echo "$msg"
                ;;
        esac
    else
        case "$level" in
            ok|success)
                echo -e "${COLOR_GREEN}[✓]${COLOR_RESET} $msg"
                ;;
            info)
                echo -e "${COLOR_BLUE}[ℹ]${COLOR_RESET} $msg"
                ;;
            warn|warning)
                echo -e "${COLOR_YELLOW}[⚠]${COLOR_RESET} $msg"
                ;;
            err|error)
                echo -e "${COLOR_RED}[✗]${COLOR_RESET} $msg" >&2
                ;;
            *)
                echo "$msg"
                ;;
        esac
    fi
}

# ============================================================================
# Заголовки (Headers)
# ============================================================================

gum_header() {
    local title="${1:-}"
    local subtitle="${2:-}"
    local style="${3:-normal}"

    local border_color="default"
    local text_color=""

    case "$style" in
        error|danger|red)
            border_color="#F44336"
            text_color="--foreground #F44336"
            ;;
        success|ok|green)
            border_color="#4CAF50"
            text_color="--foreground #4CAF50"
            ;;
        warning|warn|yellow)
            border_color="#FFC107"
            text_color="--foreground #FFC107"
            ;;
        info|blue)
            border_color="#2196F3"
            text_color="--foreground #2196F3"
            ;;
        accent|magenta)
            border_color="#E91E63"
            text_color="--foreground #E91E63"
            ;;
        normal|*)
            border_color="#607D8B"
            ;;
    esac

    if $GUM_AVAILABLE; then
        local content="$title"
        [ -n "$subtitle" ] && content="$title"$'\n'"$subtitle"

        if [ -n "$text_color" ]; then
            gum style \
                --border rounded \
                --border-foreground "$border_color" \
                $text_color \
                --bold \
                --padding "1 4" \
                --margin "1 2" \
                --align center \
                "$content"
        else
            gum style \
                --border rounded \
                --border-foreground "$border_color" \
                --padding "1 4" \
                --margin "1 2" \
                --align center \
                "$content"
        fi
    else
        echo ""
        echo -e "${COLOR_BOLD}${COLOR_CYAN}╔══════════════════════════════════════════════════╗${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_CYAN}║${COLOR_RESET} $(printf '%-45s' "$title") ${COLOR_BOLD}${COLOR_CYAN}║${COLOR_RESET}"
        [ -n "$subtitle" ] && echo -e "${COLOR_BOLD}${COLOR_CYAN}║${COLOR_RESET} $(printf '%-45s' "$subtitle") ${COLOR_BOLD}${COLOR_CYAN}║${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_CYAN}╚══════════════════════════════════════════════════╝${COLOR_RESET}"
        echo ""
    fi
}

# ============================================================================
# Разделители (Dividers)
# ============================================================================

gum_divider() {
    local text="${1:-}"

    if $GUM_AVAILABLE; then
        if [ -n "$text" ]; then
            gum rule --color "#607D8B" --title "$text"
        else
            gum rule --color "#607D8B"
        fi
    else
        if [ -n "$text" ]; then
            echo -e "${COLOR_CYAN}───────────── $text ─────────────${COLOR_RESET}"
        else
            echo -e "${COLOR_CYAN}─────────────────────────────────${COLOR_RESET}"
        fi
    fi
}

# ============================================================================
# Подтверждения (Confirm)
# ============================================================================

gum_confirm() {
    local prompt="$1"

    stty sane 2>/dev/null || true

    if $GUM_AVAILABLE; then
        gum confirm --prompt.foreground="#2196F3" "$prompt" && return 0 || return $?
    else
        echo -e "${COLOR_CYAN}$prompt${COLOR_RESET} (y/N): "
        read -r ans
        case "$ans" in
            y|Y|yes|YES) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# ============================================================================
# Выбор одного варианта (Single Select)
# ============================================================================

gum_choose_one() {
    local title="$1"
    shift
    local options=("$@")

    if $GUM_AVAILABLE; then
        local result
        result=$(gum choose \
            --header "$title" \
            --header.foreground="#2196F3" \
            --selected.foreground="#4CAF50" \
            --selected.background="#1B5E20" \
            --cursor.foreground="#E91E63" \
            --limit 1 \
            "${options[@]}")
        echo "$result"
        return $?
    else
        echo -e "${COLOR_BOLD}${COLOR_CYAN}$title${COLOR_RESET}"
        local i=0
        for opt in "${options[@]}"; do
            i=$((i+1))
            echo -e "  ${COLOR_BOLD}${COLOR_BLUE}$i)${COLOR_RESET} $opt"
        done
        echo ""
        echo -n "Введите номер: "
        read -r n
        i=0
        for opt in "${options[@]}"; do
            i=$((i+1))
            if [ "$i" = "$n" ]; then
                echo "$opt"
                return 0
            fi
        done
        return 1
    fi
}

# ============================================================================
# Множественный выбор (Multi Select)
# ============================================================================

gum_choose_many() {
    local title="$1"
    shift
    local options=("$@")

    if $GUM_AVAILABLE; then
        gum choose \
            --header "$title" \
            --header.foreground="#2196F3" \
            --selected.foreground="#4CAF50" \
            --selected.background="#1B5E20" \
            --cursor.foreground="#E91E63" \
            --no-limit \
            "${options[@]}"
    else
        echo -e "${COLOR_BOLD}${COLOR_CYAN}$title${COLOR_RESET}"
        echo "(введите номера через пробел, например: 1 3 5)"
        local i=0
        for opt in "${options[@]}"; do
            i=$((i+1))
            echo -e "  ${COLOR_BOLD}${COLOR_BLUE}$i)${COLOR_RESET} $opt"
        done
        echo ""
        echo -n "Введите номера: "
        read -r selections
        local result=()
        for sel in $selections; do
            i=0
            for opt in "${options[@]}"; do
                i=$((i+1))
                if [ "$i" = "$sel" ]; then
                    result+=("$opt")
                fi
            done
        done
        printf '%s\n' "${result[@]}"
    fi
}

# ============================================================================
# Ввод текста (Text Input)
# ============================================================================

gum_input() {
    local prompt="$1"
    local placeholder="${2:-}"
    local value="${3:-}"

    if $GUM_AVAILABLE; then
        gum input \
            --prompt "$prompt" \
            --placeholder "$placeholder" \
            --value "$value" \
            --prompt.foreground="#2196F3" \
            --placeholder.foreground="#9E9E9E"
    else
        echo -n "$prompt "
        if [ -n "$placeholder" ]; then
            echo -e "(${COLOR_CYAN}$placeholder${COLOR_RESET})"
        fi
        read -r input
        echo "${input:-$value}"
    fi
}

# ============================================================================
# Ввод пароля (Password Input)
# ============================================================================

gum_password() {
    local prompt="$1"

    if $GUM_AVAILABLE; then
        gum input \
            --prompt "$prompt" \
            --password \
            --prompt.foreground="#2196F3"
    else
        echo -n "$prompt "
        read -rs password
        echo ""
        echo "$password"
    fi
}

# ============================================================================
# Ввод нескольких строк (Multi-line Input)
# ============================================================================

gum_write() {
    local title="$1"
    local placeholder="${2:-}"

    if $GUM_AVAILABLE; then
        gum write \
            --title "$title" \
            --placeholder "$placeholder" \
            --width 60 \
            --height 10
    else
        echo -e "${COLOR_BOLD}${COLOR_CYAN}$title${COLOR_RESET}"
        echo "(введите текст, пустая строка для завершения)"
        local lines=()
        while true; do
            read -r line
            [ -z "$line" ] && break
            lines+=("$line")
        done
        printf '%s\n' "${lines[@]}"
    fi
}

# ============================================================================
# Прогресс бар (Progress Bar)
# ============================================================================

gum_progress() {
    local title="${1:-Загрузка...}"
    local total="${2:-100}"

    if $GUM_AVAILABLE; then
        local progress_bar
        progress_bar=$(gum spin --spinner dot --title "$title" -- sleep 0.1)
        # Для реального прогресса нужно использовать в цикле
        echo "$progress_bar"
    else
        echo -e "${COLOR_CYAN}$title${COLOR_RESET}"
    fi
}

gum_spin() {
    local title="${1:-Загрузка...}"
    local cmd="${2:-}"

    if $GUM_AVAILABLE; then
        gum spin --spinner dot --title "$title" -- $cmd
    else
        echo -n "$title ... "
        eval "$cmd" > /dev/null 2>&1
        echo -e "${COLOR_GREEN}Готово${COLOR_RESET}"
    fi
}

# ============================================================================
# Таблицы (Table)
# ============================================================================

gum_table() {
    local data="$1"

    if $GUM_AVAILABLE; then
        echo "$data" | gum table
    else
        echo "$data"
    fi
}

# ============================================================================
# Форматированный вывод (Format)
# ============================================================================

gum_format() {
    local content="$1"

    if $GUM_AVAILABLE; then
        echo "$content" | gum format
    else
        echo "$content"
    fi
}

# ============================================================================
# Пауза (Pause)
# ============================================================================

gum_pause() {
    local message="${1:-Нажмите Enter для продолжения...}"

    if $GUM_AVAILABLE; then
        gum input --prompt "" --placeholder "$message" --width 50 >/dev/null || true
    else
        echo ""
        echo -n "$message "
        read -r _ || true
    fi
}

# ============================================================================
# Список с деталями (List with details)
# ============================================================================

gum_list_detail() {
    local title="$1"
    shift

    if $GUM_AVAILABLE; then
        # Формат: "label\tdescription"
        gum choose --header "$title" "$@"
    else
        echo -e "${COLOR_BOLD}${COLOR_CYAN}$title${COLOR_RESET}"
        for item in "$@"; do
            local label="${item%%       *}"
            local desc="${item#*        }"
            echo -e "  ${COLOR_BOLD}${COLOR_BLUE}•${COLOR_RESET} ${COLOR_BOLD}$label${COLOR_RESET}"
            [ "$label" != "$desc" ] && echo -e "    ${COLOR_CYAN}$desc${COLOR_RESET}"
        done
        echo ""
    fi
}

# ============================================================================
# Статус блок (Status Block)
# ============================================================================

gum_status_block() {
    local title="$1"
    local status="$2"
    local color="${3:-blue}"

    local color_code="$COLOR_BLUE"
    case "$color" in
        green) color_code="$COLOR_GREEN" ;;
        red) color_code="$COLOR_RED" ;;
        yellow) color_code="$COLOR_YELLOW" ;;
        magenta) color_code="$COLOR_MAGENTA" ;;
    esac

    if $GUM_AVAILABLE; then
        gum style \
            --border rounded \
            --border-foreground "$color_code" \
            --padding "0 2" \
            "$title: ${color_code}${status}${COLOR_RESET}"
    else
        echo -e "${COLOR_BOLD}$title:${COLOR_RESET} ${color_code}${status}${COLOR_RESET}"
    fi
}

# ============================================================================
# Информационная панель (Info Panel)
# ============================================================================

gum_panel() {
    local title="$1"
    local content="$2"
    local style="${3:-info}"

    local border_color="#607D8B"
    case "$style" in
        error) border_color="#F44336" ;;
        success) border_color="#4CAF50" ;;
        warning) border_color="#FFC107" ;;
        info) border_color="#2196F3" ;;
    esac

    if $GUM_AVAILABLE; then
        gum style \
            --border rounded \
            --border-foreground "$border_color" \
            --padding "1 3" \
            --margin "1 2" \
            "$content"
    else
        echo ""
        echo -e "${COLOR_CYAN}┌────────────────────────────────────────┐${COLOR_RESET}"
        echo -e "${COLOR_CYAN}│${COLOR_RESET} ${title}"
        echo -e "${COLOR_CYAN}├────────────────────────────────────────┤${COLOR_RESET}"
        echo "$content" | while IFS= read -r line; do
            echo -e "${COLOR_CYAN}│${COLOR_RESET} $line"
        done
        echo -e "${COLOR_CYAN}└────────────────────────────────────────┘${COLOR_RESET}"
        echo ""
    fi
}

# ============================================================================
# Проверка размера терминала
# ============================================================================

gum_term_check() {
    local min_cols="${1:-70}"
    local min_lines="${2:-18}"

    local cols lines
    cols=$(tput cols 2>/dev/null || echo 0)
    lines=$(tput lines 2>/dev/null || echo 0)

    if [ "$cols" -gt 0 ] && [ "$cols" -lt "$min_cols" ]; then
        return 0
    fi
    if [ "$lines" -gt 0 ] && [ "$lines" -lt "$min_lines" ]; then
        return 0
    fi
    return 1
}

gum_term_warn() {
    if gum_term_check; then
        gum_notify warn "Терминал слишком мал. Рекомендуется увеличить окно."
        return 0
    fi
    return 1
}

# ============================================================================
# Инициализация (вызывается явно из main_menu_gum)
# ============================================================================