#!/bin/bash

# =========================
# CONFIGURATION
# =========================
declare -A PRODUCTS=(
    ["zapret"]="bol-van/zapret zapret zapret.service /opt/zapret /opt/zapret-ver zapret"
    ["zapret2"]="bol-van/zapret2 zapret2 zapret2.service /opt/zapret2 /opt/zapret2-ver zapret2"
)

PRODUCT_ID="${1:-zapret}"
PRODUCT_REPO=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f1)
PRODUCT_NAME=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f2)
PRODUCT_SERVICE=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f3)
PRODUCT_DIR=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f4)
PRODUCT_VER_FILE=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f5)
PRODUCT_BINLINK=$(echo "${PRODUCTS[$PRODUCT_ID]}" | cut -d' ' -f6)

PRODUCT_CFGS_DIR="/opt/$PRODUCT_ID/zapret.cfgs"
PRODUCT_CONFIG_FILE="/opt/$PRODUCT_ID/config"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# =========================
# GitHub helpers
# =========================
gh_latest_url() {
    local repo="$1"

    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | \
    python3 -c '
import sys, json

data = json.load(sys.stdin)

tag = data["tag_name"]

print(f"https://github.com/'"$repo"'/archive/refs/tags/{tag}.tar.gz")
'
}

get_latest_version() {
    curl -fsSL "https://api.github.com/repos/$PRODUCT_REPO/releases/latest" 2>/dev/null | \
    grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//' || echo "unknown"
}

