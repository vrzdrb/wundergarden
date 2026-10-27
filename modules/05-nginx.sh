#!/usr/bin/env bash

hsts_line_enable() {
    local f="$CONFIG_ROOT/config/nginx/nginx.conf"
    [[ -f "$f" ]] || return 0
    sed -i '/Strict-Transport-Security/d' "$f"
    if [[ "${HSTS_ENABLED:-false}" == "true" ]]; then
        sed -i 's|^    add_header Referrer-Policy strict-origin-when-cross-origin always;$|&\n    add_header Strict-Transport-Security "max-age=31536000" always;|' "$f"
    fi
}

reload_nginx() {
    if docker ps --format '{{.Names}}' | grep -qx homeserver-nginx-1; then
        docker compose exec -T nginx nginx -s reload \
            && log "nginx перечитал конфигурацию." \
            || warn "reload не прошёл — проверьте конфиг: docker compose logs nginx (или L в меню сервиса)"
    else
        warn "nginx не запущен (пункт 3) — конфиг сохранён, применится при запуске."
    fi
}

add_site() {
    local f="$CONFIG_ROOT/config/nginx/conf.d/$1.conf"
    printf '%s\n' "$2" > "$f"
    if [[ "$(tail -n 1 "$f")" == "}" ]]; then
        sed -i '$d' "$f"
        printf '    location ~ /\\.(?!well-known) { deny all; }\n}\n' >> "$f"
    fi
    reload_nginx
}

add_stream() {
    printf '%s\n' "$2" > "$CONFIG_ROOT/config/nginx/stream.d/$1.conf"; reload_nginx
}

mk_htpasswd() {
    mkdir -p "$CONFIG_ROOT/config/nginx/htpasswd"
    printf '%s:%s\n' "$2" "$(openssl passwd -apr1 "$3")" > "$CONFIG_ROOT/config/nginx/htpasswd/$1"
    chmod 640 "$CONFIG_ROOT/config/nginx/htpasswd/$1" || true
}

auth_conf() {
    printf '        auth_basic "%s";\n        auth_basic_user_file /etc/nginx/htpasswd/%s;\n' "$2" "$1"
}

dns_hint() {
    if ! getent ahosts "$1" >/dev/null 2>&1; then
        warn "$1 не резолвится — сертификат не выпустится/не пройдёт проверка, пока нет A-записи на ваш IP."
    fi
}

front_nginx_menu() {
    while true; do
        clear
        cat <<SUM

 --- nginx и сертификаты ---
  1. Сертификаты — делать ПЕРВЫМ
  2. Запуск nginx, stream-домены, полный конфиг
  3. Перечитать конфигурацию

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_BACK)" c || true
        case "$c" in
            1) certs_menu ;;
            2) nginx_menu ;;
            3) reload_nginx ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

