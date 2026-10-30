#!/bin/bash
# No root, network, real services or installed products required.
set -eu
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/common/snow.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

gum_notify() { :; }
resolve_config_vars() { sed -i 's/%BIN%/resolved/g' "$1"; }
validate_config() { bash -n "$1"; }
backup_begin() {
    [ "$scenario" != backup_fail ] || return 1
    BACKUP_DIR="$case_dir/backup"
    mkdir -p "$BACKUP_DIR"
}
backup_path() {
    [ "$scenario" != backup_path_fail ] || return 1
    mkdir -p "$BACKUP_DIR$(dirname "$1")"
    [ ! -f "$1" ] || cp -p "$1" "$BACKUP_DIR$1"
}
action_restart() {
    printf 'restart\n' >> "$case_dir/events"
    [ "$scenario" != restart_fail ] || return 1
}
product_health() { [ "$scenario" != health_fail ]; }

for scenario in success invalid backup_fail backup_path_fail restart_fail health_fail no_restart preset; do
    case_dir="$work/$scenario"
    mkdir -p "$case_dir"
    PRODUCT_DIR="$case_dir"
    PRODUCT_CONFIG_FILE="$case_dir/config"
    PRODUCT_ID=zapret2
    PRODUCT_SERVICE=zapret2
    printf 'VALUE=old\n' > "$PRODUCT_CONFIG_FILE"
    chmod 640 "$PRODUCT_CONFIG_FILE"
    printf 'VALUE=%%BIN%%\n' > "$case_dir/input"
    printf 'DEFAULT=yes\n' > "$case_dir/config.default"
    [ "$scenario" != invalid ] || printf 'VALUE="\n' > "$case_dir/input"
    cp "$case_dir/input" "$case_dir/source-copy"
    restart=true
    preset=false
    [ "$scenario" != no_restart ] || restart=false
    [ "$scenario" != preset ] || preset=true
    if apply_product_config "$case_dir/input" "$restart" "$preset"; then rc=0; else rc=1; fi
    cmp "$case_dir/input" "$case_dir/source-copy"
    case "$scenario" in
        success|no_restart|preset)
            [ "$rc" = 0 ]
            grep -qx VALUE=resolved "$PRODUCT_CONFIG_FILE"
            [ "$(stat -c %a "$PRODUCT_CONFIG_FILE")" = 640 ]
            ;;
        *)
            [ "$rc" = 1 ]
            grep -qx VALUE=old "$PRODUCT_CONFIG_FILE"
            ;;
    esac
    case "$scenario" in
        invalid|backup_fail|backup_path_fail|no_restart) [ ! -e "$case_dir/events" ] ;;
        restart_fail|health_fail) [ "$(wc -l < "$case_dir/events")" = 2 ] ;;
    esac
    [ "$scenario" != preset ] || grep -qx DEFAULT=yes "$PRODUCT_CONFIG_FILE"
    printf 'PASS %s\n' "$scenario"
done
