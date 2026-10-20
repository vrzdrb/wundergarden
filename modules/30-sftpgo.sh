#!/usr/bin/env bash
# modules/30-sftpgo.sh — сервис: sftpgo
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_sftpgo() {
    ensure_prepared
    log "=== SFTPGo (файлы + ссылки друзьям) ==="
    local sftpdata="${SFTPGO_DATA:-/mnt/emmc/cloud}" admin_user="${SFTPGO_ADMIN_USER:-admin}" \
          cloud_user="" cloud_pass="" cloud_quota=0 \
          sftp_ext="false" webdav="false" SUB_WEBDAV="${SUB_WEBDAV:-webdav.$DOMAIN}"
    [[ "${SFTPGO_SFTP_BIND:-127.0.0.1:2022}" != "127.0.0.1:2022" ]] && sftp_ext="true"

    SUB_FILES="$(ask "Поддомен веб-клиента (share-ссылки)" "${SUB_FILES:-files.$DOMAIN}")"; update_env SUB_FILES "$SUB_FILES"
    dns_hint "$SUB_FILES"

    while true; do
        local cloud_descr="не создавать" sftp_descr="выкл (только туннель)" webdav_descr="выкл"
        [[ -n "$cloud_user" ]] && cloud_descr="$cloud_user (квота ${cloud_quota} МБ)"
        [[ "$sftp_ext" == "true" ]] && sftp_descr="вкл (0.0.0.0:2022)"
        [[ "$webdav" == "true" ]] && webdav_descr="https://$SUB_WEBDAV"
        cat <<SUM

 --- Настройки SFTPGo ---
  1. Папка данных (eMMC): $sftpdata
  2. Веб-клиент: https://$SUB_FILES
  3. Админ: $admin_user (пароль в .env)
  4. Пользователь облака: $cloud_descr
  5. SFTP наружу (2022/tcp): $sftp_descr
  6. WebDAV через nginx: $webdav_descr
  БД: MariaDB (контейнер sftpgo-db); sqlite/postgres — только вручную через env.
  Внимание: пользователи/настройки из старой sqlite-установки автоматически НЕ переезжают.

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                sftpdata="$(ask "Папка данных на eMMC" "$sftpdata")"
                if findmnt -n -T "$sftpdata" 2>/dev/null | awk '{print $1}' | grep -q '^/$'; then
                    warn "$sftpdata на корневом разделе, а не на eMMC."
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
                        cloud_pass="$(ask "Пароль (Enter — сгенерировать; без кавычек и \\)" "$(gen_pass)")"
                        [[ "$cloud_pass" != *[\"\\]* ]] && break
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
            L|l|Д|д) logs_menu sftpgo sftpgo-db ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    mkdir -p "$sftpdata"; update_env SFTPGO_DATA "$sftpdata"
    update_env SFTPGO_SFTP_BIND "$([[ "$sftp_ext" == "true" ]] && echo 0.0.0.0:2022 || echo 127.0.0.1:2022)"

    docker compose up -d sftpgo-db
    wait_container sftpgo-db mariadb-admin ping -h127.0.0.1
    docker compose up -d sftpgo
    sleep 4

    # --- создание пользователя облака через API ---
    if [[ -n "$cloud_user" ]]; then
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' -u "$admin_user:$SFTPGO_ADMIN_PASSWORD" -X POST \
            http://127.0.0.1:8080/api/v2/users -H 'Content-Type: application/json' \
            -d "{\"username\":\"$cloud_user\",\"password\":\"$cloud_pass\",\"status\":1,\"permissions\":[\"*\"],\"quota_size\":$((cloud_quota*1024*1024))}")
        case "$code" in
            201) log "Пользователь '$cloud_user' создан (квота $cloud_quota МБ, домашняя папка на eMMC)." ;;
            409) warn "Пользователь '$cloud_user' уже существует — пропускаю." ;;
            *)   warn "Не удалось создать пользователя (HTTP $code) — создайте в админке." ;;
        esac
    fi

    add_site 30-files "server {
    listen 8443 ssl;
    server_name $SUB_FILES;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location /web/admin { return 403; }
    location / {
        proxy_pass http://sftpgo:8080;
        include /etc/nginx/proxy_common.conf;
    }
}"
    if [[ "$webdav" == "true" ]]; then
        add_site 35-webdav "server {
    listen 8443 ssl;
    server_name $SUB_WEBDAV;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://sftpgo:8090;
        include /etc/nginx/proxy_common.conf;
    }
}"
    else
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/35-webdav.conf"; reload_nginx
    fi

    local sftp_note="" webdav_note=""
    [[ "$sftp_ext" == "true" ]] && sftp_note=" SFTP снаружи: sftp -P 2022 <user>@$PUBLIC_IP (откройте 2022/tcp в UFW и на роутере)."
    [[ "$webdav" == "true" ]] && sftp_note="$sftp_note"$'\n'" WebDAV: https://$SUB_WEBDAV (логин/пароль пользователя облака; для rclone/DAVx⁵)."
    cat <<EOF

 Готово.
 Веб-клиент: https://$SUB_FILES (share-ссылки друзьям создаются в нём)
 Админка: ssh -L 8080:localhost:8080 user@$DOMAIN -> http://localhost:8080 ($admin_user)
$sftp_note
EOF
}
