#!/bin/bash
set -eu
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/common/flow_v2.sh"

curl() { printf '%s' "$MOCK_RESPONSE"; return "$MOCK_STATUS"; }
MOCK_RESPONSE=200 MOCK_STATUS=0
output=$(check_site_connection test https://example.com)
[[ "$output" == *'[OK]'* && "$output" == *'HTTP 200'* ]]
MOCK_RESPONSE=404
if output=$(check_site_connection test https://example.com); then exit 1; fi
[[ "$output" == *'HTTP 404'* && "$output" == *'соединение установлено'* ]]
MOCK_RESPONSE='curl: timeout' MOCK_STATUS=28
if output=$(check_site_connection test https://example.com); then exit 1; fi
[[ "$output" == *'[ОШИБКА]'* && "$output" == *'curl 28'* ]]
printf 'site checks: OK\n'
