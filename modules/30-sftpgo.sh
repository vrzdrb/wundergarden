#!/usr/bin/env bash

# fallback если скрипт запущен не через wundergarden.sh
command -v rm_site >/dev/null 2>&1 || rm_site() {
    rm -f "$CONFIG_ROOT/config/nginx/conf.d/${1}.conf"
    nginx -s reload 2>/dev/null || true
}
command -v reload_nginx >/dev/null 2>&1 || reload_nginx() {
    nginx -s reload 2>/dev/null || true
}
command -v add_stream_passthrough >/dev/null 2>&1 || add_stream_passthrough() {
    log "add_stream_passthrough не определён — пропускаю $1"
}

install_sftpgo() {
    ensure_prepared
    check_dependencies
    log "=== SFTPGo (файлы + ссылки друзьям) ==="
    local sftpdata="${SFTPGO_DATA:-/opt/homeserver/sftpgo}" admin_user="${SFTPGO_ADMIN_USER:-admin}" \
          cloud_user="" cloud_pass="" cloud_quota=0 \
          sftp_ext="false" webdav="false" \
          tls_mode="${SFTPGO_TLS_MODE:-direct}" \
          SUB_WEBDAV="${SUB_WEBDAV:-webdav.$DOMAIN}"
    [[ "${tls_mode}" != "xray" ]] && tls_mode="direct"
    [[ "${SFTPGO_SFTP_BIND:-127.0.0.1:2022}" != "127.0.0.1:2022" ]] && sftp_ext="true"

    SUB_FILES="$(ask "Поддомен веб-клиента (share-ссылки)" "${SUB_FILES:-files.$DOMAIN}")"; update_env SUB_FILES "$SUB_FILES"
    dns_hint "$SUB_FILES"

    while true; do
        local cloud_descr="не создавать" sftp_descr="выкл (только туннель)" webdav_descr="выкл" tls_descr="127.0.0.1:8443 (nginx)"
        local st="не установлен"
        [[ -n "$cloud_user" ]] && cloud_descr="$cloud_user (квота ${cloud_quota} МБ)"
        [[ "$sftp_ext" == "true" ]] && sftp_descr="вкл (0.0.0.0:2022)"
        [[ "$webdav" == "true" ]] && webdav_descr="https://$SUB_WEBDAV"
        [[ "$tls_mode" == "xray" ]] && tls_descr="127.0.0.1:7443 (REALITY)"
        docker compose ps -q sftpgo 2>/dev/null | grep -q . && st="установлен"
        local admin_hint_user="${SUDO_USER:-$USER}"
        local admin_hint_ip="${PUBLIC_IP:-}"
        [[ -z "$admin_hint_ip" ]] && admin_hint_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
        [[ -z "$admin_hint_ip" ]] && admin_hint_ip="<IP сервера>"
        clear
        cat <<SUM
${c_mag} --- Настройки SFTPGo ---${c_off}   Статус: $st
  ${c_txt}Админка: ssh -L 8080:localhost:8080 $admin_hint_user@$admin_hint_ip -> http://localhost:8080/web/admin${c_off}
  ${c_num}1.${c_off} ${c_txt}Папка данных: $sftpdata${c_off}
  ${c_num}2.${c_off} ${c_txt}Веб-клиент: https://$SUB_FILES${c_off}
  ${c_num}3.${c_off} ${c_txt}Админ: $admin_user${c_off}
  ${c_num}4.${c_off} ${c_txt}Пользователь облака: $cloud_descr${c_off}
  ${c_num}5.${c_off} ${c_txt}SFTP наружу: $sftp_descr${c_off}
  ${c_num}6.${c_off} ${c_txt}WebDAV через nginx: $webdav_descr${c_off}
  ${c_num}7.${c_off} ${c_txt}Терминация TLS: $tls_descr${c_off}
  ${c_num}8.${c_off} ${c_txt}Логи${c_off}
  ${c_num}9.${c_off} ${c_txt}Установить / Применить${c_off}
  ${c_num}10.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад (без установки)${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                sftpdata="$(ask "Папка данных" "$sftpdata")"
                if findmnt -n -T "$sftpdata" 2>/dev/null | awk '{print $1}' | grep -q '^/$'; then
                    warn "$sftpdata находится на корневом разделе."
                    ask_yn "Продолжить?" || true
                fi ;;
            2) SUB_FILES="$(ask "Поддомен веб-клиента" "$SUB_FILES")"; update_env SUB_FILES "$SUB_FILES"; dns_hint "$SUB_FILES" ;;
            3)
                admin_user="$(ask "Логин админа" "$admin_user")"; update_env SFTPGO_ADMIN_USER "$admin_user"
                if ask_yn "Сгенерировать новый пароль админа?"; then
                    SFTPGO_ADMIN_PASSWORD="$(gen_pass)"; update_env SFTPGO_ADMIN_PASSWORD "$SFTPGO_ADMIN_PASSWORD"
                    log "Новый пароль: $SFTPGO_ADMIN_PASSWORD (на свежем сервере применится сразу; на работающем смените в админке)"
                fi ;;
            4)
                if [[ -n "$cloud_user" ]]; then cloud_user=""
                else
                    cloud_user="$(ask "Логин пользователя облака" "cloud")"
                    while :; do
                        cloud_pass="$(ask 'Пароль (Enter — сгенерировать; без кавычек и \\)' "$(gen_pass)")"
                        [[ "$cloud_pass" =~ [\\\"] ]] || break
                        warn "кавычки и обратный слеш ломают JSON API — выберите другой пароль"
                    done
                    log "Пароль '$cloud_user': $cloud_pass"
                    cloud_quota="$(ask "Квота, МБ (0 — без ограничений)" "0")"
                fi ;;
            5) [[ "$sftp_ext" == "true" ]] && sftp_ext="false" || sftp_ext="true" ;;
            6)
                if [[ "$webdav" == "true" ]]; then webdav="false"
                else
                    webdav="true"
                    SUB_WEBDAV="$(ask "Поддомен WebDAV" "$SUB_WEBDAV")"; update_env SUB_WEBDAV "$SUB_WEBDAV"
                    dns_hint "$SUB_WEBDAV"
                fi ;;
            7)
                if [[ "$tls_mode" == "xray" ]]; then tls_mode="direct"
                else
                    tls_mode="xray"
                    echo "${c_txt}Режим 'через xray (REALITY)': nginx НЕ получает SNI $SUB_FILES напрямую.${c_off}"
                    echo "${c_txt}SNI $SUB_FILES будет проброшен на 127.0.0.1:7443 (inbound xray VLESS+REALITY).${c_off}"
                    echo "${c_txt}VLESS-клиенты: TLS 1.3 завершает xray (REALITY).${c_off}"
                    echo "${c_txt}Браузеры: xray пробрасывает handshake в dest 127.0.0.1:8443 — TLS 1.2/1.3${c_off}"
                    echo "${c_txt}завершает этот nginx, сайт на 8443 обслуживает веб-клиент.${c_off}"
                    echo "${c_txt}Требование к скрипту xray: inbound 7443 с dest: 127.0.0.1:8443 (настраивается там).${c_off}"
                    ask_yn "Продолжить?" || tls_mode="direct"
                fi ;;
            8) logs_menu sftpgo sftpgo-db ;;
            9) break ;;
            10) remove_sftpgo; return 0 ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    update_env SFTPGO_TLS_MODE "$tls_mode"
    mkdir -p "$sftpdata"
    chmod 0777 "$sftpdata"
    log "Папка данных: $sftpdata (права 0777 — не только root)"
    update_env SFTPGO_DATA "$sftpdata"
    local new_sftp_bind="$([[ "$sftp_ext" == "true" ]] && echo 0.0.0.0:2022 || echo 127.0.0.1:2022)"
    local old_sftp_bind="${SFTPGO_SFTP_BIND:-127.0.0.1:2022}"
    update_env SFTPGO_SFTP_BIND "$new_sftp_bind"

    # Открываем порт SFTP в UFW если SFTP наружу
    if [[ "$sftp_ext" == "true" ]]; then
        require_cmd ufw ufw
        ufw allow 2022/tcp comment 'SFTPGo SFTP' >/dev/null 2>&1 && log "UFW: порт 2022/tcp открыт" || warn "Ошибка UFW"
        ufw reload >/dev/null 2>&1 || true
    fi

    # Запускаем MariaDB и ждём готовности
    docker compose up -d sftpgo-db
    wait_container sftpgo-db mariadb-admin ping -h127.0.0.1

    # Проверяем, нужно ли пересоздать контейнер SFTPGo (если изменился SFTP_BIND)
    local need_recreate="false"
    if docker compose ps -q sftpgo 2>/dev/null | grep -q .; then
        # Контейнер уже существует, проверяем нужно ли пересоздание
        if [[ "$old_sftp_bind" != "$new_sftp_bind" ]]; then
            log "Обнаружено изменение SFTP_BIND ($old_sftp_bind -> $new_sftp_bind) — пересоздаю контейнер"
            need_recreate="true"
        fi
    fi

    # Запускаем или пересоздаём SFTPGo
    if [[ "$need_recreate" == "true" ]]; then
        docker compose up -d --force-recreate sftpgo
    else
        docker compose up -d sftpgo
    fi

    # Ждём готовности SFTPGo (увеличенная задержка)
    log "Ожидание готовности SFTPGo..."
    local sftpgo_ready="false"
    for i in {1..15}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/api/v2/version 2>/dev/null | grep -q "200"; then
            sftpgo_ready="true"
            log "SFTPGo готов (попытка $i/15)"
            break
        fi
        sleep 2
    done

    if [[ "$sftpgo_ready" != "true" ]]; then
        warn "SFTPGo не ответил после 30 секунд — продолжаю, но создание пользователя может не сработать"
    fi

    # Создаём пользователя облака если задан
    if [[ -n "$cloud_user" ]]; then
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' -u "$admin_user:$SFTPGO_ADMIN_PASSWORD" -X POST \
            http://127.0.0.1:8080/api/v2/users -H 'Content-Type: application/json' \
            -d "{\"username\":\"$cloud_user\",\"password\":\"$cloud_pass\",\"status\":1,\"permissions\":[\"*\"],\"quota_size\":$((cloud_quota*1024*1024))}")
        case "$code" in
            201) log "Пользователь '$cloud_user' создан (квота $cloud_quota МБ)." ;;
            409) warn "Пользователь '$cloud_user' уже существует — пропускаю." ;;
            *)   warn "Не удалось создать пользователя (HTTP $code) — создайте в админке." ;;
        esac
    fi

    # --- nginx ---
    # Сайт одинаковый в обоих режимах: nginx терминирует TLS (loopback-only),
    # в sftpgo — plain HTTP. Режим 'xray' отличается только тем, что SNI домена
    # идёт на xray:7443 (REALITY), а xray пробрасывает браузерный handshake
    # в dest 127.0.0.1:8443 — сюда же, этот сайт его и обслуживает.
    add_site 30-sftpgo "server {
    listen 127.0.0.1:8443 ssl;
    server_name $SUB_FILES;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location /web/admin { return 403; }
    location / {
        proxy_pass http://127.0.0.1:8080;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"

    if [[ "$tls_mode" == "xray" ]]; then
        # Проброс SNI $SUB_FILES на xray (127.0.0.1:7443) через stream.
        add_stream_passthrough "$SUB_FILES" 7443
    fi

    # WebDAV остаётся на nginx (TLS терминирует nginx) — через xray не ходит.
    if [[ "$webdav" == "true" ]]; then
        add_site 35-webdav "server {
    listen 127.0.0.1:8443 ssl;
    server_name $SUB_WEBDAV;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://127.0.0.1:8090;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    else
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/35-webdav.conf"; reload_nginx
    fi

    # Формируем параметры подключения
    local -a conn_params=(
        "Веб-клиент: https://$SUB_FILES"
        "Админка: ssh -L 8080:localhost:8080 user@$DOMAIN -> http://localhost:8080"
        "Логин админа: $admin_user"
        "Пароль админа: $SFTPGO_ADMIN_PASSWORD"
    )
    local -a log_params=(
        "Веб-клиент: https://$SUB_FILES"
        "Админка: ssh -L 8080:localhost:8080 user@$DOMAIN -> http://localhost:8080"
        "Логин админа: $admin_user"
        "Пароль админа: $SFTPGO_ADMIN_PASSWORD"
    )

    if [[ "$sftp_ext" == "true" ]]; then
        conn_params+=("" "SFTP снаружи: sftp -P 2022 <user>@$PUBLIC_IP")
        log_params+=("SFTP: sftp -P 2022 <user>@$PUBLIC_IP")
    fi

    if [[ -n "$cloud_user" ]]; then
        conn_params+=("" "Пользователь облака:" "  Логин: $cloud_user" "  Пароль: $cloud_pass")
        log_params+=("Пользователь облака: $cloud_user / $cloud_pass")
    fi

    if [[ "$tls_mode" == "xray" ]]; then
        conn_params+=("" "TLS: SNI $SUB_FILES -> 127.0.0.1:7443 (xray VLESS+REALITY)")
        conn_params+=("  VLESS-клиенты: TLS 1.3 завершает xray (REALITY)")
        conn_params+=("  Браузеры: dest xray 127.0.0.1:8443 -> этот nginx (TLS 1.2/1.3)")
        log_params+=("TLS: xray 127.0.0.1:7443 (REALITY), dest 127.0.0.1:8443")
    fi

    if [[ "$webdav" == "true" ]]; then
        conn_params+=("" "WebDAV: https://$SUB_WEBDAV")
        log_params+=("WebDAV: https://$SUB_WEBDAV")
    fi

    # Вывод параметров подключения
    show_connection_info "SFTPGo" "${conn_params[@]}"

    # Сохранение параметров в файл
    log_connection_params "SFTPGo" "${log_params[@]}"
}

