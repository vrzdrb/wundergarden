#!/usr/bin/env bash

install_couchdb() {
    ensure_prepared
    check_dependencies
    log "=== CouchDB (Obsidian LiveSync) ==="
    local fresh="true" new_pass=""
    if [[ -d "$DATA_DIR/couchdb" && -n "$(ls -A "$DATA_DIR/couchdb" 2>/dev/null)" ]]; then fresh="false"; fi
    local dbname="obsidian" maxdoc=50 maxreq=4096 cors_extra=""

    SUB_OBSIDIAN="$(ask "Поддомен для Obsidian (LiveSync)" "${SUB_OBSIDIAN:-obsidian.$DOMAIN}")"
    update_env SUB_OBSIDIAN "$SUB_OBSIDIAN"; dns_hint "$SUB_OBSIDIAN"

    while true; do
        local pass_descr="в .env (COUCHDB_PASSWORD)"
        [[ "$fresh" == "true" ]] && pass_descr="будет сгенерирован (или задайте в пункте 2)"
        clear
        cat <<SUM

${c_mag} --- Настройки CouchDB ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB_OBSIDIAN${c_off}
  ${c_num}2.${c_off} ${c_txt}Учётка: $COUCHDB_USER / $pass_descr${c_off}
  ${c_num}3.${c_off} ${c_txt}База заметок: $dbname${c_off}
  ${c_num}4.${c_off} ${c_txt}Лимиты: документ ${maxdoc} МБ | HTTP-запрос ${maxreq} МБ${c_off}
  ${c_num}5.${c_off} ${c_txt}Доп. CORS-origins: ${cors_extra:-—}${c_off}

 ${c_num}6.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                SUB_OBSIDIAN="$(ask "Поддомен" "$SUB_OBSIDIAN")"
                update_env SUB_OBSIDIAN "$SUB_OBSIDIAN"; dns_hint "$SUB_OBSIDIAN" ;;
            2)
                local u p
                u="$(ask "Логин CouchDB" "$COUCHDB_USER")"
                if [[ "$u" != "$COUCHDB_USER" && "$fresh" == "false" ]]; then
                    warn "на существующей установке логин не меняется (админ уже создан) — оставляю $COUCHDB_USER"
                else
                    COUCHDB_USER="$u"; update_env COUCHDB_USER "$u"
                fi
                p="$(ask "Пароль (Enter — сгенерировать/не менять)" "$([[ "$fresh" == "true" ]] && gen_pass)")"
                [[ -n "$p" ]] && new_pass="$p" ;;
            3)
                dbname="$(ask "Имя базы (a-z0-9 и _ $ ( ) + -)" "$dbname")"
                [[ "$dbname" =~ ^[a-z0-9][a-z0-9_$()+-]*$ ]] || { warn "недопустимое имя базы '$dbname'"; dbname="obsidian"; } ;;
            4)
                local md mr
                md="$(ask "Макс. размер документа, МБ (число)" "$maxdoc")"
                mr="$(ask "Макс. размер HTTP-запроса, МБ (число)" "$maxreq")"
                [[ "$md" =~ ^[0-9]+$ ]] && maxdoc="$md" || warn "нужно число — оставляю $maxdoc"
                [[ "$mr" =~ ^[0-9]+$ ]] && maxreq="$mr" || warn "нужно число — оставляю $maxreq" ;;
            5) cors_extra="$(ask "Доп. origins через запятую (напр. http://localhost:8080); пусто — без" "$cors_extra")"
               cors_extra="${cors_extra// /}" ;;
            6) logs_menu couchdb  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    if [[ "$fresh" == "true" && -n "$new_pass" ]]; then
        COUCHDB_PASSWORD="$new_pass"; update_env COUCHDB_PASSWORD "$new_pass"
    fi

    mkdir -p "$CONFIG_ROOT/config/couchdb"
    cat > "$CONFIG_ROOT/config/couchdb/10-livesync.ini" <<EOF
[couchdb]
single_node = true
max_document_size = $((maxdoc*1048576))
[chttpd]
max_http_request_size = $((maxreq*1048576))
require_valid_user = true
[httpd]
enable_cors = true
[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost${cors_extra:+,$cors_extra}
methods = GET, PUT, POST, HEAD, DELETE
credentials = true
headers = accept, authorization, content-type, origin, referer
max_age = 3600
EOF

    docker compose up -d couchdb
    log "Жду healthcheck CouchDB (до 180 секунд)..."
    local status=""
    for _ in $(seq 1 90); do
        status=$(docker inspect --format '{{.State.Health.Status}}' homeserver-couchdb-1 2>/dev/null || echo starting)
        [[ "$status" == "healthy" ]] && break; sleep 2
    done
    [[ "$status" == "healthy" ]] || die "CouchDB не поднялся за 180 секунд: docker compose logs couchdb"

    for db in _users _replicator "$dbname"; do
        code=$(docker compose exec -T couchdb curl -s -o /dev/null -w '%{http_code}' \
            -X PUT -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/$db")
        [[ "$code" =~ ^(201|412)$ ]] && log "  база $db — ок" || warn "  база $db — HTTP $code"
    done

    if [[ "$fresh" == "false" && -n "$new_pass" ]]; then
        code=$(docker compose exec -T couchdb curl -s -o /dev/null -w '%{http_code}' -X PUT \
            -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
            "http://localhost:5984/_node/_local/_config/admins/$COUCHDB_USER" -d "\"$new_pass\"")
        [[ "$code" == "200" ]] && { update_env COUCHDB_PASSWORD "$new_pass"; log "Пароль CouchDB обновлён."; } \
                               || warn "смена пароля не удалась (HTTP $code) — смените через Fauxton (_utils)."
    fi

    add_site 10-obsidian "server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    server_name $SUB_OBSIDIAN;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 4096m;
    location / {
        proxy_pass http://127.0.0.1:5984;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    
    # Вывод параметров подключения
    show_connection_info "CouchDB (Obsidian LiveSync)" \
        "URL: https://$SUB_OBSIDIAN" \
        "База данных: $dbname" \
        "Логин: $COUCHDB_USER" \
        "Пароль: $COUCHDB_PASSWORD" \
        "Веб-админка Fauxton: https://$SUB_OBSIDIAN/_utils" \
        "" \
        "В плагине Self-hosted LiveSync на каждом устройстве:" \
        "  URL: https://$SUB_OBSIDIAN" \
        "  База: $dbname" \
        "  Логин: $COUCHDB_USER" \
        "  Пароль: $COUCHDB_PASSWORD" \
        "  E2E-пароль задайте свой, одинаковый на всех устройствах."
    
    # Сохранение параметров в файл
    log_connection_params "CouchDB" \
        "URL: https://$SUB_OBSIDIAN" \
        "База: $dbname" \
        "Логин: $COUCHDB_USER" \
        "Пароль: $COUCHDB_PASSWORD" \
        "Админка: https://$SUB_OBSIDIAN/_utils"
}
