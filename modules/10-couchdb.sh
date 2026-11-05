#!/usr/bin/env bash

COUCHDB_DATA="$DATA_DIR/couchdb"
COUCHDB_CFG="$CONFIG_ROOT/config/couchdb"

couchdb_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qE 'couchdb'
}

install_couchdb() {
    ensure_prepared
    check_dependencies
    log "=== CouchDB (Obsidian LiveSync) ==="

    local fresh="true" new_pass=""
    if [[ -d "$COUCHDB_DATA" && -n "$(ls -A "$COUCHDB_DATA" 2>/dev/null)" ]]; then fresh="false"; fi

    local dbname="obsidian" maxdoc=50 maxreq=4096 cors_extra="" port="5984"
    local subdomain="${SUB_OBSIDIAN:-obsidian}"
    [[ "$subdomain" == *.* ]] || subdomain="${subdomain}.${DOMAIN}"

    while true; do
        local pass_descr="в .env (COUCHDB_PASSWORD)"
        [[ "$fresh" == "true" ]] && pass_descr="будет сгенерирован (или задайте в пункте 2)"
        clear
        cat <<SUM

${c_mag} --- Настройки CouchDB ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: ${subdomain}${c_off}
  ${c_num}2.${c_off} ${c_txt}Настройки учётной записи (логин: $COUCHDB_USER)${c_off}
  ${c_num}3.${c_off} ${c_txt}Локальный порт: ${port}${c_off}
  ${c_num}4.${c_off} ${c_txt}База заметок: $dbname${c_off}
  ${c_num}5.${c_off} ${c_txt}Лимиты: документ ${maxdoc} МБ | HTTP-запрос ${maxreq} МБ${c_off}
  ${c_num}6.${c_off} ${c_txt}Доп. CORS-origins: ${cors_extra:-—}${c_off}

  ${c_num}9.${c_off} ${c_txt}Установить / Применить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад (без установки)${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                local raw
                raw="$(ask "Поддомен (без .$DOMAIN)" "${subdomain%%.*}")"
                [[ "$raw" =~ ^[a-z0-9-]+$ ]] || { warn "некорректный поддомен"; read -rp "Enter — продолжить " _ || true; continue; }
                subdomain="${raw}.${DOMAIN}"
                ;;
            2)
                local u p
                u="$(ask "Логин CouchDB" "$COUCHDB_USER")"
                if [[ "$u" != "$COUCHDB_USER" && "$fresh" == "false" ]]; then
                    warn "на существующей установке логин не меняется (админ уже создан) — оставляю $COUCHDB_USER"
                    read -rp "Enter — продолжить " _ || true
                else
                    COUCHDB_USER="$u"; update_env COUCHDB_USER "$u"
                fi
                p="$(ask "Пароль (Enter — сгенерировать/не менять)" "$([[ "$fresh" == "true" ]] && gen_pass)")"
                [[ -n "$p" ]] && new_pass="$p"
                ;;
            3)
                local p
                p="$(ask "Локальный порт CouchDB (nginx → CouchDB)" "$port")"
                [[ "$p" =~ ^[0-9]+$ ]] && port="$p" || { warn "нужно число — оставляю $port"; read -rp "Enter — продолжить " _ || true; }
                ;;
            4)
                dbname="$(ask "Имя базы (a-z0-9 и _ \$ ( ) + -)" "$dbname")"
                [[ "$dbname" =~ ^[a-z0-9][a-z0-9_$()+-]*$ ]] || { warn "недопустимое имя базы '$dbname'"; dbname="obsidian"; read -rp "Enter — продолжить " _ || true; }
                ;;
            5)
                local md mr
                md="$(ask "Макс. размер документа, МБ (число)" "$maxdoc")"
                mr="$(ask "Макс. размер HTTP-запроса, МБ (число)" "$maxreq")"
                [[ "$md" =~ ^[0-9]+$ ]] && maxdoc="$md" || { warn "нужно число — оставляю $maxdoc"; read -rp "Enter — продолжить " _ || true; }
                [[ "$mr" =~ ^[0-9]+$ ]] && maxreq="$mr" || { warn "нужно число — оставляю $maxreq"; read -rp "Enter — продолжить " _ || true; }
                ;;
            6)
                cors_extra="$(ask "Доп. origins через запятую (напр. http://localhost:8080); пусто — без" "$cors_extra")"
                cors_extra="${cors_extra// /}"
                ;;
            9) break ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Enter — продолжить " _ || true ;;
        esac
    done

    SUB_OBSIDIAN="$subdomain"
    update_env SUB_OBSIDIAN "$subdomain"
    update_env COUCHDB_PORT "$port"
    dns_hint "$subdomain"

    if [[ "$fresh" == "true" && -n "$new_pass" ]]; then
        COUCHDB_PASSWORD="$new_pass"; update_env COUCHDB_PASSWORD "$new_pass"
    fi

    # Харднинг через override
    cat > "$CONFIG_ROOT/docker-compose.override.couchdb.yml" <<EOF