# Проброс TLS домена насквозь (SNI -> 127.0.0.1:PORT) через stream-блок nginx.
# Добавляет запись в STREAM_DOMAINS и пересобирает stream.d/00-map.conf
# (та же логика, что пункт 4 меню nginx).
add_stream_passthrough() {
    local domain="$1" port="$2"
    local entry="${domain}:${port}"
    local lst="${STREAM_DOMAINS:-}"

    [[ ":${lst//,/:}:" == *":${entry}:"* ]] && { log "Passthrough $entry уже есть в STREAM_DOMAINS"; return 0; }

    lst="${lst:+$lst,}$entry"
    update_env STREAM_DOMAINS "$lst"

    local map_file="$CONFIG_ROOT/config/nginx/stream.d/00-map.conf"
    {
        echo "map \$ssl_preread_server_name \$stream_upstream {"
        local e d p seen_ports=""
        IFS=','; for e in $lst; do
            [[ -z "$e" ]] && continue
            d="${e%%:*}"; p="${e##*:}"
            printf '    %-40s host_passthrough_%s;\n' "$d" "$p"
        done; unset IFS
        echo "    default web_tls;"
        echo "}"
        echo "upstream web_tls { server 127.0.0.1:8443; }"
        IFS=','; for e in $lst; do
            [[ -z "$e" ]] && continue
            p="${e##*:}"
            [[ ":$seen_ports:" == *":$p:"* ]] && continue
            seen_ports+="${seen_ports:+:}$p"
            printf 'upstream host_passthrough_%s { server 127.0.0.1:%s; }\n' "$p" "$p"
        done; unset IFS
    } > "$map_file"
    log "stream: SNI $domain -> 127.0.0.1:$port (00-map.conf пересобран)"
    reload_nginx
}

remove_sftpgo() {
    docker compose -f "$CONFIG_ROOT/docker-compose.yml" down --volumes sftpgo sftpgo-db 2>/dev/null || true
    rm_site 30-sftpgo
    rm_site 35-webdav
    rm -f "$CONFIG_ROOT/config/nginx/stream.d/00-map.conf"
    reload_nginx
    local sftpdata="${SFTPGO_DATA:-/opt/homeserver/sftpgo}"
    if [[ -d "$sftpdata" ]]; then
        ask_yn "Удалить папку данных $sftpdata?" && rm -rf "$sftpdata" && log "Данные удалены."
    fi
    ufw delete allow 2022/tcp comment 'SFTPGo SFTP' >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
    update_env SUB_FILES ""
    update_env SUB_WEBDAV ""
    update_env SFTPGO_DATA ""
    update_env SFTPGO_ADMIN_USER ""
    update_env SFTPGO_ADMIN_PASSWORD ""
    update_env SFTPGO_TLS_MODE ""
    update_env SFTPGO_SFTP_BIND ""
    log "SFTPGo удалён"
    read -rp "Enter — продолжить " _ || true
}
