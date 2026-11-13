#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/products/zapret/install.sh"
PRODUCT_ID=zapret2
PRODUCT_SERVICE=zapret2
INIT_SYSTEM=systemd
warn() { :; }
service_is_active() { [ "$1" = zapret ] && [ "$active" = true ]; }
service_is_enabled() { [ "$1" = zapret ] && [ "$enabled" = true ]; }
manage_service() { echo "$PRODUCT_SERVICE $1" >> "$events"; }
manage_autostart() { echo "$PRODUCT_SERVICE $1" >> "$events"; }
events=$(mktemp)
trap 'rm -f "$events"' EXIT
active=true enabled=true switch_pending=false
prepare_legacy_switch <<< y
[ "$switch_pending" = true ]
grep -qx 'zapret stop' "$events"
grep -qx 'zapret disable' "$events"
restore_legacy_service
grep -qx 'zapret2 stop' "$events"
grep -qx 'zapret2 disable' "$events"
grep -qx 'zapret enable' "$events"
grep -qx 'zapret start' "$events"
: > "$events"
switch_pending=false
if prepare_legacy_switch <<< n; then exit 1; fi
[ "$switch_pending" = false ] && [ ! -s "$events" ]
active=false enabled=false
prepare_legacy_switch
[ "$switch_pending" = false ] && [ ! -s "$events" ]
echo 'PASS migration switch, rollback and cancellation'
