#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${1:-}"
TIMEOUT_SEC="${TIMEOUT_SEC:-4}"
MAX_DOMAIN_TESTS="${MAX_DOMAIN_TESTS:-0}"   # 0 = all
STRICT_DOMAIN_FAIL="${STRICT_DOMAIN_FAIL:-0}" # 0 = DNS/TLS как WARN
PARALLEL_JOBS="${PARALLEL_JOBS:-16}"
USE_GUM="${USE_GUM:-auto}"                 # auto|1|0
SUMMARY_ONLY="${SUMMARY_ONLY:-0}"          # 1 = only summary

if [ -z "$CONFIG_FILE" ]; then
    echo "[ERR] Config file not provided"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERR] Config file not found: $CONFIG_FILE"
    exit 1
fi

require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

for cmd in awk sed grep sort uniq timeout getent; do
    if ! require_cmd "$cmd"; then
        echo "[ERR] Missing required command: $cmd"
        exit 1
    fi
done

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

GUM_ENABLED=0
if [ "$USE_GUM" = "1" ]; then
    GUM_ENABLED=1
elif [ "$USE_GUM" = "auto" ] && has_cmd gum && [ -t 1 ]; then
    GUM_ENABLED=1
fi

section() {
    local title="$1"
    if [ "$GUM_ENABLED" -eq 1 ]; then
        gum style --bold --foreground 212 "$title"
    else
        echo "$title"
    fi
}

msg() {
    local text="$1"
    if [ "$GUM_ENABLED" -eq 1 ]; then
        gum style --foreground 244 "$text"
    else
        echo "$text"
    fi
}

parse_domains() {
    sed ':a;N;$!ba;s/\\\n/ /g' "$CONFIG_FILE" \
        | grep -oE -- '--hostlist-domains=[^[:space:]]+' || true
}

mapfile -t ALL_DOMAINS < <(
    parse_domains \
        | sed 's/^--hostlist-domains=//' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | grep -E '^[A-Za-z0-9._-]+$' \
        | sort -u
)

if [ "$MAX_DOMAIN_TESTS" -gt 0 ]; then
    mapfile -t DOMAINS < <(printf '%s\n' "${ALL_DOMAINS[@]}" | head -n "$MAX_DOMAIN_TESTS")
else
    DOMAINS=("${ALL_DOMAINS[@]}")
fi

tcp_check() {
    local host="$1" port="$2"
    timeout "$TIMEOUT_SEC" bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

udp_check_nc() {
    local host="$1" port="$2"
    timeout "$TIMEOUT_SEC" nc -zu -w"$TIMEOUT_SEC" "$host" "$port" >/dev/null 2>&1
}

tls_check() {
    local host="$1"
    if has_cmd openssl; then
        timeout "$TIMEOUT_SEC" openssl s_client -connect "$host:443" -servername "$host" -brief </dev/null >/dev/null 2>&1
    else
        return 2
    fi
}

http_head_check() {
    local host="$1"
    if has_cmd curl; then
        timeout "$TIMEOUT_SEC" curl -sSI --connect-timeout "$TIMEOUT_SEC" -m "$TIMEOUT_SEC" "https://$host" >/dev/null 2>&1
    else
        return 2
    fi
}

print_result() {
    local rc="$1" label="$2" details="$3"

    if [ "$SUMMARY_ONLY" -eq 1 ]; then
        return
    fi

    if [ "$rc" -eq 0 ]; then
        echo "[ OK ] $label :: $details"
    elif [ "$rc" -eq 2 ]; then
        echo "[SKIP] $label :: $details (tool missing)"
    else
        echo "[FAIL] $label :: $details"
    fi
}

print_warn_result() {
    local rc="$1" label="$2" details="$3"

    if [ "$SUMMARY_ONLY" -eq 1 ]; then
        return
    fi

    if [ "$rc" -eq 0 ]; then
        echo "[ OK ] $label :: $details"
    elif [ "$rc" -eq 2 ]; then
        echo "[SKIP] $label :: $details (tool missing)"
    else
        echo "[WARN] $label :: $details"
    fi
}

ok=0
fail=0
warn=0
skip=0

count_mode_rc() {
    local mode="$1" rc="$2"
    if [ "$mode" = "fail" ]; then
        case "$rc" in
            0) ((ok++)) ;;
            2) ((skip++)) ;;
            *) ((fail++)) ;;
        esac
    else
        case "$rc" in
            0) ((ok++)) ;;
            2) ((skip++)) ;;
            *) ((warn++)) ;;
        esac
    fi
}

