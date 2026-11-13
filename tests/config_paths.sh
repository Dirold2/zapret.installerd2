#!/bin/bash
set -eu
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/common/snow.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
PRODUCT_PATH_BIN=/opt/zapret2
PRODUCT_PATH_LISTS=/opt/zapret2/ipset
PRODUCT_PATH_LUA=/opt/zapret2/lua
cat > "$work/config" <<'EOF'
--lua-init=@/opt/zapret2/lua/test.lua
--lua-init=lua/test.lua
--hostlist=lists/test.txt
--hostlist=/opt/zapret2/ipset/lists/test.txt
EOF
resolve_config_vars "$work/config"
cp "$work/config" "$work/once"
resolve_config_vars "$work/config"
cmp "$work/once" "$work/config"
grep -Fx -- '--lua-init=@/opt/zapret2/lua/test.lua' "$work/config" >/dev/null
grep -Fx -- '--lua-init=/opt/zapret2/lua/test.lua' "$work/config" >/dev/null
grep -Fx -- '--hostlist=/opt/zapret2/ipset/test.txt' "$work/config" >/dev/null
grep -Fx -- '--hostlist=/opt/zapret2/ipset/lists/test.txt' "$work/config" >/dev/null
printf 'config path resolution: OK\n'
