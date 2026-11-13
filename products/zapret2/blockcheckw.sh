#!/bin/bash

# blockcheckw is supported only by zapret2.

action_install_blockcheckw() {
    [ "$PRODUCT_ID" = "zapret2" ] || { gum_notify error "blockcheckw только для zapret2"; return 1; }

    local target_dir="$PRODUCT_DIR/blockcheckw"
    local bin_path="$target_dir/blockcheckw"
    [ -x "$bin_path" ] && { gum_notify info "blockcheckw уже установлен"; return 0; }

    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        i686|i386) arch="x86" ;;
        mips|mips64|mipsel|ppc|riscv64) ;;
        *) gum_notify error "Неизвестная архитектура: $arch"; return 1 ;;
    esac

    local tag
    tag=$(github_curl "https://api.github.com/repos/rcd27/blockcheckw/releases/latest" 2>/dev/null |
        grep '"tag_name"' | cut -d'"' -f4)
    [ -n "$tag" ] || { gum_notify error "Не удалось определить версию"; return 1; }

    local tarball="blockcheckw-linux-${arch}.tar.gz"
    local url="https://github.com/rcd27/blockcheckw/releases/download/${tag}/${tarball}"
    local tmp
    tmp=$(mktemp -d) || { gum_notify error "Ошибка tmpdir"; return 1; }

    print_header "Установка blockcheckw" "normal"
    gum style "Версия:  $tag"
    gum style "Арх:     $arch"
    if ! github_curl "$url" -o "$tmp/$tarball"; then
        rm -rf "$tmp"; gum_notify error "Не удалось скачать $tarball"; return 1
    fi

    mkdir -p "$target_dir"
    if ! tar -xzf "$tmp/$tarball" -C "$target_dir" 2>/dev/null || [ ! -f "$bin_path" ]; then
        rm -rf "$tmp" "$target_dir"; gum_notify error "Не удалось распаковать архив"; return 1
    fi
    rm -rf "$tmp"
    chmod +x "$bin_path" || return 1

    local arch_dir src target_bin_dir="$PRODUCT_DIR/binaries/linux-$(uname -m)"
    mkdir -p "$target_bin_dir"
    for src in "$PRODUCT_DIR/nfq2/nfqws2" "$PRODUCT_DIR/binaries/nfqws2"; do
        if [ -f "$src" ] && [ ! -f "$target_bin_dir/nfqws2" ]; then
            ln -sf "$src" "$target_bin_dir/nfqws2" || return 1
            break
        fi
    done

    gum_notify info "blockcheckw $tag установлен"
}

action_uninstall_blockcheckw() {
    local target_dir="$PRODUCT_DIR/blockcheckw"
    [ -d "$target_dir" ] || { gum_notify info "blockcheckw не установлен"; return 0; }
    gum_confirm "Удалить blockcheckw?" && rm -rf "$target_dir" && gum_notify info "blockcheckw удалён"
}

blockcheckw_reports_dir() { printf '%s/blockcheckw/reports\n' "$PRODUCT_DIR"; }