# =========================
# INSTALL CORE
# =========================
install_release() {
    local tmp url extracted fake_backup
    tmp=$(mktemp -d) || return 1
    fake_backup=$(mktemp -d)
    url=$(gh_latest_url "$PRODUCT_REPO")
    
    [ -z "$url" ] && { rm -rf "$tmp" "$fake_backup"; return 1; }

    [ -d "$PRODUCT_DIR/files/fake" ] && cp -r "$PRODUCT_DIR/files/fake"/* "$fake_backup/" 2>/dev/null || true
    
    log "Скачиваю релиз $PRODUCT_ID..."
    curl -fL "$url" -o "$tmp/release.tar.gz" || { rm -rf "$tmp" "$fake_backup"; return 1; }
    
    rm -rf "$PRODUCT_DIR" 2>/dev/null || true
    mkdir -p /opt
    
    tar -xzf "$tmp/release.tar.gz" -C /opt || {
        rm -rf "$tmp" "$fake_backup"
        return 1
    }

    extracted=$(tar -tzf "$tmp/release.tar.gz" | head -1 | cut -d/ -f1)
    extracted="/opt/$extracted"

    rm -rf "$tmp"
    [ -z "$extracted" ] && { rm -rf "$fake_backup"; return 1; }
    
    mv "$extracted" "$PRODUCT_DIR" || { rm -rf "$fake_backup"; return 1; }

    [ -d "$fake_backup" ] && [ "$(ls -A "$fake_backup" 2>/dev/null)" ] &&
        cp -r "$fake_backup"/* "$PRODUCT_DIR/files/fake/" 2>/dev/null || true
    rm -rf "$fake_backup"

    local ver
    ver=$(echo "$url" | sed 's/.*\/tags\///; s/\.tar\.gz$//; s/^v//')
    echo "${ver:-release}" > "$PRODUCT_VER_FILE"
    log "$PRODUCT_ID установлен из релиза"
}

install_git() {
    rm -rf "$PRODUCT_DIR"
    log "Клонирую git-репозиторий $PRODUCT_REPO..."
    git clone --depth 1 "https://github.com/$PRODUCT_REPO" "$PRODUCT_DIR" || return 1
    echo "git" > "$PRODUCT_VER_FILE"
    log "$PRODUCT_ID установлен из git"
}

install_cfgs() {
    [ -d "$PRODUCT_CFGS_DIR" ] && return 0
    git clone "$PRODUCT_CFGS_REPO" "$PRODUCT_CFGS_DIR" || warn "Не удалось клонировать конфиги"
}

ensure_lists() {
    local ipset_dir="$PRODUCT_DIR/ipset"
    mkdir -p "$ipset_dir"
    chmod 755 "$ipset_dir" 2>/dev/null || true
    for f in zapret-hosts-user.txt ipset-game.txt ipset-discord.txt ipset-exclude-user.txt ipset-include-user.txt; do
        touch "$ipset_dir/$f" 2>/dev/null || true
        chmod 644 "$ipset_dir/$f" 2>/dev/null || true
    done
}

# =========================
# SYSTEMD
# =========================
systemd_install() {
    [ "$INIT_SYSTEM" = "systemd" ] || return 0

    mkdir -p /etc/systemd/system

    local unit_path="/etc/systemd/system/${PRODUCT_SERVICE}.service"
    local script_path="${PRODUCT_DIR}/init.d/sysv/${PRODUCT_SERVICE}"

    cat > "$unit_path" <<EOF
[Unit]
Description=$PRODUCT_ID network filtering service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
Restart=no
TimeoutSec=30
KillMode=control-group
GuessMainPID=no

ExecStart=/bin/bash $script_path start
ExecStop=/bin/bash $script_path stop

RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${PRODUCT_SERVICE}.service" >/dev/null 2>&1 || true
}



# =========================
# MAIN INSTALL
# =========================
main_install() {
    read -p "Установить $PRODUCT_ID? (y/N): " answer
    [[ "$answer" =~ ^[Yy] ]] || return 0
    
    # Backup
    [ -d "$PRODUCT_DIR" ] && {
        read -p "Найден $PRODUCT_DIR. Удалить? (y/N): " answer
        [[ "$answer" =~ ^[Yy] ]] || return 0
        rm -rf "$PRODUCT_DIR"
    }
    
    # Dependencies (упрощенно)
    command -v iptables >/dev/null 2>/dev/null || apt-get install -y iptables ipset 2>/dev/null || true
    
    # Install
    if ! install_release; then
        warn "Релиз не удалось установить, использую git"
        install_git || error "Не удалось установить $PRODUCT_ID"
    fi
    
    # Build
    log "Сборка $PRODUCT_ID..."

    cd "$PRODUCT_DIR" || error "Не удалось открыть $PRODUCT_DIR"

    make -j"$(nproc)" || error "Ошибка сборки $PRODUCT_ID"

    nfq_bin=$(find "$PRODUCT_DIR" -type f \( -name "nfqws" -o -name "nfqws2" \) | head -n1)    

    [ -n "$nfq_bin" ] || error "nfqws binary не найден"
    [ -x "$nfq_bin" ] || error "nfqws binary не executable"
    # Run installer
    [ -f "$PRODUCT_DIR/install_easy.sh" ] && {
        cd "$PRODUCT_DIR"
        sed -i 's/ask_yes_no N/ask_yes_no Y/g' common/installer.sh 2>/dev/null || true
        yes "" | ./install_easy.sh || true
        sed -i 's/ask_yes_no Y/ask_yes_no N/g' common/installer.sh 2>/dev/null || true
    }
    
    # Configs
    install_cfgs
    [ -d "$PRODUCT_CFGS_DIR/configurations" ] && {
        cp -f "$PRODUCT_CFGS_DIR/configurations/general" "$PRODUCT_CONFIG_FILE" || true
    }
    [ -d "$PRODUCT_CFGS_DIR/bin" ] && {
        mkdir -p "$PRODUCT_DIR/files/fake"
        cp "$PRODUCT_CFGS_DIR/bin/"* "$PRODUCT_DIR/files/fake/" 2>/dev/null || true
    }
    
    ensure_lists
    ln -sf "/opt/zapret.installer/zapret-control.sh" "/bin/$PRODUCT_ID" 2>/dev/null || true
    
    systemd_install
    systemctl restart "$PRODUCT_SERVICE" 2>/dev/null || true
    
    if product_health "$PRODUCT_SERVICE"; then
        log "$PRODUCT_ID успешно установлен и работает!"
    else
        warn "$PRODUCT_ID установлен, но не активен (проверьте nft/ipset)"
    fi
}

# =========================
# UPDATE
# =========================
main_update() {
    local ver_file_content
    ver_file_content=$(cat "$PRODUCT_VER_FILE" 2>/dev/null || echo "")
    
    if [ "$ver_file_content" = "git" ]; then
        cd "$PRODUCT_DIR" && git pull origin master || install_release
    else
        install_release || install_git
    fi
    
    install_cfgs
    systemctl restart "$PRODUCT_SERVICE" 2>/dev/null || true
    
    log "$PRODUCT_ID обновлен!"
}