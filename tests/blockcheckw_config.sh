#!/bin/bash
set -eu
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/products/zapret2/blockcheckw.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
PRODUCT_CONFIG_FILE="$work/config"
cat > "$PRODUCT_CONFIG_FILE" <<'EOF'
NFQWS2_OPT="
--blob=custom:/example/fake.bin
--name=YouTube \
--filter-tcp=80,443 \
--hostlist-domains=youtube.com,googlevideo.com \
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls
--new
# blockcheckw auto: youtube.com
--filter-tcp=80,443 --hostlist-domains=youtube.com --lua-desync=multisplit:pos=2 --new
"
OTHER=unchanged
EOF
strategy='--payload=tls_client_hello --lua-desync=multisplit:pos=midsld'
cp "$PRODUCT_CONFIG_FILE" "$work/original"
_bcw_prepare_config "$work/candidate" youtube.com "$strategy"
cmp "$PRODUCT_CONFIG_FILE" "$work/original"
bash -n "$work/candidate"
python3 -c 'from pathlib import Path; import sys
s=Path(sys.argv[1]).read_text()
assert s.count("# blockcheckw auto: youtube.com") == 1
assert s.index("--blob=") < s.index("--name=blockcheckw_youtube.com") < s.index("--name=YouTube")
assert "--hostlist-domains=youtube.com,googlevideo.com" in s
assert "OTHER=unchanged" in s
' "$work/candidate"
printf 'PASS priority, legacy replacement, original preserved\n'
cp "$work/candidate" "$PRODUCT_CONFIG_FILE"
_bcw_prepare_config "$work/repeated" youtube.com "$strategy"
cmp "$work/candidate" "$work/repeated"
printf 'PASS repeat is idempotent\n'
for bad in '--new' '--payload=tls_client_hello --filter-tcp=443' '--lua-init=$unsafe' '--lua-init=unsafe\'; do
    if _bcw_prepare_config "$work/bad" youtube.com "$bad"; then
        echo 'FAIL unsafe strategy accepted'; exit 1
    fi
done
printf 'PASS unsafe profile arguments rejected\n'
apply_product_config() {
    [ "$2" = true ]
    cmp "$1" "$work/repeated"
    return 7
}
if _bcw_apply_strategy youtube.com "$strategy"; then
    echo 'FAIL transaction error swallowed'; exit 1
else
    [ "$?" = 7 ]
fi
if compgen -G "${PRODUCT_CONFIG_FILE}.bcw.*" >/dev/null; then
    echo 'FAIL temporary file leaked'; exit 1
fi
printf 'PASS shared transaction called, errors propagated, temporary file removed\n'