services:
  couchdb:
    pids_limit: 400
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - NET_RAW
      - SYS_PTRACE
      - SYS_ADMIN
      - SYS_MODULE
      - DAC_READ_SEARCH
EOF

    mkdir -p "$COUCHDB_CFG"
    cat > "$COUCHDB_CFG/10-livesync.ini" <<EOF
[couchdb]
single_node = true
max_document_size = $((maxdoc*1048576))
[chttpd]
max_http_request_size = $((maxreq*1048576))
[httpd]
enable_cors = true
[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost${cors_extra:+,$cors_extra}
methods = GET, PUT, POST, HEAD, DELETE
credentials = true
headers = accept, authorization, content-type, origin, referer
max_age = 3600
EOF

    # Убедимся, что сервис couchdb описан в compose
    if ! grep -q '^[[:space:]]*couchdb:' "$CONFIG_ROOT/docker-compose.yml" 2>/dev/null; then
        warn "Сервис couchdb не найден в docker-compose.yml — добавьте его вручную или через gen_compose"
        read -rp "Enter — продолжить " _ || true
        return 1
    fi

    # Обновляем порт в compose если нужно
    if grep -q 'couchdb:' "$CONFIG_ROOT/docker-compose.yml" 2>/dev/null; then
        if ! grep -q "127.0.0.1:${port}:5984" "$CONFIG_ROOT/docker-compose.yml"; then
            sed -i "s|127.0.0.1:[0-9]\+:5984|127.0.0.1:${port}:5984|" "$CONFIG_ROOT/docker-compose.yml" || \
            sed -i "s|'5984:5984'|'127.0.0.1:${port}:5984'|" "$CONFIG_ROOT/docker-compose.yml"
        fi
    fi

    docker compose -f "$CONFIG_ROOT/docker-compose.yml" \
        -f "$CONFIG_ROOT/docker-compose.override.couchdb.yml" up -d couchdb

    log "Жду healthcheck CouchDB (до 180 секунд)..."
    local status=""
    for _ in $(seq 1 90); do
        status=$(docker inspect --format '{{.State.Health.Status}}' homeserver-couchdb-1 2>/dev/null || echo starting)
        [[ "$status" == "healthy" ]] && break; sleep 2
    done
    [[ "$status" == "healthy" ]] || { warn "CouchDB не поднялся за 180 секунд"; read -rp "Enter — продолжить " _ || true; return 1; }

    for db in _users _replicator "$dbname"; do
        local code
        code=$(docker compose -f "$CONFIG_ROOT/docker-compose.yml" exec -T couchdb curl -s -o /dev/null -w '%{http_code}' \
            -X PUT -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/$db")
        [[ "$code" =~ ^(201|412)$ ]] && log "  база $db — ок" || { warn "  база $db — HTTP $code"; read -rp "Enter — продолжить " _ || true; }
    done

    if [[ "$fresh" == "false" && -n "$new_pass" ]]; then
        local code
        code=$(docker compose -f "$CONFIG_ROOT/docker-compose.yml" exec -T couchdb curl -s -o /dev/null -w '%{http_code}' -X PUT \
            -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
            "http://localhost:5984/_node/_local/_config/admins/$COUCHDB_USER" -d "\"$new_pass\"")
        [[ "$code" == "200" ]] && { update_env COUCHDB_PASSWORD "$new_pass"; log "Пароль CouchDB обновлён."; read -rp "Enter — продолжить " _ || true; } \
                               || { warn "смена пароля не удалась (HTTP $code) — смените через Fauxton (_utils)."; read -rp "Enter — продолжить " _ || true; }
    fi

    add_site 10-obsidian "server {
    listen 8443 ssl;
    server_name $subdomain;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 4096m;
    location / {
        proxy_pass http://127.0.0.1:${port};
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    update_env SUB_OBSIDIAN "$subdomain"

    show_connection_info "CouchDB (Obsidian LiveSync)" \
        "URL: https://$subdomain" \
        "База данных: $dbname" \
        "Логин: $COUCHDB_USER" \
        "Пароль: $COUCHDB_PASSWORD" \
        "Веб-админка Fauxton: https://$subdomain/_utils" \
        "" \
        "!!! ВАЖНО: Включите E2E-шифрование в плагине Obsidian !!!" \
        "  Без E2E заметки хранятся на сервере в ОТКРЫТОМ виде." \
        "  Settings → Community Plugins → Self-hosted LiveSync → Encryption" \
        "  Enable End-to-End Encryption + задайте длинный passphrase." \
        "" \
        "В плагине Self-hosted LiveSync на каждом устройстве:" \
        "  URL: https://$subdomain" \
        "  База: $dbname" \
        "  Логин: $COUCHDB_USER" \
        "  Пароль: $COUCHDB_PASSWORD" \
        "  E2E-passphrase: одинаковый на всех устройствах"
    read -rp "Enter — продолжить " _ || true

    log_connection_params "CouchDB" \
        "URL: https://$subdomain" \
        "База: $dbname" \
        "Логин: $COUCHDB_USER" \
        "Пароль: $COUCHDB_PASSWORD" \
        "Админка: https://$subdomain/_utils"
}

remove_couchdb() {
    [[ -d "$COUCHDB_DATA" ]] || { warn "CouchDB не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    ask_yn "Удалить CouchDB? Все данные будут потеряны." || return 0

    local port="${COUCHDB_PORT:-5984}"
    docker compose -f "$CONFIG_ROOT/docker-compose.yml" down --volumes couchdb 2>/dev/null || true
    rm -f "$CONFIG_ROOT/docker-compose.override.couchdb.yml"
    rm_site 10-obsidian
    rm -rf "$COUCHDB_DATA" "$COUCHDB_CFG"
    update_env SUB_OBSIDIAN ""
    update_env COUCHDB_PORT ""
    log "CouchDB удалён"
    read -rp "Enter — продолжить " _ || true
}

couchdb_create_db() {
    [[ -d "$COUCHDB_DATA" ]] || { warn "CouchDB не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    couchdb_running || { warn "CouchDB не запущен"; read -rp "Enter — продолжить " _ || true; return 1; }

    local dbname
    dbname="$(ask "Имя новой базы (a-z0-9 и _ \$ ( ) + -)" "obsidian_friend")"
    [[ "$dbname" =~ ^[a-z0-9][a-z0-9_$()+-]*$ ]] || { warn "недопустимое имя базы"; read -rp "Enter — продолжить " _ || true; return 1; }

    local code
    code=$(docker compose -f "$CONFIG_ROOT/docker-compose.yml" exec -T couchdb curl -s -o /dev/null -w '%{http_code}' \
        -X PUT -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/$dbname")

    case "$code" in
        201) log "База '$dbname' создана. Для подключения в Obsidian: URL=https://$SUB_OBSIDIAN, База=$dbname" ;;
        412) warn "База '$dbname' уже существует" ;;
        *)   warn "Ошибка создания базы: HTTP $code" ;;
    esac
    read -rp "Enter — продолжить " _ || true
}

couchdb_list_dbs() {
    [[ -d "$COUCHDB_DATA" ]] || { warn "CouchDB не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    couchdb_running || { warn "CouchDB не запущен"; read -rp "Enter — продолжить " _ || true; return 1; }

    log "Список баз данных:"
    docker compose -f "$CONFIG_ROOT/docker-compose.yml" exec -T couchdb curl -s \
        -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/_all_dbs" | \
        python3 -m json.tool 2>/dev/null || \
        docker compose -f "$CONFIG_ROOT/docker-compose.yml" exec -T couchdb curl -s \
        -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/_all_dbs"
    read -rp "Enter — продолжить " _ || true
}

couchdb_menu() {
    while true; do
        clear
        local st="не установлен" svc_st=""
        if [[ -d "$COUCHDB_DATA" ]]; then
            st="установлен"
            if couchdb_running; then
                svc_st=" | контейнер: active"
            else
                svc_st=" | контейнер: not active"
            fi
        fi
        cat <<SUM

${c_mag} --- CouchDB (Obsidian LiveSync) ${st}${svc_st} ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Создать базу данных${c_off}
  ${c_num}3.${c_off} ${c_txt}Список баз данных${c_off}
  ${c_num}4.${c_off} ${c_txt}Логи${c_off}

  ${c_num}r.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_couchdb ;;
            2) couchdb_create_db ;;
            3) couchdb_list_dbs ;;
            4)
                if [[ -d "$COUCHDB_DATA" ]]; then
                    docker compose -f "$CONFIG_ROOT/docker-compose.yml" logs --tail=50 couchdb
                    read -rp "Enter — продолжить " _ || true
                else
                    warn "не установлен"; read -rp "Enter — продолжить " _ || true
                fi
                ;;
            r|R) remove_couchdb ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Enter — продолжить " _ || true ;;
        esac
    done
}