certs_menu() {
    log "=== Сертификаты (acme.sh, wildcard через DNS-01) ==="
    
    # Загружаем .env если есть
    [[ -f "$ENV_FILE" ]] && load_env
    
    # Проверяем наличие EMAIL, если нет - запрашиваем
    if [[ -z "${EMAIL:-}" ]]; then
        local domain="${DOMAIN:-}"
        if [[ -z "$domain" ]]; then
            domain=$(ask "Ваш домен" "")
            [[ -n "$domain" ]] && update_env DOMAIN "$domain"
        fi
        EMAIL=$(ask "Email для Let's Encrypt" "admin@$domain")
        update_env EMAIL "$EMAIL"
    fi
    
    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        ask_yn "Установить acme.sh?" || return 0
        curl -fsSL https://get.acme.sh | sh -s email="$EMAIL" || die "установка acme.sh не удалась"
    fi
    
    local prov="${ACME_DNS_PROVIDER:-dns_cf}"
    echo "${c_txt}DNS-провайдер acme.sh (код модуля): dns_cf (Cloudflare), dns_selectel, dns_desec, dns_hetzner,${c_off}"
    echo "${c_txt}  dns_yandex, dns_regru... Полный список: https://github.com/acmesh-official/acme.sh/wiki/dnsapi${c_off}"
    prov="$(ask "Код провайдера" "$prov")"
    local key1 key2
    case "$prov" in
        dns_cf)
            key1="$(ask "CF_Token (API-токен с правами DNS edit)")"
            key2="$(ask "CF_Account_ID (опционально, Enter — пропустить)" "")" ;;
        *)
            key1="$(ask "Значение первой переменной окружения провайдера (см. dnsapi wiki)")"
            key2="$(ask "Значение второй переменной (если нужна, иначе Enter)" "")" ;;
    esac
    update_env ACME_DNS_PROVIDER "$prov"
    mkdir -p "$CONFIG_ROOT/config/nginx/certs"

    export CF_Token="$key1" CF_Account_ID="$key2"
    log "Выпускаю сертификат для $DOMAIN и *.$DOMAIN (DNS-01)..."
    "$HOME/.acme.sh/acme.sh" --issue --dns "$prov" -d "$DOMAIN" -d "*.$DOMAIN" --server letsencrypt \
        || die "выпуск не удался — проверьте DNS API credentials и propagation"

    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --fullchain-file "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" \
        --key-file "$CONFIG_ROOT/config/nginx/certs/privkey.pem" \
        --reloadcmd "cd $CONFIG_ROOT && docker compose exec -T nginx nginx -s reload" \
        && chmod 600 "$CONFIG_ROOT/config/nginx/certs/privkey.pem"
    log "Сертификаты установлены в config/nginx/certs/."
    log "Продление: acme.sh cron (автоматически), reload nginx встроен в --reloadcmd."
    [[ -f "$ENV_FILE" ]] && update_env CERT_ISSUED "yes"
}

nginx_up() {
    if ss -tln | grep -qE ':(80|443|64738)\s'; then
        ss -tlnp | grep -E ':(80|443|64738)\s' >&2 || true
        warn "часть портов занята (см. выше) — если это ваш stream-терминатор, продолжаем."
    fi
    [[ -f "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" ]] \
        || warn "сертификаты не найдены — сначала пункт 3 (acme.sh)."
    docker compose up -d nginx
    sleep 2
    if docker compose exec -T nginx nginx -V 2>&1 | grep -q stream_ssl_preread; then
        log "stream_ssl_preread: поддерживается."
    else
        warn "образ nginx без stream_ssl_preread — SNI-роутинг не заработает; нужен образ с --with-stream_ssl_preread_module."
    fi
    reload_nginx
}

nginx_menu() {
    ensure_prepared
    log "=== nginx (веб-фасад) ==="
    while true; do
        local st; st=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -qx homeserver-nginx-1 && echo "запущен" || echo "не запущен")
        clear
        cat <<SUM

