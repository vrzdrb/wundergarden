#!/usr/bin/env bash

install_etherpad() {
    ensure_prepared
    log "=== Etherpad (совместный текстовый редактор) ==="
    local SUB="${SUB_ETHERPAD:-pad.$DOMAIN}" title="Etherpad" \
          padtext="Добро пожаловать! Этот документ синхронизируется между всеми участниками в реальном времени." \
          protected="false" req_session="false" user="" pass=""
    dns_hint "$SUB"

    while true; do
        local prot_descr="открытый (любой по ссылке)" sess_descr="выкл"
        [[ "$protected" == "true" ]] && prot_descr="по паролю (basicauth)"
        [[ "$req_session" == "true" ]] && sess_descr="вкл (только авторизованные)"
        clear
        cat <<SUM

${c_mag} --- Настройки Etherpad ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB${c_off}
  ${c_num}2.${c_off} ${c_txt}Название: $title${c_off}
  ${c_num}3.${c_off} ${c_txt}Текст нового пада: ${padtext:0:60}...${c_off}
  ${c_num}4.${c_off} ${c_txt}Доступ: $prot_descr${c_off}
  ${c_num}5.${c_off} ${c_txt}requireSession: $sess_descr${c_off}
  БД: MariaDB. Пады из старого dirty.db автоматически НЕ переезжают.

 ${c_num}6.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_ETHERPAD "$SUB"; dns_hint "$SUB" ;;
            2) title="$(ask "Название (без кавычек)" "$title")" ;;
            3)
                padtext="$(ask "Текст нового пада (одна строка, без кавычек)" "$padtext")" ;;
            4)
                if [[ "$protected" == "true" ]]; then protected="false"
                else
                    protected="true"
                    user="$(ask "Логин" "pad")"
                    while :; do
                        pass="$(ask "Пароль basicauth (Enter — сгенерировать)" "$(gen_pass)")"
                        [[ -n "$pass" ]] && break
                    done
                fi ;;
            5) [[ "$req_session" == "true" ]] && req_session="false" || req_session="true" ;;
            6) logs_menu etherpad etherpad-db  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_ETHERPAD "$SUB"

    if forbidden_json "$title" || forbidden_json "$padtext"; then
        die "название и текст пада не должны содержать кавычки или обратный слеш (JSON)"
    fi

    mkdir -p "$CONFIG_ROOT/config/etherpad" "$DATA_DIR/etherpad"
    cat > "$CONFIG_ROOT/config/etherpad/settings.json" <<EOF
{
  "title": "$title",
  "skinName": "colibris",
  "defaultPadText": "$padtext",
  "requireSession": $req_session,
  "dbType": "mysql",
  "dbSettings": {
    "host": "etherpad-db",
    "port": 3306,
    "user": "etherpad",
    "password": "$ETHERPAD_DB_PASSWORD",
    "database": "etherpad",
    "charset": "utf8mb4"
  },
  "suppressErrorsInPadText": true,
  "maxAge": 21600
}
EOF
    chmod 600 "$CONFIG_ROOT/config/etherpad/settings.json" 2>/dev/null || true

    docker compose up -d etherpad-db
    wait_container etherpad-db mariadb-admin ping -h127.0.0.1
    docker compose up -d etherpad

    local ep_auth=""
    if [[ "$protected" == "true" ]]; then
        [[ -z "$user" ]] && { user="pad"; pass="$(gen_pass)"; }
        mk_htpasswd pad "$user" "$pass"
        ep_auth=$(auth_conf pad "Etherpad")
        log "basicauth: $user / $pass"
    fi
    add_site 47-pad "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
${ep_auth}    location / {
        proxy_pass http://etherpad:9001;
        include /etc/nginx/proxy_common.conf;
        include /etc/nginx/ws_common.conf;
    }
}"

    local ep_note=""
    [[ "$protected" == "true" && -n "$user" ]] && ep_note=" Доступ только с паролем basicauth ($user / $pass)."
    cat <<EOF

 Готово: https://$SUB
 Каждый пад — по ссылке https://$SUB/<имя-пада>; цвета авторов, история правок, экспорт txt/md/pdf — встроены.$ep_note
 Плагины (таблицы, заголовки) — через env ADMIN_PLUGINS в compose, если понадобятся.
EOF
}