run_domain_phase_parallel() {
    local phase="$1"
    local mode="$2"   # fail|warn
    local check_fn="$3"

    local tmpdir
    tmpdir="$(mktemp -d)"

    local pids=()
    local d safe rc

    for d in "${DOMAINS[@]}"; do
        safe="${d//[^A-Za-z0-9._-]/_}"

        (
            "$check_fn" "$d"
            rc=$?
            printf '%s\n' "$rc" > "$tmpdir/$safe"
        ) &

        pids+=("$!")

        if [ "${#pids[@]}" -ge "$PARALLEL_JOBS" ]; then
            wait "${pids[0]}" || true
            pids=("${pids[@]:1}")
        fi
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    for d in "${DOMAINS[@]}"; do
        safe="${d//[^A-Za-z0-9._-]/_}"
        rc="$(cat "$tmpdir/$safe" 2>/dev/null || echo 1)"

        if [ "$rc" -eq 0 ]; then
            print_warn_result 0 "$phase" "$d"
        elif [ "$rc" -eq 2 ]; then
            print_warn_result 2 "$phase" "$d"
        else
            if [ "$mode" = "fail" ]; then
                print_result 1 "$phase" "$d"
            else
                print_warn_result 1 "$phase" "$d"
            fi
        fi

        count_mode_rc "$mode" "$rc"
    done

    rm -rf "$tmpdir"
}

dns_check() {
    local host="$1"
    getent ahosts "$host" >/dev/null 2>&1
}

echo "== Zapret bench =="
echo "Config: $CONFIG_FILE"
echo "Timeout: ${TIMEOUT_SEC}s"
echo "Strict domain fail mode: $STRICT_DOMAIN_FAIL"
echo "Parallel jobs: $PARALLEL_JOBS"
echo "Gum UI: $GUM_ENABLED"
echo

echo "Parsed domains: ${#ALL_DOMAINS[@]} (testing: ${#DOMAINS[@]})"

TCP_PORTS_RAW="$(grep -m1 -E '^NFQWS_PORTS_TCP=' "$CONFIG_FILE" | sed -E 's/^NFQWS_PORTS_TCP=//' || true)"
UDP_PORTS_RAW="$(grep -m1 -E '^NFQWS_PORTS_UDP=' "$CONFIG_FILE" | sed -E 's/^NFQWS_PORTS_UDP=//' || true)"

echo "NFQWS TCP ports: ${TCP_PORTS_RAW:-<none>}"
echo "NFQWS UDP ports: ${UDP_PORTS_RAW:-<none>}"
echo

if [ "$SUMMARY_ONLY" -eq 0 ]; then section "== 1) DNS resolve check =="; fi
if [ "$STRICT_DOMAIN_FAIL" -eq 1 ]; then
    run_domain_phase_parallel "DNS" "fail" "dns_check"
else
    run_domain_phase_parallel "DNS" "warn" "dns_check"
fi
echo

if [ "$SUMMARY_ONLY" -eq 0 ]; then section "== 2) TLS handshake check =="; fi
if [ "$STRICT_DOMAIN_FAIL" -eq 1 ]; then
    run_domain_phase_parallel "TLS" "fail" "tls_check"
else
    run_domain_phase_parallel "TLS" "warn" "tls_check"
fi
echo

if [ "$SUMMARY_ONLY" -eq 0 ]; then section "== 3) HTTPS HEAD check =="; fi
run_domain_phase_parallel "HTTPS" "warn" "http_head_check"
echo

if [ "$SUMMARY_ONLY" -eq 0 ]; then section "== 4) Raw TCP reachability =="; fi
declare -a TCP_PROBES=(
    "discord.com:443"
    "gateway.discord.gg:443"
    "cdn.discordapp.com:443"
    "www.youtube.com:443"
    "googlevideo.com:443"
    "web.whatsapp.com:443"
)

for p in "${TCP_PROBES[@]}"; do
    host="${p%:*}"
    port="${p#*:}"
    tcp_check "$host" "$port"
    rc=$?
    print_result "$rc" TCP "$host:$port"
    count_mode_rc "fail" "$rc"
done
echo

if [ "$SUMMARY_ONLY" -eq 0 ]; then section "== 5) UDP path check (best effort) =="; fi
if has_cmd nc; then
    declare -a UDP_PROBES=(
        "1.1.1.1:53"
        "8.8.8.8:53"
        "stun.l.google.com:19302"
    )
    for p in "${UDP_PROBES[@]}"; do
        host="${p%:*}"
        port="${p#*:}"
        udp_check_nc "$host" "$port"
        rc=$?
        print_warn_result "$rc" UDP "$host:$port"
        count_mode_rc "warn" "$rc"
    done
else
    print_warn_result 2 UDP "nc not found"
    count_mode_rc "warn" 2
fi
echo

echo "== Summary =="
echo "OK   : $ok"
echo "FAIL : $fail"
echo "WARN : $warn"
echo "SKIP : $skip"

[ "$fail" -gt 0 ] && exit 1
exit 0