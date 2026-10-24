#!/usr/bin/env bash

JITSI_DIR="$CONFIG_ROOT/jitsi"
JITSI_CFG="$CONFIG_ROOT/data/jitsi-cfg"
JITSI_TOKEN_DIR="$CONFIG_ROOT/jitsi-token-server"

jitsi_dc() {
    local files=(-f docker-compose.yml)
    [[ -f "$JITSI_DIR/coturn.yml" ]] && files+=(-f coturn.yml)
    [[ -f "$JITSI_DIR/web-certs.yml" ]] && files+=(-f web-certs.yml)
    ( cd "$JITSI_DIR" && docker compose "${files[@]}" "$@" )
}

jitsi_set_env() {
    local key="$1" val="$2"
    ( cd "$JITSI_DIR" && { grep -v "^${key}=" .env || true; echo "${key}=${val}"; } > .env.tmp.$$ && mv .env.tmp.$$ .env )
}

jitsi_get_env() { ( cd "$JITSI_DIR" && grep "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- ); }

install_jitsi() {
    ensure_prepared
    log "=== Jitsi Meet (видеоконференции) ==="
    [[ -d "$JITSI_DIR" ]] && { ask_yn "Обнаружена установка в $JITSI_DIR — переустановить? Конфиг сохранится." || return 0; }

    local domain pub_ip mode turn_src tz
    while true; do
        domain="$(ask "Домен (meet.$DOMAIN)" "meet.$DOMAIN")"
        [[ "$domain" =~ ^[a-z0-9.-]+$ && "$domain" == *.* ]] && break
        warn "некорректный домен"
    done
    pub_ip="$(ask "Публичный IP (JVB_ADVERTISE_IPS)" "${PUBLIC_IP:-}")"
    [[ -z "$pub_ip" ]] && { warn "IP обязателен"; return 1; }
    echo "${c_txt}Режим веба: 1) за нашим nginx (TLS нашим wildcard; порт хоста 127.0.0.1:7443, рекомендуется)${c_off}"
    echo "${c_txt}            2) прямой HTTPS своим сертификатом (80+443 на этом хосте)${c_off}"
    mode="$(ask "1/2" "1")"
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
    zipurl="$(grep browser_download_url <<< "$json" | grep '\.zip' | cut -d'"' -f4)"
    [[ -z "$zipurl" ]] && die "не удалось получить ссылку на релиз"
    mkdir -p "$JITSI_DIR"
    ( cd "$JITSI_DIR" && curl -fsSL -o jitsi.zip "$zipurl" && unzip -o -q jitsi.zip ) || die "ошибка скачивания/распаковки"
    topdir="$(unzip -Z1 "$JITSI_DIR/jitsi.zip" | head -1 | cut -d/ -f1)"
    [[ -n "$topdir" && -d "$JITSI_DIR/$topdir" ]] && { cp -a "$JITSI_DIR/$topdir"/. "$JITSI_DIR/"; rm -rf "$JITSI_DIR/$topdir"; }
    rm -f "$JITSI_DIR/jitsi.zip"
    log "Версия: $tag"
    cd "$JITSI_DIR"
    [[ -f .env ]] || cp env.example .env
    bash gen-passwords.sh >/dev/null
    chmod 600 .env

    jitsi_set_env CONFIG "$JITSI_CFG"
    jitsi_set_env TZ "$tz"
    jitsi_set_env PUBLIC_URL "https://$domain"
    jitsi_set_env JVB_ADVERTISE_IPS "$pub_ip"
    jitsi_set_env ENABLE_XMPP_WEBSOCKET 1
    jitsi_set_env ENABLE_HTTP_REDIRECT 0
    jitsi_set_env JITSI_IMAGE_VERSION "$tag"
    jitsi_set_env ENABLE_LETSENCRYPT 0
    jitsi_set_env DISABLE_HTTPS 1
    jitsi_set_env HTTP_PORT 7443
    jitsi_set_env HTTPS_PORT 8443

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

    if [[ "$mode" == "1" ]]; then
        sed -i "s#- '\${HTTP_PORT}:8000'#- '127.0.0.1:\${HTTP_PORT}:8000'#" docker-compose.yml
        sed -i "s#- '\${HTTPS_PORT}:8443'#- '127.0.0.1:\${HTTPS_PORT}:8443'#" docker-compose.yml
    fi

    docker compose -f docker-compose.yml ${turn_src:+$( [[ "$turn_src" == "2" ]] && echo "-f coturn.yml" )} pull
    jitsi_dc up -d || die "ошибка запуска: cd $JITSI_DIR && docker compose logs"

    if [[ "$mode" == "1" ]]; then
        add_site 150-jitsi "server {
    listen 8443 ssl;
    server_name $domain;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://127.0.0.1:7443;
        include /etc/nginx/proxy_common.conf;
        include /etc/nginx/ws_common.conf;
        proxy_read_timeout 3600s;
    }
}"
        update_env SUB_JITSI "$domain"
    fi

    cat <<EOF

 Готово: https://$domain
 TURN: $([[ "$turn_src" == "1" ]] && echo "наш coturn (turn.$DOMAIN:3478)" || echo "свой coturn (3478 host-network)")
 Медиа JVB: 10000/udp (docker публикует сам; на VPS откройте в security group).
 Комната без авторизации: любой, кто знает ссылку. Включите JWT (п.22 меню -> действие 2).
EOF
}

jitsi_toggle_udp() {
    if [[ -f "$JITSI_DIR/coturn.yml" ]]; then
        local conf="$JITSI_CFG/coturn/turnserver.conf"
    else
        local conf="$DATA_DIR/coturn/turnserver.conf"
    fi
    [[ -f "$conf" ]] || { warn "coturn не найден ($conf)"; return 1; }
    if grep -q '^no-udp' "$conf"; then
        sed -i '/^no-udp/d' "$conf"
        log "3478: TCP+UDP (полная совместимость TURN)"
    else
        echo "no-udp" >> "$conf"
        log "3478: только TCP (порт UDP освобождён; NAT-traversal хуже)"
    fi
    if [[ -f "$JITSI_DIR/coturn.yml" ]]; then
        ( cd "$JITSI_DIR" && docker compose -f docker-compose.yml -f coturn.yml up -d --force-recreate coturn )
    else
        docker compose up -d --force-recreate coturn
    fi
}

jitsi_menu() {
    while true; do
        cat <<SUM

${c_mag} --- Jitsi Meet ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Включить JWT-аутентификацию${c_off}
  ${c_num}3.${c_off} ${c_txt}3478: переключить TCP+UDP / только TCP${c_off}
  ${c_num}4.${c_off} ${c_txt}Пересоздать и перезапустить контейнеры${c_off}
  ${c_num}5.${c_off} ${c_txt}Запустить token-сервер${c_off}
  ${c_num}6.${c_off} ${c_txt}Выдать токен для комнаты${c_off}
  ${c_num}7.${c_off} ${c_txt}Остановить token-сервер${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_jitsi ;;
            2) jitsi_enable_jwt ;;
            3) jitsi_toggle_udp ;;
            4) [[ -d "$JITSI_DIR" ]] && { jitsi_dc down && jitsi_dc up -d; } || warn "не установлен" ;;
            5) jitsi_token_server_start ;;
            6) jitsi_issue_token ;;
            7) jitsi_token_server_stop ;;
            8) [[ -d "$JITSI_DIR" ]] && jitsi_dc logs --tail=50 ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
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
    jitsi_dc up -d
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
[[ -z "$JITSI_HOST" ]] && export JITSI_HOST=meet.jitsi
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
