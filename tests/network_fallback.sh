#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/products/zapret/install.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
log() { :; }
warn() { :; }

curl() {
    local url="${*: -1}"
    printf '%s\n' "$url" >> "$TEST_TMP/calls"
    case "$url" in
        https://cdn.gh-proxy.org/https://github.com/*) printf 'proxy-ok' ;;
        *) return 22 ;;
    esac
}
[ "$(github_curl https://github.com/example/repo/archive/test.tar.gz)" = proxy-ok ]
[ "$(wc -l < "$TEST_TMP/calls")" -eq 2 ]

# A failed or corrupt mirror must not replace an existing Lua file.
PRODUCT_ID=zapret2 PRODUCT_DIR="$TEST_TMP/product"
mkdir -p "$PRODUCT_DIR/lua"
printf 'existing' > "$PRODUCT_DIR/lua/zapret-installer-multishake.lua"
: > "$TEST_TMP/calls"
curl() {
    local url="${*: -1}"
    printf '%s\n' "$url" >> "$TEST_TMP/calls"
    printf '{"content":"aW52YWxpZA=="}'
}
if install_zapret2_lua 2>/dev/null; then exit 1; fi
[ "$(wc -l < "$TEST_TMP/calls")" -eq 7 ]
[ "$(cat "$PRODUCT_DIR/lua/zapret-installer-multishake.lua")" = existing ]
printf 'PASS GitHub proxy and Lua mirror failure handling\n'
