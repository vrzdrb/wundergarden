#!/usr/bin/env bash

NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_CONFIG_DIR="$CONFIG_ROOT/config/nginx"

hsts_line_enable() {
    [[ -f "$NGINX_CONF" ]] || return 0
    sed -i '/Strict-Transport-Security/d' "$NGINX_CONF"
    if [[ "${HSTS_ENABLED:-false}" == "true" ]]; then
        if grep -q '^    add_header Referrer-Policy strict-origin-when-cross-origin always;$' "$NGINX_CONF"; then
            sed -i 's|^    add_header Referrer-Policy strict-origin-when-cross-origin always;$|&\n    add_header Strict-Transport-Security "max-age=31536000" always;|' "$NGINX_CONF"
        else
            warn "HSTS не добавлен: строка Referrer-Policy не найдена в $NGINX_CONF"
        fi
    fi
}

reload_nginx() {
    if systemctl is-active --quiet nginx; then
        nginx -t 2>/dev/null && systemctl reload nginx \
            && log "nginx перечитал конфигурацию." \
            || warn "reload не прошёл — проверьте конфиг: journalctl -u nginx"
    else
        warn "nginx не запущен — сначала установите (пункт 2 в подменю)."
    fi
}

install_nginx_host() {
    if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
        log "nginx уже установлен: $(nginx -v 2>&1)"
        return 0
    fi

    log "Устанавливаю nginx-full из репозитория Debian..."
    apt-get update -qq
    apt-get install -y -qq nginx-full

    # Проверяем наличие нужных модулей
    if nginx -V 2>&1 | grep -q 'with-stream'; then
        log "Модуль stream: присутствует"
    else
        die "nginx собран без модуля stream"
    fi
    if nginx -V 2>&1 | grep -q 'with-stream_ssl_preread_module'; then
        log "Модуль stream_ssl_preread: присутствует"
    else
        die "nginx собран без модуля stream_ssl_preread"
    fi

    # Создаём директории
    mkdir -p "$NGINX_CONFIG_DIR"/{conf.d,stream.d,htpasswd,certs}
    mkdir -p /var/log/nginx

    # Генерируем nginx.conf
    cat > "$NGINX_CONF" <<NGXEOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    server_tokens off;
    client_max_body_size 512m;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    limit_req_zone \$binary_remote_addr zone=perip:10m rate=10r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:10m;

    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;
    keepalive_requests 1000;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Permissions-Policy "geolocation=()" always;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 127.0.0.1:8443 ssl default_server;
        listen [::1]:8443 ssl default_server;
        ssl_certificate     $NGINX_CONFIG_DIR/certs/fullchain.pem;
        ssl_certificate_key $NGINX_CONFIG_DIR/certs/privkey.pem;
        return 444;
    }

    include $NGINX_CONFIG_DIR/conf.d/*.conf;
}

stream {
    error_log /var/log/nginx/stream-error.log;
    include $NGINX_CONFIG_DIR/stream.d/*.conf;

    server {
        listen 443;
        listen [::]:443;
        proxy_pass \$stream_upstream;
        ssl_preread on;
    }
}
NGXEOF

    # IPv6 может быть отключён на хосте — тогда listen на [::] приведёт
    # к ошибке bind() и nginx -t не пройдёт. Убираем IPv6-строки.
    if [[ ! -f /proc/net/if_inet6 ]]; then
        sed -i '/listen \[::/d' "$NGINX_CONF"
        log "IPv6 не обнаружен — IPv6-директивы listen удалены из конфига"
    fi

    # Создаём базовые include-файлы
    cat > "$NGINX_CONFIG_DIR/proxy_common.conf" <<'NGXEOF'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_read_timeout 3600s;
proxy_hide_header Server;
proxy_hide_header X-Powered-By;
limit_req zone=perip burst=100 nodelay;
limit_conn addr 20;
NGXEOF

    cat > "$NGINX_CONFIG_DIR/ws_common.conf" <<'NGXEOF'
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
NGXEOF

    # Базовый stream-маппинг (заполняется через меню)
    cat > "$NGINX_CONFIG_DIR/stream.d/00-map.conf" <<'NGXEOF'
map $ssl_preread_server_name $stream_upstream {
    default web_tls;
}
upstream web_tls { server 127.0.0.1:8443; }
NGXEOF

    # Права на директории
    chown -R root:www-data "$NGINX_CONFIG_DIR"
    chmod 750 "$NGINX_CONFIG_DIR/certs"

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp comment 'nginx HTTP' >/dev/null 2>&1 || true
        ufw allow 443/tcp comment 'nginx HTTPS' >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
        log "UFW: порты 80/tcp и 443/tcp открыты"
    fi

    # Тест конфига и запуск
    if [[ -f "$NGINX_CONFIG_DIR/certs/fullchain.pem" && -f "$NGINX_CONFIG_DIR/certs/privkey.pem" ]]; then
        nginx -t 2>&1 || die "nginx: ошибка в конфигурации"
        systemctl enable --now nginx
        log "nginx установлен и запущен: $(nginx -v 2>&1)"
    else
        warn "Сертификаты ещё не найдены в $NGINX_CONFIG_DIR/certs — nginx установлен, но не запущен."
        warn "Сначала выпустите сертификаты (пункт 1), затем запустите nginx вручную или повторите установку."
        nginx -t 2>&1 || warn "nginx: конфиг ещё не валиден до появления сертификатов"
        systemctl enable nginx 2>/dev/null || true
    fi

    read -rp "Enter — продолжить " _ || true
}

add_site() {
    local f="$NGINX_CONFIG_DIR/conf.d/$1.conf"
    printf '%s\n' "$2" > "$f"
    if [[ "$(tail -n 1 "$f")" == "}" ]]; then
        sed -i '$d' "$f"
        printf '    location ~ /\.(?!well-known) { deny all; }\n}\n' >> "$f"
    fi
    reload_nginx
}

add_stream() {
    printf '%s\n' "$2" > "$NGINX_CONFIG_DIR/stream.d/$1.conf"; reload_nginx
}

mk_htpasswd() {
    mkdir -p "$NGINX_CONFIG_DIR/htpasswd"
    printf '%s:%s\n' "$2" "$(openssl passwd -apr1 "$3")" > "$NGINX_CONFIG_DIR/htpasswd/$1"
    chmod 640 "$NGINX_CONFIG_DIR/htpasswd/$1" || true
}

auth_conf() {
    printf '        auth_basic "%s";\n        auth_basic_user_file %s/htpasswd/%s;\n' "$2" "$NGINX_CONFIG_DIR" "$1"
}

dns_hint() {
    if ! getent ahosts "$1" >/dev/null 2>&1; then
        warn "$1 не резолвится — сертификат не выпустится/не пройдёт проверку, пока нет A-записи на ваш IP."
    fi
}

find_certificates() {
    local cert_dir="$NGINX_CONFIG_DIR/certs"
    echo "${c_txt}Путь к сертификатам: ${cert_dir}${c_off}"
    if [[ -f "$cert_dir/fullchain.pem" || -f "$cert_dir/privkey.pem" ]]; then
        ls -l "$cert_dir" 2>/dev/null || true
    else
        warn "Сертификаты в текущем каталоге не найдены."
        warn "Проверьте: $cert_dir"
    fi
    if [[ -d "$HOME/.acme.sh" ]]; then
        echo "${c_txt}acme.sh данные: $HOME/.acme.sh${c_off}"
    fi
    read -rp "Enter — продолжить " _ || true
}

remove_nginx_keep_certs() {
    local cert_dir="$NGINX_CONFIG_DIR/certs"
    local backup_dir="/var/backups/wundergarden-nginx-certs-$(date +%s)"

    if [[ -d "$cert_dir" ]]; then
        mkdir -p "$backup_dir"
        cp -a "$cert_dir/." "$backup_dir/" 2>/dev/null || true
        log "Сертификаты сохранены в резервную копию: $backup_dir"
    fi

    systemctl disable --now nginx 2>/dev/null || true
    apt-get purge -y nginx nginx-common nginx-full 2>/dev/null || apt-get remove --purge -y nginx* 2>/dev/null || true
    rm -rf /etc/nginx /var/lib/nginx /var/log/nginx 2>/dev/null || true

    if [[ -d "$NGINX_CONFIG_DIR" ]]; then
        rm -rf "$NGINX_CONFIG_DIR/conf.d" "$NGINX_CONFIG_DIR/stream.d" "$NGINX_CONFIG_DIR/htpasswd" "$NGINX_CONFIG_DIR/proxy_common.conf" "$NGINX_CONFIG_DIR/ws_common.conf"
        mkdir -p "$NGINX_CONFIG_DIR/certs"
    fi

    log "nginx удалён из системы; сертификаты сохранены и каталог certs оставлен в $NGINX_CONFIG_DIR/certs"
    read -rp "Enter — продолжить " _ || true
}

watch_nginx_logs() {
    if [[ -f /var/log/nginx/error.log || -f /var/log/nginx/access.log ]]; then
        tail -n 30 -F /var/log/nginx/error.log /var/log/nginx/access.log
    else
        journalctl -u nginx -n 30 -f
    fi
}

# Сопоставление кода провайдера acme.sh с именами переменных окружения.
# Возвращает список пар "VAR=значение" в stdout.
acme_creds() {
    local prov="$1" key1="$2" key2="$3"
    case "$prov" in
        dns_cf)        printf 'CF_Token=%s\n' "$key1"; [[ -n "$key2" ]] && printf 'CF_Account_ID=%s\n' "$key2" ;;
        dns_hetzner)   printf 'HETZNER_Token=%s\n' "$key1" ;;
        dns_desec)     printf 'DESECRETE=%s\n' "$key1" ;;
        dns_selectel)  printf 'SELECTEL_API_TOKEN=%s\n' "$key1" ;;
        dns_regru)     printf 'REGRU_API_USERNAME=%s\nREGRU_API_PASSWORD=%s\n' "$key1" "$key2" ;;
        dns_yandex)    printf 'YANDEX_TOKEN=%s\n' "$key1" ;;
        *)
            # Неизвестный провайдер: спрашиваем имена переменных у пользователя
            local v1 v2
            v1="$(ask "Имя переменной окружения для первого ключа (см. dnsapi wiki)")"
            [[ -n "$v1" ]] && printf '%s=%s\n' "$v1" "$key1"
            if [[ -n "$key2" ]]; then
                v2="$(ask "Имя переменной окружения для второго ключа")"
                [[ -n "$v2" ]] && printf '%s=%s\n' "$v2" "$key2"
            fi ;;
    esac
}

# Экспортирует креды в текущую сессию и сохраняет в account.conf
# (acme.sh подгружает account.conf при продлении по cron).
apply_acme_creds() {
    local creds="$1" pair var val
    while IFS= read -r pair; do
        [[ -z "$pair" ]] && continue
        var="${pair%%=*}"; val="${pair#*=}"
        export "$var=$val"
        if [[ -f "$HOME/.acme.sh/account.conf" ]]; then
            # Обновляем существующую запись или добавляем новую
            if grep -q "^export ${var}=" "$HOME/.acme.sh/account.conf"; then
                sed -i "s|^export ${var}=.*|export ${var}='${val}'|" "$HOME/.acme.sh/account.conf"
            else
                printf "export %s='%s'\n" "$var" "$val" >> "$HOME/.acme.sh/account.conf"
            fi
        fi
    done <<< "$creds"
}

front_nginx_menu() {
    while true; do
        local st; st=$(systemctl is-active nginx 2>/dev/null || echo "не установлен")
        [[ "$st" == "active" ]] && st="запущен" || st="не запущен"
        clear
        cat <<SUM

${c_mag} --- nginx и сертификаты: $st ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Сертификаты — делать ПЕРВЫМ${c_off}
  ${c_num}2.${c_off} ${c_txt}Установить nginx на хост${c_off}
  ${c_num}3.${c_off} ${c_txt}Перезапустить nginx${c_off}
  ${c_num}4.${c_off} ${c_txt}Stream-passthrough домены: ${STREAM_DOMAINS:-нет}${c_off}
  ${c_num}5.${c_off} ${c_txt}Показать полный текущий конфиг${c_off}
  ${c_num}6.${c_off} ${c_txt}HSTS: $(onoff "${HSTS_ENABLED:-false}")${c_off}
  ${c_num}7.${c_off} ${c_txt}Перечитать конфигурацию${c_off}
  ${c_num}8.${c_off} ${c_txt}Найти сертификаты${c_off}
  ${c_num}9.${c_off} ${c_txt}Удалить nginx, оставив сертификаты${c_off}
  ${c_num}10.${c_off} ${c_txt}Смотреть логи nginx${c_off}
  ${c_txt}Порты: 80, 443${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "Выбор: " c || return 0
        [[ -z "$c" ]] && continue
        case "$c" in
            1) certs_menu ;;
            2) install_nginx_host ;;
            3)
                if ! command -v nginx >/dev/null 2>&1; then
                    warn "nginx не установлен — сначала пункт 2."
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi
                if ss -tln | grep -qE ':(80|443)\s'; then
                    ss -tlnp | grep -E ':(80|443)\s' >&2 || true
                    warn "часть портов занята (см. выше) — продолжаем."
                fi
                [[ -f "$NGINX_CONFIG_DIR/certs/fullchain.pem" ]] \
                    || warn "сертификаты не найдены — сначала пункт 1."
                systemctl restart nginx
                sleep 1
                if systemctl is-active --quiet nginx; then
                    log "nginx перезапущен"
                else
                    warn "nginx не запустился — journalctl -u nginx"
                fi
                ;;
            4)
                echo "${c_txt}Домены, TLS которых должен проходить насквозь (SNI -> loopback-порт).${c_off}"
                echo "${c_txt}Формат записи: домен:порт (через запятую).${c_off}"
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
                    echo "map \$ssl_preread_server_name \$stream_upstream {"
                    local entry d p seen_ports=""
                    IFS=','; for entry in $lst; do
                        [[ -z "$entry" ]] && continue
                        d="${entry%%:*}"; p="${entry##*:}"
                        printf '    %-40s host_passthrough_%s;\n' "$d" "$p"
                    done; unset IFS
                    echo "    default web_tls;"
                    echo "}"
                    echo "upstream web_tls { server 127.0.0.1:8443; }"
                    IFS=','; for entry in $lst; do
                        [[ -z "$entry" ]] && continue
                        p="${entry##*:}"
                        # Дедупликация upstream'ов по порту
                        [[ ":$seen_ports:" == *":$p:"* ]] && continue
                        seen_ports+="${seen_ports:+:}$p"
                        printf 'upstream host_passthrough_%s { server 127.0.0.1:%s; }\n' "$p" "$p"
                    done; unset IFS
                } > "$NGINX_CONFIG_DIR/stream.d/00-map.conf"
                reload_nginx
                log "00-map.conf пересобран: ${STREAM_DOMAINS:-(пусто)}." ;;
            5)
                if command -v nginx >/dev/null 2>&1; then
                    if command -v less >/dev/null 2>&1; then
                        nginx -T 2>&1 | less
                    else
                        nginx -T 2>&1
                    fi
                else
                    warn "nginx не установлен"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            6)
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
            7) reload_nginx ;;
            8) find_certificates ;;
            9) remove_nginx_keep_certs ;;
            10) watch_nginx_logs ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

certs_menu() {
    log "=== Сертификаты (acme.sh, wildcard через DNS-01) ==="

    [[ -f "$ENV_FILE" ]] && load_env

    if [[ -z "${DOMAIN:-}" ]]; then
        local domain_input
        domain_input=$(ask "Ваш домен (например: example.com)" "")
        if [[ -n "$domain_input" ]]; then
            export DOMAIN="$domain_input"
            update_env DOMAIN "$domain_input"
        else
            die "Домен не указан - невозможно выпустить сертификат"
        fi
    fi

    if [[ -z "${EMAIL:-}" ]]; then
        EMAIL=$(ask "Email для Let's Encrypt" "admin@$DOMAIN")
        export EMAIL
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
    mkdir -p "$NGINX_CONFIG_DIR/certs"

    # Экспортируем креды под именами переменных провайдера и сохраняем
    # в account.conf, чтобы продление по cron работало без интерактива.
    local creds; creds="$(acme_creds "$prov" "$key1" "$key2")"
    [[ -n "$creds" ]] || die "креды провайдера $prov не заданы"
    apply_acme_creds "$creds"

    dns_hint "$DOMAIN"

    local cert_dir="$NGINX_CONFIG_DIR/certs"
    local cert_exists=false
    if [[ -f "$cert_dir/fullchain.pem" && -f "$cert_dir/privkey.pem" ]]; then
        cert_exists=true
        echo "${c_txt}Сертификаты уже существуют: $cert_dir${c_off}"
        ls -l "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem" 2>/dev/null || true
        ask_yn "Перевыпустить/обновить сертификаты сейчас?" || return 0
    fi

    # Формируем reloadcmd: выставляет права и перезагружает nginx
    local reloadcmd="chown root:www-data ${NGINX_CONFIG_DIR}/certs/privkey.pem && chmod 640 ${NGINX_CONFIG_DIR}/certs/privkey.pem && chown root:www-data ${NGINX_CONFIG_DIR}/certs/fullchain.pem && chmod 644 ${NGINX_CONFIG_DIR}/certs/fullchain.pem && (systemctl reload nginx || true)"

    log "Выпускаю сертификат для $DOMAIN и *.$DOMAIN (DNS-01)..."
    if [[ "$cert_exists" == true ]]; then
        "$HOME/.acme.sh/acme.sh" --renew -d "$DOMAIN" -d "*.$DOMAIN" --dns "$prov" --server letsencrypt --force \
            || "$HOME/.acme.sh/acme.sh" --issue --dns "$prov" -d "$DOMAIN" -d "*.$DOMAIN" --server letsencrypt --force \
            || die "перевыпуск не удался — проверьте DNS API credentials и propagation"
    else
        "$HOME/.acme.sh/acme.sh" --issue --dns "$prov" -d "$DOMAIN" -d "*.$DOMAIN" --server letsencrypt \
            || die "выпуск не удался — проверьте DNS API credentials и propagation"
    fi

    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --fullchain-file "$NGINX_CONFIG_DIR/certs/fullchain.pem" \
        --key-file "$NGINX_CONFIG_DIR/certs/privkey.pem" \
        --reloadcmd "$reloadcmd" \
        && log "Сертификаты установлены, права выставлены, nginx перезагружен."

    # Выставляем права сразу (на случай если reloadcmd не сработал при первом --install-cert)
    chown root:www-data "$NGINX_CONFIG_DIR/certs/privkey.pem"
    chmod 640 "$NGINX_CONFIG_DIR/certs/privkey.pem"
    chown root:www-data "$NGINX_CONFIG_DIR/certs/fullchain.pem"
    chmod 644 "$NGINX_CONFIG_DIR/certs/fullchain.pem"

    if [[ -f "$NGINX_CONFIG_DIR/certs/fullchain.pem" && -f "$NGINX_CONFIG_DIR/certs/privkey.pem" ]]; then
        log "✓ Оба файла сертификатов существуют"
        [[ -f "$ENV_FILE" ]] && update_env CERT_ISSUED "yes"

        if systemctl is-active --quiet nginx; then
            nginx -t 2>/dev/null && systemctl reload nginx \
                && log "nginx перезагружен" \
                || warn "Не удалось перезагрузить nginx"
        else
            echo "${c_txt}ℹ nginx ещё не запущен${c_off}"
            echo "${c_txt}  После установки nginx (пункт 2) сертификаты будут использованы автоматически.${c_off}"
            echo "${c_txt}  Продление сертификатов: acme.sh cron (автоматически)${c_off}"
        fi
    else
        warn "Некоторые файлы сертификатов не найдены!"
        [[ ! -f "$NGINX_CONFIG_DIR/certs/fullchain.pem" ]] && warn "  - Отсутствует: fullchain.pem"
        [[ ! -f "$NGINX_CONFIG_DIR/certs/privkey.pem" ]] && warn "  - Отсутствует: privkey.pem"
    fi

    read -rp "Enter — продолжить " _ || true
}