${c_mag} --- nginx: $st ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Запустить / перезапустить${c_off}
  ${c_num}2.${c_off} ${c_txt}Stream-пасsthrough домены: ${STREAM_DOMAINS:-нет}${c_off}
  ${c_num}3.${c_off} ${c_txt}Показать полный текущий конфиг${c_off}
  ${c_num}4.${c_off} ${c_txt}HSTS: $(onoff "${HSTS_ENABLED:-false}")${c_off}
  Порты: 80, 443,
         64738.

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_NGINX)" c || true
        case "$c" in
            1)
                if ss -tln | grep -qE ':(80|443|64738)\s'; then
                    ss -tlnp | grep -E ':(80|443|64738)\s' >&2 || true
                    warn "часть портов занята (см. выше) — если это ваш stream-терминатор, продолжаем."
                fi
                [[ -f "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" ]] \
                    || warn "сертификаты не найдены — сначала пункт 3 (acme.sh)."
                docker compose up -d nginx
                sleep 2
                if docker compose exec -T nginx nginx -V 2>&1 | grep -q stream_ssl_preread; then
                    log "stream_ssl_preread: поддерживается."
                else
                    warn "образ nginx без stream_ssl_preread — SNI-роутинг не заработает; нужен образ, собранный с --with-stream_ssl_preread_module."
                fi
                reload_nginx ;;
            4)
                if [[ "${HSTS_ENABLED:-false}" == "true" ]]; then
                    HSTS_ENABLED="false"
                else
                    echo "${c_txt}HSTS: браузеры будут ОБЯЗАНЫ ходить по HTTPS год. Откат, если HTTPS сломается,${c_off}"
                    echo "${c_txt}возможен только через max-age=0 на работающем HTTPS. includeSubDomains/preload НЕ включаем.${c_off}"
                    ask_yn "Включить HSTS?" && HSTS_ENABLED="true" || HSTS_ENABLED="false"
                fi
                update_env HSTS_ENABLED "$HSTS_ENABLED"
                hsts_line_enable
                reload_nginx
                log "HSTS: $(onoff "$HSTS_ENABLED")" ;;
            3)
                if docker ps --format '{{.Names}}' | grep -qx homeserver-nginx-1; then
                    if command -v less >/dev/null 2>&1; then
                        docker compose exec -T nginx nginx -T 2>&1 | less
                    else
                        docker compose exec -T nginx nginx -T 2>&1
                    fi
                else
                    warn "nginx не запущен — сначала действие 1."
                fi
                read -rp "$(_t BACK)" _ || true ;;
            2)
                echo "${c_txt}Домены, TLS которых должен проходить насквозь (SNI -> loopback-порт внешнего терминатора).${c_off}"
                echo "${c_txt}Формат записи: домен:порт (через запятую). Терминатор слушает на loopback хоста.${c_off}"
                echo "${c_txt}Текущий список: ${STREAM_DOMAINS:-пусто}${c_off}"
                local lst; lst="$(ask "Новый список (пусто — очистить)" "${STREAM_DOMAINS:-}")"
                lst="${lst// /}"
                local entry_clean="" e d p
                IFS=','; for e in $lst; do
                    [[ -z "$e" ]] && continue
                    d="${e%%:*}"; p="${e##*:}"; [[ "$p" == "$d" ]] && p="8444"
                    if [[ "$d" =~ ^[a-z0-9.-]+$ && "$p" =~ ^[0-9]+$ && "$p" -le 65535 ]]; then
                        entry_clean+="${entry_clean:+,}$d:$p"
                    else
                        warn "пропускаю некорректную запись '$e' (нужно домен:порт)"
                    fi
                done; unset IFS
                lst="$entry_clean"; update_env STREAM_DOMAINS "$lst"
                {
                    echo "${c_txt}map \$ssl_preread_server_name \$stream_upstream {${c_off}"
                    local entry d p
                    IFS=','; for entry in $lst; do
                        [[ -z "$entry" ]] && continue
                        d="${entry%%:*}"; p="${entry##*:}"
                        [[ "$p" == "$d" ]] && p="8444"
                        printf '    %-40s host_passthrough_%s;\n' "$d" "$p"
                    done; unset IFS
                    echo "${c_txt}    default web_tls;${c_off}"
                    echo "${c_txt}}${c_off}"
                    echo "${c_txt}upstream web_tls { server 127.0.0.1:8443; }${c_off}"
                    IFS=','; for entry in $lst; do
                        [[ -z "$entry" ]] && continue
                        p="${entry##*:}"; [[ "$p" == "$entry" ]] && p="8444"
                        printf 'upstream host_passthrough_%s { server host.docker.internal:%s; }\n' "$p" "$p"
                    done; unset IFS
                } > "$CONFIG_ROOT/config/nginx/stream.d/00-map.conf"
                reload_nginx
                log "00-map.conf пересобран: ${STREAM_DOMAINS:-(пусто)}." ;;
            5)
                docker compose logs --tail=50 nginx 2>&1 | tail -n 50 || true
                read -rp "$(_t BACK)" _ || true ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}