action_view_bcw_results() {
    local reports_dir="$(blockcheckw_reports_dir)" files=() f
    while IFS= read -r f; do files+=("$(basename "$f")"); done < <(
        find "$reports_dir" -maxdepth 1 -type f \( -name '*_report_vanilla.txt' -o -name '*_scan.json' -o -name '*_scan.txt' -o -name '*_universal.json' -o -name '*_status.json' \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
    )
    [ ${#files[@]} -gt 0 ] || { gum_notify warn "Отчётов blockcheckw не найдено"; return 0; }
    files+=("Удалить все" "Назад")

    local act
    act="$(ui_choose_one "Отчёты blockcheckw" "${files[@]}")" || return 0
    case "$act" in
        "Назад") return 0 ;;
        "Удалить все")
            gum_confirm "Удалить все отчёты blockcheckw?" &&
                rm -f "$reports_dir"/*_report_vanilla.txt "$reports_dir"/*_scan.json "$reports_dir"/*_scan.txt "$reports_dir"/*_universal.json "$reports_dir"/*_status.json
            ;;
        *)
            local fpath="$reports_dir/$act"
            [ -f "$fpath" ] || return 1
            if [[ "$act" == *.json ]] && command -v python3 >/dev/null 2>&1; then
                python3 -m json.tool "$fpath" 2>/dev/null || cat "$fpath"
            elif command -v bat >/dev/null 2>&1; then
                bat --style=plain --paging=never "$fpath"
            else
                cat "$fpath"
            fi
            pause
            ;;
    esac
}

_bcw_workers() {
    local cfg="$PRODUCT_DIR/blockcheckw/config.env"
    [ -f "$cfg" ] && source "$cfg"
    printf '%s\n' "${BCW_WORKERS:-8}"
}

action_check_bcw_report() {
    local bin_path="$PRODUCT_DIR/blockcheckw/blockcheckw"
    local reports_dir="$(blockcheckw_reports_dir)" report domain take passes
    [ -x "$bin_path" ] || { gum_notify error "blockcheckw не установлен"; return 1; }

    local reports=()
    while IFS= read -r report; do reports+=("$(basename "$report")"); done < <(
        find "$reports_dir" -maxdepth 1 -type f \( -name '*_check.json' -o -name '*_universal.json' -o -name '*_status.json' \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
    )
    [ ${#reports[@]} -gt 0 ] || { gum_notify warn "Совместимых отчётов для проверки не найдено"; return 0; }

    report="$(ui_choose_one "Выберите отчёт для проверки" "${reports[@]}")" || return 0
    read -erp "Домен для проверки: " domain || return 1
    [ -n "$domain" ] || { gum_notify error "Укажите домен"; return 1; }
    read -erp "Сколько успешных стратегий проверить (по умолчанию 10, 0 = все): " take || return 1
    take="${take:-10}"
    [[ "$take" =~ ^[0-9]+$ ]] || { gum_notify error "Введите целое неотрицательное число"; return 1; }
    read -erp "Проходов верификации (по умолчанию 3, 1 = быстрый прогон): " passes || return 1
    passes="${passes:-3}"
    [[ "$passes" =~ ^[1-9][0-9]*$ ]] && [ "$passes" -le 100 ] || { gum_notify error "Введите целое число от 1 до 100"; return 1; }

    local args=(check --from-file "$reports_dir/$report" -d "$domain" --passes "$passes")
    [ "$take" = "0" ] || args+=(--take "$take")
    "$bin_path" "${args[@]}" || {
        gum_notify warn "Проверка отчёта завершилась с ошибкой"
        pause
        return 1
    }
    pause
}

action_set_bcw_workers() {
    local current workers cfg="$PRODUCT_DIR/blockcheckw/config.env"
    current="$(_bcw_workers)"
    read -erp "Число воркеров (текущее $current): " workers || return 1
    workers="${workers:-$current}"
    [[ "$workers" =~ ^[1-9][0-9]*$ ]] || {
        gum_notify error "Введите положительное число воркеров"
        return 1
    }
    mkdir -p "$(dirname "$cfg")" || return 1
    printf 'BCW_WORKERS=%s\n' "$workers" > "$cfg" || return 1
    gum_notify info "Сохранено: BCW_WORKERS=$workers"
    pause
}

action_bench_blockcheckw() {
    local bin_path="$PRODUCT_DIR/blockcheckw/blockcheckw" domain recommended
    [ -x "$bin_path" ] || { gum_notify error "blockcheckw не установлен"; return 1; }

    read -erp "Домен для теста (по умолчанию discord.com): " domain || return 1
    domain="${domain:-discord.com}"
    print_header "benchmark — $domain" "normal"
    "$bin_path" benchmark -d "$domain" || { gum_notify warn "benchmark завершился с ошибкой"; pause; return 1; }

    read -erp "Сколько воркеров записать (Enter = пропустить): " recommended || return 1
    if [ -n "$recommended" ] && [ "$recommended" -gt 0 ] 2>/dev/null; then
        printf 'BCW_WORKERS=%s\n' "$recommended" > "$PRODUCT_DIR/blockcheckw/config.env"
        gum_notify info "Сохранено: BCW_WORKERS=$recommended"
    fi
    pause
}

# Build a candidate only; apply_product_config owns validation and rollback.
_bcw_prepare_config() {
    python3 - "$PRODUCT_CONFIG_FILE" "$1" "$2" "$3" <<'PY'
import re
import sys
from pathlib import Path

source, output, domain, strategy = sys.argv[1:]
if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", domain):
    raise SystemExit("Некорректный домен")
if not strategy.startswith("--") or any(c in strategy for c in '\n\r"`$\\'):
    raise SystemExit("Стратегия не может быть безопасно записана в shell-конфиг")
# Report strategies must not create extra profiles or replace profile selectors.
if re.search(r"(?:^|\s)--(?:new|name|filter-[^=\s]+|hostlist[^=\s]*|ipset[^=\s]*)(?:=|\s|$)", strategy):
    raise SystemExit("Стратегия содержит управляющие параметры профиля")
config = Path(source).read_text()
blocks = list(re.finditer(r'^NFQWS2_OPT="(.*?)^"[ \t]*$', config, re.M | re.S))
if len(blocks) != 1:
    raise SystemExit("Ожидается один многострочный NFQWS2_OPT")
match = blocks[0]
body = match.group(1)
marker = "# blockcheckw auto: " + domain
# Remove only our own previously generated profile, including the legacy form.
managed = re.compile(r"(?m)^" + re.escape(marker) + r"\n(?:(?!^# blockcheckw auto:|^\").)*?--new[ \t]*\n(?:[ \t]*\n)*", re.S)
body = managed.sub("", body)
# Keep global declarations (e.g. --blob) before the first profile. Inserting
# ahead of that profile gives the exact-domain rule precedence over broad lists.
first = re.search(r"(?m)^[ \t]*(?:--name=|--filter-)", body)
if not first and body.strip():
    raise SystemExit("Не удалось безопасно определить начало профилей")
position = first.start() if first else len(body)
profile = (
    marker + "\n--name=blockcheckw_" + domain + " "
    "--filter-tcp=80,443 --hostlist-domains=" + domain + " " + strategy + " --new\n\n"
)
body = body[:position] + profile + body[position:]
updated = config[:match.start(1)] + body + config[match.end(1):]
Path(output).write_text(updated)
PY
}

_bcw_apply_strategy() (
    local domain="$1" strategy="$2" candidate
    candidate=$(mktemp "${PRODUCT_CONFIG_FILE}.bcw.XXXXXX") || return 1
    trap 'rm -f -- "$candidate"' EXIT
    _bcw_prepare_config "$candidate" "$domain" "$strategy" || return 1
    apply_product_config "$candidate" true
)

action_auto_strategy() {
    [ "$PRODUCT_ID" = "zapret2" ] || {
        gum_notify error "Автоподбор доступен только для zapret2"
        return 1
    }

    local bin_path="$PRODUCT_DIR/blockcheckw/blockcheckw"
    local reports_dir scan_file candidates_file check_file domain workers strategy
    [ -x "$bin_path" ] || { gum_notify error "blockcheckw не установлен"; return 1; }

    read -erp "Домен для автоподбора: " domain || return 1
    domain="${domain,,}"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || {
        gum_notify error "Некорректный домен"
        return 1
    }

    workers="$(_bcw_workers)"
    reports_dir="$(blockcheckw_reports_dir)"
    mkdir -p "$reports_dir" || return 1
    scan_file="$reports_dir/auto_${domain}_scan.txt"
    candidates_file="$reports_dir/auto_${domain}_candidates_report_vanilla.txt"
    check_file="$reports_dir/auto_${domain}_check.json"

    print_header "Автоподбор — $domain" "normal"
    gum style --foreground 3 "Scan найдёт стратегии; будут проверены первые 20, по 3 прохода."
    gum style --foreground 240 "Текущий конфиг не изменится до успешной проверки."
    gum_pause

    "$bin_path" -w "$workers" scan -d "$domain" --timeout 300 -o "$scan_file" || {
        gum_notify error "Не удалось найти стратегии для $domain"
        return 1
    }
    [ -s "$scan_file" ] || { gum_notify error "Отчёт scan не создан"; return 1; }

    # New blockcheckw scan reports contain bare nfqws2 arguments, but `check`
    # accepts its older vanilla `curl_test_*` format. Convert only a bounded
    # candidate set and retain the protocol inferred from every section header.
    if ! python3 - "$scan_file" "$candidates_file" "$domain" <<'PY'
import sys
from pathlib import Path

scan_path = Path(sys.argv[1])
candidates_path = Path(sys.argv[2])
domain = sys.argv[3]
protocol = None
candidates = []
protocols = {
    "HTTPS/TLS1.2": "curl_test_https_tls12",
    "HTTPS/TLS1.3": "curl_test_https_tls13",
    "HTTP": "curl_test_http",
}
for raw in scan_path.read_text().splitlines():
    line = raw.strip()
    if line.startswith("# "):
        title = line[2:].split(" — ", 1)[0]
        protocol = protocols.get(title)
        continue
    if not protocol or not line.startswith("--"):
        continue
    candidates.append(f"{protocol} ipv4 {domain} : nfqws2 {line}")
    if len(candidates) == 20:
        break
if not candidates:
    raise SystemExit("В scan-отчёте не найдены поддерживаемые TLS-стратегии")
Path(candidates_path).write_text("* SUMMARY\n" + "\n".join(candidates) + "\n")
print(len(candidates))
PY
    then
        gum_notify error "Не удалось подготовить 20 стратегий для проверки"
        return 1
    fi

    "$bin_path" -w "$workers" check --from-file "$candidates_file" -d "$domain" \
        --take 1 --passes 3 -o "$check_file" || {
        gum_notify warn "blockcheckw не подтвердил стратегию для $domain; конфиг не изменён"
        return 1
    }
    [ -s "$check_file" ] || {
        gum_notify warn "blockcheckw завершился без отчёта проверки; конфиг не изменён"
        return 1
    }

    strategy=$(python3 - "$check_file" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)
for item in data.get("strategies", []):
    args = " ".join(str(item.get("args", "")).split())
    if args and float(item.get("success_rate", 0)) >= 1.0:
        print(args)
        break
PY
    ) || true

    [ -n "$strategy" ] || {
        gum_notify warn "Стабильная стратегия для $domain не найдена"
        return 1
    }
    [[ "$strategy" != *$'\n'* && "$strategy" != *$'\r'* &&
        "$strategy" != *'"'* && "$strategy" != *'`'* && "$strategy" != *'$'* ]] || {
        gum_notify error "Отчёт содержит недопустимую стратегию"
        return 1
    }

    print_header "Найдена рабочая стратегия" "info"
    printf '%s\n' "$strategy"
    gum style --foreground 3 "Будет создан или обновлён приоритетный TCP-профиль для этого домена."
    gum style --foreground 240 "Общие профили и стратегии остальных доменов останутся без изменений."
    gum_confirm "Применить стратегию для $domain и перезапустить сервис?" || return 0
    _bcw_apply_strategy "$domain" "$strategy" || {
        gum_notify error "Не удалось применить стратегию для $domain"
        return 1
    }
    gum_notify success "Стратегия для $domain применена"
    pause
}

action_run_blockcheckw() {
    local bin_path="$PRODUCT_DIR/blockcheckw/blockcheckw"
    if [ ! -x "$bin_path" ]; then
        gum_confirm "blockcheckw не установлен. Установить?" || return 1
        action_install_blockcheckw || return 1
    fi

    local saved_workers
    saved_workers="$(_bcw_workers)"
    local domain_list subcmd workers domain timeout_s
    subcmd="$(ui_choose_one "Режим проверки" "scan — подбор для одного домена" "universal — общие стратегии для списка" "status — проверка текущего zapret2" "Назад")" || return 0
    case "$subcmd" in
        "scan — подбор для одного домена") subcmd=scan ;;
        "universal — общие стратегии для списка") subcmd=universal ;;
        "status — проверка текущего zapret2") subcmd=status ;;
        *) return 0 ;;
    esac

    local cmd_args=("$subcmd")
    if [ "$subcmd" = "scan" ]; then
        read -erp "Домен (например www.youtube.com): " domain || return 1
        [ -n "$domain" ] || { gum_notify error "Укажите домен"; return 1; }
        cmd_args+=("--domain" "$domain")
        read -erp "Таймаут скана в секундах (по умолчанию 300, 0=без лимита): " timeout_s || return 1
        timeout_s="${timeout_s:-300}"
        [[ "$timeout_s" =~ ^[0-9]+$ ]] || { gum_notify error "Введите неотрицательное целое число"; return 1; }
        cmd_args+=("--timeout" "$timeout_s")
    else
        if [ -z "$domain_list" ] || [ ! -f "$domain_list" ]; then
            read -erp "Путь к списку доменов (.txt): " domain_list || return 1
            domain_list="${domain_list/#\~/$HOME}"
        fi
        [ -f "$domain_list" ] || { gum_notify error "Файл не найден: $domain_list"; return 1; }
        cmd_args+=("--domain-list" "$domain_list")
        if [ "$subcmd" = "universal" ]; then
            local sample_n
            read -erp "Сколько доменов тестировать (по умолчанию 5): " sample_n || return 1
            sample_n="${sample_n:-5}"
            [[ "$sample_n" =~ ^[1-9][0-9]*$ ]] || { gum_notify error "Введите положительное целое число"; return 1; }
            cmd_args+=("--sample" "$sample_n")
        fi
    fi

    read -erp "Воркеров (по умолчанию $saved_workers): " workers || return 1
    workers="${workers:-$saved_workers}"
    [[ "$workers" =~ ^[1-9][0-9]*$ ]] || { gum_notify error "Введите положительное число воркеров"; return 1; }
    gum style --foreground 3 "Проверка может временно повлиять на сеть и работающий zapret2."
    gum_confirm "Начать проверку?" || return 0
    local reports_dir started
    reports_dir="$(blockcheckw_reports_dir)"
    mkdir -p "$reports_dir" || { gum_notify error "Не удалось создать папку отчётов"; return 1; }
    started=$(mktemp) || return 1
    (cd "$PRODUCT_DIR" && "$bin_path" -w "$workers" "${cmd_args[@]}") || {
        rm -f "$started"
        gum_notify warn "blockcheckw завершился с ошибкой"
        pause
        return 1
    }
    find "$PRODUCT_DIR" -maxdepth 1 -type f -newer "$started" \( -name '*_report_vanilla.txt' -o -name '*_scan.json' -o -name '*_scan.txt' -o -name '*_universal.json' -o -name '*_status.json' \) -exec mv -t "$reports_dir" {} +
    rm -f "$started"
    gum_notify info "Выполнение завершено. Отчёты: $reports_dir"
    pause
}
