#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/products/zapret/install.sh"
PRODUCT_DIR=$(mktemp -d)
trap 'rm -rf "$PRODUCT_DIR"' EXIT
mkdir -p "$PRODUCT_DIR/nested dir"
printf '#!/bin/sh\n' > "$PRODUCT_DIR/nested dir/test script.sh"
chmod 600 "$PRODUCT_DIR/nested dir/test script.sh"
ensure_scripts_executable
[ -x "$PRODUCT_DIR/nested dir/test script.sh" ]
printf 'PASS script permissions\n'
