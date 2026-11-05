#!/usr/bin/env bash

JITSI_DIR="$CONFIG_ROOT/jitsi"
JITSI_CFG="$CONFIG_ROOT/data/jitsi-cfg"
JITSI_TOKEN_DIR="$CONFIG_ROOT/jitsi-token-server"

jitsi_dc() {
    local files=(-f docker-compose.yml)
    [[ -f "$JITSI_DIR/docker-compose.override.yml" ]] && files+=(-f docker-compose.override.yml)
    [[ -f "$JITSI_DIR/coturn.yml" ]] && files+=(-f coturn.yml)
    [[ -f "$JITSI_DIR/web-certs.yml" ]] && files+=(-f web-certs.yml)
    ( cd "$JITSI_DIR" && docker compose "${files[@]}" "$@" )
}

jitsi_set_env() {
    local key="$1" val="$2"
    ( cd "$JITSI_DIR" && { grep -v "^${key}=" .env || true; echo "${key}=${val}"; } > .env.tmp.$$ && mv .env.tmp.$$ .env )
}

jitsi_get_env() { ( cd "$JITSI_DIR" && grep "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- ); }

_jitsi_gen_harden_override() {
    cat > "$JITSI_DIR/docker-compose.override.yml" <<'EOF'
services:
  web:     { pids_limit: 400 }
  prosody: { pids_limit: 400 }
  jicofo:  { pids_limit: 400 }
  jvb:     { pids_limit: 400 }
EOF
}

rebuild_stream_map() {
    local lst="${STREAM_DOMAINS:-}"
    local map_file="$NGINX_CONFIG_DIR/stream.d/00-map.conf"
    {
        echo "map \\$ssl_preread_server_name \\$stream_upstream {"
        local entry d p seen_ports=""
        if [[ -n "$lst" ]]; then
            IFS=','; for entry in $lst; do
                [[ -z "$entry" ]] && continue
                d="${entry%%:*}"; p="${entry##*:}"
                printf '    %-40s host_passthrough_%s;\n' "$d" "$p"
            done; unset IFS
        fi
        echo "    default web_tls;"
        echo "}"
        echo "upstream web_tls { server 127.0.0.1:8443; }"
        if [[ -n "$lst" ]]; then
            IFS=','; for entry in $lst; do
                [[ -z "$entry" ]] && continue
                p="${entry##*:}"
                [[ ":$seen_ports:" == *":$p:"* ]] && continue
                seen_ports+="${seen_ports:+:}$p"
                printf 'upstream host_passthrough_%s { server 127.0.0.1:%s; }\n' "$p" "$p"
            done; unset IFS
        fi
    } > "$map_file"
}

install_jitsi() {
    ensure_prepared
    check_dependencies
    log "=== Jitsi Meet (видеоконференции) ==="
    [[ -d "$JITSI_DIR" ]] && { ask_yn "Обнаружена установка в $JITSI_DIR — переустановить? Конфиг сохранится." || return 0; }

    local subdomain domain pub_ip mode turn_src tz jitsi_port proxy_port
    [[ -z "${DOMAIN:-}" ]] && { warn "DOMAIN не задан в .env"; return 1; }
    while true; do
        subdomain="$(ask "Поддомен для Jitsi" "meet")"
        [[ "$subdomain" =~ ^[a-z0-9-]+$ ]] && break
        warn "некорректный поддомен"
    done
    domain="${subdomain}.${DOMAIN}"
    pub_ip="$(ask "Публичный IP (JVB_ADVERTISE_IPS)" "${PUBLIC_IP:-}")"
    [[ -z "$pub_ip" ]] && { warn "IP обязателен"; return 1; }

    echo "${c_txt}Режим доступа:${c_off}"
    echo "  1) За nginx (nginx терминирует TLS; Jitsi на loopback HTTP) [по умолчанию]"
    echo "  2a) Прямой HTTPS (Jitsi терминирует TLS сам, порт на 0.0.0.0)"
    echo "  2b) Stream passthrough (внешний прокси терминирует TLS; nginx → прокси-порт → Jitsi HTTP)"
    mode="$(ask "1 / 2a / 2b" "1")"
    [[ "$mode" == "2" ]] && mode="2a"

    case "$mode" in
        1)
            jitsi_port="$(ask "Локальный HTTP-порт Jitsi (nginx → Jitsi)" "7443")"
            proxy_port=""
            ;;
        2a)
            jitsi_port="$(ask "Локальный HTTPS-порт Jitsi (0.0.0.0, Jitsi терминирует TLS)" "8443")"
            proxy_port=""
            ;;
        2b)
            proxy_port="$(ask "Локальный порт прокси (nginx stream → прокси)" "8444")"
            jitsi_port="$(ask "Локальный HTTP-порт Jitsi (прокси → Jitsi, loopback)" "7443")"
            ;;
        *)
            warn "Неверный режим"; return 1
            ;;
    esac

    echo "${c_txt}TURN: 1) наш существующий coturn (пункт 6; общий секрет с Matrix — нормально)${c_off}"
    echo "${c_txt}     2) собственный coturn этого скрипта (host-network, 3478)${c_off}"
    turn_src="$(ask "1/2" "1")"
    [[ "$turn_src" == "1" && -z "${SUB_TURN:-}" && -z "${TURN_PASSWORD:-}" ]] && \
        warn "наш coturn ещё не установлен — сначала пункт 6 (Matrix), либо выберите '2'."
    tz="$(ask "Часовой пояс" "$TZ")"

    log "Скачиваю docker-jitsi-meet (последний релиз)..."
    local json tag zipurl topdir
    json="$(curl -fsSL https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/latest)"
    tag="$(grep '"tag_name"' <<< "$json" | cut -d'"' -f4)"
    [[ -z "$tag" ]] && die "не удалось получить тег релиза"
    zipurl="https://github.com/jitsi/docker-jitsi-meet/archive/refs/tags/${tag}.zip"
    mkdir -p "$JITSI_DIR"

    local env_bak=""
    [[ -f "$JITSI_DIR/.env" ]] && { env_bak="$(mktemp)"; cp "$JITSI_DIR/.env" "$env_bak"; }

    ( cd "$JITSI_DIR" && curl -fsSL -o jitsi.zip "$zipurl" && unzip -o -q jitsi.zip ) || die "ошибка скачивания/распаковки"
    topdir="$(find "$JITSI_DIR" -maxdepth 1 -type d -name 'docker-jitsi-meet-*' | head -1)"
    topdir="${topdir##*/}"
    [[ -z "$topdir" ]] && die "не удалось определить директорию распаковки"
    cp -a "$JITSI_DIR/$topdir"/.* "$JITSI_DIR/" 2>/dev/null || true
    cp -a "$JITSI_DIR/$topdir"/* "$JITSI_DIR/" 2>/dev/null || true
    rm -rf "$JITSI_DIR/$topdir"
    rm -f "$JITSI_DIR/jitsi.zip"
    log "Версия: $tag"
    cd "$JITSI_DIR"

    if [[ -n "$env_bak" && -f "$env_bak" ]]; then
        cp "$env_bak" .env
        rm -f "$env_bak"
    else
        [[ -f env.example ]] || die "env.example не найден в $JITSI_DIR"
        cp env.example .env
        bash gen-passwords.sh >/dev/null
        chmod 600 .env
    fi

    _jitsi_gen_harden_override

    jitsi_set_env CONFIG "$JITSI_CFG"
    jitsi_set_env TZ "$tz"
    jitsi_set_env PUBLIC_URL "https://$domain"
    jitsi_set_env JVB_ADVERTISE_IPS "$pub_ip"
    jitsi_set_env ENABLE_XMPP_WEBSOCKET 1
    jitsi_set_env ENABLE_HTTP_REDIRECT 0
    jitsi_set_env JITSI_IMAGE_VERSION "$tag"
    jitsi_set_env VIDEOBRIDGE_MAX_MEMORY "1024m"
    jitsi_set_env JICOFO_MAX_MEMORY "1024m"
    jitsi_set_env ENABLE_LETSENCRYPT 0
    jitsi_set_env JITSI_MODE "$mode"
    jitsi_set_env JITSI_PORT "$jitsi_port"
    [[ -n "$proxy_port" ]] && jitsi_set_env JITSI_PROXY_PORT "$proxy_port"

    # Настройка портов и режима в docker-compose.yml
    case "$mode" in
        1)
            jitsi_set_env HTTP_PORT "$jitsi_port"
            jitsi_set_env DISABLE_HTTPS 1
            sed -i '/HTTPS_PORT/d' docker-compose.yml
            sed -i "s|\\\${HTTP_PORT}:8000|127.0.0.1:${jitsi_port}:8000|" docker-compose.yml
            ;;
        2a)
            jitsi_set_env HTTPS_PORT "$jitsi_port"
            jitsi_set_env DISABLE_HTTPS 0
            sed -i '/HTTP_PORT/d' docker-compose.yml
            sed -i "s|\\\${HTTPS_PORT}:8443|0.0.0.0:${jitsi_port}:8443|" docker-compose.yml
            mkdir -p "$JITSI_CFG/web"
            if [[ -f "$NGINX_CONFIG_DIR/certs/fullchain.pem" && -f "$NGINX_CONFIG_DIR/certs/privkey.pem" ]]; then
                cp "$NGINX_CONFIG_DIR/certs/fullchain.pem" "$JITSI_CFG/web/"
                cp "$NGINX_CONFIG_DIR/certs/privkey.pem" "$JITSI_CFG/web/"
                chmod 644 "$JITSI_CFG/web/fullchain.pem"
                chmod 600 "$JITSI_CFG/web/privkey.pem"
            else
                warn "Сертификаты не найдены — для режима 2a нужны в $JITSI_CFG/web/"
            fi
            ;;
        2b)
            jitsi_set_env HTTP_PORT "$jitsi_port"
            jitsi_set_env DISABLE_HTTPS 1
            sed -i '/HTTPS_PORT/d' docker-compose.yml
            sed -i "s|\\\${HTTP_PORT}:8000|127.0.0.1:${jitsi_port}:8000|" docker-compose.yml
            # Stream passthrough
            local new_entry="${domain}:${proxy_port}"
            if [[ -n "${STREAM_DOMAINS:-}" ]]; then
                if [[ ",${STREAM_DOMAINS}," != *",${domain}:"* ]]; then
                    update_env STREAM_DOMAINS "${STREAM_DOMAINS},${new_entry}"
                else
                    local updated="${STREAM_DOMAINS}"
                    updated="$(echo "$updated" | sed "s|[^,]*${domain}:[0-9]*|${new_entry}|g")"
                    update_env STREAM_DOMAINS "$updated"
                fi
            else
                update_env STREAM_DOMAINS "$new_entry"
            fi
            rebuild_stream_map
            reload_nginx 2>/dev/null || true
            ;;
    esac

    if [[ "$turn_src" == "1" ]]; then
        rm -f "$JITSI_DIR/coturn.yml"
        jitsi_set_env TURN_HOST "$SUB_TURN"
        jitsi_set_env TURN_PORT 3478
        jitsi_set_env TURN_TRANSPORT "tcp,udp"
        jitsi_set_env TURN_CREDENTIALS "$TURN_PASSWORD"
    else
        local secret; secret="$(gen_pass)"
        mkdir -p "$JITSI_CFG/coturn"
        cat > "$JITSI_CFG/coturn/turnserver.conf" <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$secret
realm=$domain
min-port=49152
max-port=65535
no-multicast-peers
no-loopback-peers
no-cli
log-file=stdout
EOF
        cat > "$JITSI_DIR/coturn.yml" <<'EOF'
services:
    coturn:
        image: coturn/coturn:4.6.2
        restart: unless-stopped
        network_mode: host
        volumes:
            - ${CONFIG}/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro
EOF
        jitsi_set_env TURN_HOST "$domain"
        jitsi_set_env TURN_PORT 3478
        jitsi_set_env TURN_TRANSPORT "tcp,udp"
        jitsi_set_env TURN_CREDENTIALS "$secret"
        ( cd "$JITSI_DIR" && sed -i '/^TURNS_HOST=/d;/^TURNS_PORT=/d' .env )
    fi

    mkdir -p "$JITSI_CFG"/{web,prosody/config,jicofo,jvb}
    mkdir -p "$JITSI_CFG"/storage/{jibri,prosody}
    mkdir -p "$JITSI_CFG"/tmp/web-crontabs
    chmod -R 777 "$JITSI_CFG"/storage "$JITSI_CFG"/tmp 2>/dev/null || true

    # UFW
    require_cmd ufw ufw
    if [[ "$mode" == "2a" ]]; then
        ufw allow "$jitsi_port/tcp" comment "Jitsi HTTPS" >/dev/null 2>&1 && log "UFW: $jitsi_port/tcp открыт" || warn "Ошибка UFW"
    elif [[ "$mode" == "2b" ]]; then
        ufw allow "$proxy_port/tcp" comment "Jitsi stream passthrough" >/dev/null 2>&1 && log "UFW: $proxy_port/tcp открыт" || warn "Ошибка UFW"
    fi
    ufw allow 10000/udp comment 'Jitsi JVB media' >/dev/null 2>&1 && log "UFW: 10000/udp открыт (JVB)" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1 || true

    jitsi_dc pull
    jitsi_dc up -d || die "ошибка запуска: cd $JITSI_DIR && docker compose logs"

    if [[ "$mode" == "1" ]]; then
        add_site 150-jitsi "server {
    listen 8443 ssl;
    server_name $domain;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://127.0.0.1:${jitsi_port};
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
        include $CONFIG_ROOT/config/nginx/ws_common.conf;
        proxy_read_timeout 3600s;
    }
}"
    fi
    update_env SUB_JITSI "$domain"

    local conn_mode=""
    case "$mode" in
        1) conn_mode="nginx (https://$domain)" ;;
        2a) conn_mode="прямой HTTPS (0.0.0.0:$jitsi_port)" ;;
        2b) conn_mode="stream passthrough (прокси-порт $proxy_port → Jitsi $jitsi_port)" ;;
    esac

    show_connection_info "Jitsi Meet" \
        "URL: https://$domain" \
        "Режим: $conn_mode" \
        "TURN: $([[ "$turn_src" == "1" ]] && echo "наш coturn (turn.$DOMAIN:3478)" || echo "свой coturn (3478 host-network)")" \
        "Медиа JVB: 10000/udp (открыт в UFW)" \
        "" \
        "Комната без авторизации: любой, кто знает ссылку" \
        "Для JWT-аутентификации: меню Jitsi -> действие 2"

    log_connection_params "Jitsi Meet" \
        "URL: https://$domain" \
        "Режим: $conn_mode" \
        "TURN: $([[ "$turn_src" == "1" ]] && echo "turn.$DOMAIN:3478" || echo "свой coturn:3478")"
}

remove_jitsi() {
    [[ -d "$JITSI_DIR" ]] || { warn "Jitsi Meet не установлен"; return 1; }
    ask_yn "Удалить Jitsi Meet? Все данные будут потеряны." || return 0

    local mode domain
    mode="$(jitsi_get_env JITSI_MODE)"
    domain="$(jitsi_get_env PUBLIC_URL)"
    domain="${domain#https://}"

    jitsi_token_server_stop 2>/dev/null || true
    jitsi_dc down --volumes 2>/dev/null || true

    rm_site 150-jitsi

    # Удаляем stream passthrough если был режим 2b
    if [[ "$mode" == "2b" && -n "$domain" && -n "${STREAM_DOMAINS:-}" ]]; then
        local updated
        updated="$(echo "$STREAM_DOMAINS" | sed "s|[^,]*${domain}:[0-9]*||g")"
        updated="${updated#,}"; updated="${updated%,}"
        updated="${updated//,,/,}"
        update_env STREAM_DOMAINS "$updated"
        rebuild_stream_map
        reload_nginx 2>/dev/null || true
    fi

    local jitsi_port proxy_port
    jitsi_port="$(jitsi_get_env JITSI_PORT)"
    proxy_port="$(jitsi_get_env JITSI_PROXY_PORT)"
    if [[ "$mode" == "2a" && -n "$jitsi_port" ]]; then
        ufw delete allow "$jitsi_port/tcp" comment 'Jitsi HTTPS' >/dev/null 2>&1 || true
    elif [[ "$mode" == "2b" && -n "$proxy_port" ]]; then
        ufw delete allow "$proxy_port/tcp" comment 'Jitsi stream passthrough' >/dev/null 2>&1 || true
    fi
    ufw delete allow 10000/udp comment 'Jitsi JVB media' >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true

    if [[ -f "$JITSI_DIR/coturn.yml" ]]; then
        ask_yn "Удалить собственный coturn Jitsi?" && {
            rm -f "$JITSI_DIR/coturn.yml"
            log "Собственный coturn Jitsi удалён"
        }
    else
        log "Общий coturn (Matrix) остаётся без изменений"
    fi

    update_env SUB_JITSI ""

    rm -rf "$JITSI_DIR" "$JITSI_CFG" "$JITSI_TOKEN_DIR"
    log "Jitsi Meet удалён"
}

jitsi_toggle_udp() {
    local conf
    if [[ -f "$JITSI_DIR/coturn.yml" ]]; then
        conf="$JITSI_CFG/coturn/turnserver.conf"
        [[ -f "$conf" ]] || { warn "coturn не найден ($conf)"; return 1; }
        if grep -q '^no-udp' "$conf"; then
            sed -i '/^no-udp/d' "$conf"
            log "3478: TCP+UDP (свой coturn Jitsi)"
        else
            echo "no-udp" >> "$conf"
            log "3478: только TCP (свой coturn Jitsi)"
        fi
        jitsi_dc up -d --force-recreate coturn
    else
        conf="$DATA_DIR/coturn/turnserver.conf"
        [[ -f "$conf" ]] || { warn "общий coturn не найден ($conf)"; return 1; }
        if grep -q '^no-udp' "$conf"; then
            sed -i '/^no-udp/d' "$conf"
            log "3478: TCP+UDP (общий coturn)"
        else
            echo "no-udp" >> "$conf"
            log "3478: только TCP (общий coturn)"
        fi
        docker ps -q --filter name=coturn | xargs -r docker restart 2>/dev/null || \
            warn "Перезапустите coturn вручную (меню Matrix)"
    fi
}

jitsi_enable_jwt() {
    [[ -f "$JITSI_DIR/.env" ]] || { warn "сначала п.1 (установка)"; return 1; }
    local app_id secret
    app_id="$(ask "APP_ID" "wundergarden")"
    secret="$(gen_pass)"
    jitsi_set_env ENABLE_AUTH 1
    jitsi_set_env AUTH_TYPE jwt
    jitsi_set_env JWT_APP_ID "$app_id"
    jitsi_set_env JWT_APP_SECRET "$secret"
    jitsi_set_env ENABLE_GUESTS 1
    jitsi_token_server_stop 2>/dev/null || true
    rm -f "$JITSI_TOKEN_DIR/run.sh"
    jitsi_dc up -d --force-recreate
    log "JWT включён. APP_ID=$app_id | APP_SECRET=$secret (сохраните)"
    log "Выдача токенов: см. исходный jitsi-auto.sh (Flask-сервер) — добавлю по запросу."
}

install_jitsi_entry() { install_jitsi; }

jitsi_token_server_running() {
    [[ -f "$JITSI_TOKEN_DIR/server.pid" ]] && kill -0 "$(cat "$JITSI_TOKEN_DIR/server.pid")" 2>/dev/null
}

jitsi_token_key_ensure() {
    local key; key="$(jitsi_get_env JITSI_TOKEN_KEY)"
    if [[ -z "$key" ]]; then
        key="$(gen_pass)"
        jitsi_set_env JITSI_TOKEN_KEY "$key"
        log "Ключ доступа к token-серверу (показан ОДИН раз, сохраните): $key"
        warn "Ключ уже хранится в .env (chmod 600) — issue_token использует его автоматически."
    fi
}

jitsi_token_server_start() {
    [[ -f "$JITSI_DIR/.env" ]] || { warn "сначала п.1 (установка)"; return 1; }
    jitsi_token_key_ensure
    mkdir -p "$JITSI_TOKEN_DIR"
    if [[ ! -d "$JITSI_TOKEN_DIR/venv" ]]; then
        log "Подготовка Python-окружения (venv + flask + pyjwt)..."
        apt-get install -y -qq python3-venv >/dev/null 2>&1 || warn "python3-venv не установился"
        python3 -m venv "$JITSI_TOKEN_DIR/venv"
        "$JITSI_TOKEN_DIR/venv/bin/pip" -q install flask "pyjwt>=2" || die "pip install не удался"
    fi
    rm -f "$JITSI_TOKEN_DIR/run.sh"
    cat > "$JITSI_TOKEN_DIR/server.py" <<'EOF'
import os, hmac, time, jwt
from flask import Flask, request, jsonify, abort
app = Flask(__name__)
APP_ID = os.environ["JITSI_APP_ID"]
APP_SECRET = os.environ["JITSI_APP_SECRET"]
HOST = os.environ.get("JITSI_HOST", "meet.jitsi")
TOKEN_KEY = os.environ["JITSI_TOKEN_KEY"]

@app.route("/token")
def gen():
    if not hmac.compare_digest(request.headers.get("X-Token-Key", ""), TOKEN_KEY):
        abort(403)
    room = request.args.get("room", "conference1")
    name = request.args.get("name", "user")
    ttl = request.args.get("ttl_hours")
    payload = {"aud": APP_ID, "iss": APP_ID, "sub": HOST, "room": room,
               "context": {"user": {"name": name}}}
    payload["exp"] = int(time.time()) + int(float(ttl) * 3600) if ttl else 32503680000
    return jsonify({"token": jwt.encode(payload, APP_SECRET, algorithm="HS256")})

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
EOF
    cat > "$JITSI_TOKEN_DIR/run.sh" <<EOF
#!/bin/bash
cd "$JITSI_TOKEN_DIR"
export JITSI_APP_ID='$(jitsi_get_env JWT_APP_ID)'
export JITSI_APP_SECRET='$(jitsi_get_env JWT_APP_SECRET)'
export JITSI_HOST='$(jitsi_get_env XMPP_DOMAIN)'
export JITSI_TOKEN_KEY='$(jitsi_get_env JITSI_TOKEN_KEY)'
[[ -z "\$JITSI_HOST" ]] && export JITSI_HOST=meet.jitsi
exec "$JITSI_TOKEN_DIR/venv/bin/python" server.py
EOF
    chmod +x "$JITSI_TOKEN_DIR/run.sh"
    if jitsi_token_server_running; then log "уже работает"; return 0; fi
    nohup "$JITSI_TOKEN_DIR/run.sh" > "$JITSI_TOKEN_DIR/server.log" 2>&1 &
    echo $! > "$JITSI_TOKEN_DIR/server.pid"
    sleep 1
    jitsi_token_server_running && log "token-сервер: 127.0.0.1:5000" || warn "не стартовал: $JITSI_TOKEN_DIR/server.log"
}

jitsi_issue_token() {
    [[ -f "$JITSI_DIR/.env" ]] || { warn "сначала п.1"; return 1; }
    jitsi_token_server_running || { ask_yn "token-сервер не запущен — запустить?" && jitsi_token_server_start || return 1; }
    local room name key token domain
    while true; do
        room="$(ask "Имя комнаты (a-z0-9_-)" "conference1")"
        [[ "$room" =~ ^[A-Za-z0-9_-]+$ ]] && break
        warn "недопустимое имя комнаты"
    done
    name="$(ask "Отображаемое имя пользователя" "user")"
    key="$(jitsi_get_env JITSI_TOKEN_KEY)"
    [[ -z "$key" ]] && die "JITSI_TOKEN_KEY не найден в .env"
    local name_enc; name_enc="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$name" 2>/dev/null || echo "$name")"
    token="$(curl -fsS --max-time 5 -H "X-Token-Key: $key" \
        "http://127.0.0.1:5000/token?room=${room}&name=${name_enc}" | grep -o '"token": *"[^"]*"' | cut -d'"' -f4)"
    [[ -z "$token" ]] && { warn "токен не получен: $JITSI_TOKEN_DIR/server.log"; return 1; }
    domain="$(jitsi_get_env PUBLIC_URL)"
    cat <<EOF

 Токен для комнаты '$room' (показан один раз, сохраните):
   $token
 Ссылка для входа:
   $domain/$room?jwt=$token
EOF
    read -rp "Enter — продолжить " _ || true
}

jitsi_revoke_tokens() {
    [[ -f "$JITSI_DIR/.env" ]] || { warn "сначала п.2 (включить JWT)"; return 1; }
    ask_yn "Отозвать ВСЕ токены? Будет сгенерирован новый APP_SECRET." || return 0
    local new_secret
    new_secret="$(gen_pass)"
    jitsi_set_env JWT_APP_SECRET "$new_secret"
    jitsi_dc up -d --force-recreate
    log "Все токены отозваны. Новый APP_SECRET: $new_secret"
    warn "Сохраните новый APP_SECRET — старые токены больше не работают."
    read -rp "Enter — продолжить " _ || true
}

jitsi_token_server_stop() {
    if jitsi_token_server_running; then
        kill "$(cat "$JITSI_TOKEN_DIR/server.pid")" 2>/dev/null
        rm -f "$JITSI_TOKEN_DIR/server.pid"
        log "token-сервер остановлен"
    else
        warn "не запущен"
    fi
}

jitsi_menu() {
    while true; do
        clear
        local st="не установлен" svc_st="" turn_st=""
        if [[ -d "$JITSI_DIR" ]]; then
            st="установлен"
            if jitsi_token_server_running; then
                svc_st=" | token: active"
            fi
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE 'jitsi|jicofo|jvb|prosody'; then
                svc_st="${svc_st} | контейнеры: active"
            else
                svc_st="${svc_st} | контейнеры: not active"
            fi
            if [[ -f "$JITSI_DIR/coturn.yml" ]]; then
                turn_st=" | coturn: свой"
            else
                turn_st=" | coturn: общий"
            fi
        fi
        cat <<SUM

${c_mag} --- Jitsi Meet ${st}${svc_st}${turn_st} ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Включить JWT-аутентификацию${c_off}
  ${c_num}3.${c_off} ${c_txt}3478: переключить TCP+UDP / только TCP${c_off}
  ${c_num}4.${c_off} ${c_txt}Пересоздать и перезапустить контейнеры${c_off}
  ${c_num}5.${c_off} ${c_txt}Выдать токен для комнаты${c_off}
  ${c_num}6.${c_off} ${c_txt}Отозвать все токены${c_off}
  ${c_num}7.${c_off} ${c_txt}Остановить token-сервер${c_off}
  ${c_num}8.${c_off} ${c_txt}Логи${c_off}

  ${c_num}r.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_jitsi ;;
            2) jitsi_enable_jwt ;;
            3) jitsi_toggle_udp ;;
            4) [[ -d "$JITSI_DIR" ]] && { jitsi_dc down && jitsi_dc up -d; } || warn "не установлен" ;;
            5) jitsi_issue_token ;;
            6) jitsi_revoke_tokens ;;
            7) jitsi_token_server_stop ;;
            8)
                if [[ -d "$JITSI_DIR" ]]; then
                    jitsi_dc logs --tail=50
                else
                    warn "не установлен"
                fi
                read -rp "Enter — продолжить " _ || true
                ;;
            r|R) remove_jitsi ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}
