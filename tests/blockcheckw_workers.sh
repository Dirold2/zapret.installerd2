#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/products/zapret2/blockcheckw.sh"
PRODUCT_DIR=$(mktemp -d)
trap 'rm -rf "$PRODUCT_DIR"' EXIT
gum_notify() { :; }
pause() { :; }
[ "$(_bcw_workers)" = 8 ]
action_set_bcw_workers <<< '12'
[ "$(_bcw_workers)" = 12 ]
if action_set_bcw_workers <<< '0'; then exit 1; fi
if action_set_bcw_workers <<< 'abc'; then exit 1; fi
[ "$(_bcw_workers)" = 12 ]
action_set_bcw_workers <<< ''
[ "$(_bcw_workers)" = 12 ]
echo 'PASS blockcheckw worker configuration'
