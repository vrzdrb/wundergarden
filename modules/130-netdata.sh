#!/usr/bin/env bash

install_limesurvey() {
    ensure_prepared
    log "=== LimeSurvey (опросы и тесты) ==="
    local SUB="${SUB_LIMESURVEY:-survey.$DOMAIN}" dbtype="${LIMESURVEY_DB_TYPE:-mysql}" \
          admin_user="${LIMESURVEY_ADMIN_USER:-admin}" admin_name="${LIMESURVEY_ADMIN_NAME:-Admin}" \
          admin_pass="${LIMESURVEY_ADMIN_PASSWORD:-$(gen_pass)}" \
          uploads="${LIMESURVEY_UPLOADS:-$CONFIG_ROOT/data/limesurvey}" \
          img="${LIMESURVEY_IMAGE:-limesurvey/limesurvey:latest}" img_db="${LIMESURVEY_DB_IMAGE:-mariadb:11}"
    dns_hint "$SUB"

    while true; do
        clear
        clear
        cat <<SUM

${c_mag} --- Настройки LimeSurvey ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB${c_off}
  ${c_num}2.${c_off} ${c_txt}База данных: $${c_off}
  ${c_num}3.${c_off} ${c_txt}Админ: $admin_user, пароль: задан${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка uploads: $uploads${c_off}
  ${c_num}5.${c_off} ${c_txt}Образы: ${img##*/} | ${img_db##*/}${c_off}
  Примечание: для удалённого VPS тот же скрипт — просто запустите его там.

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_LIMESURVEY "$SUB"; dns_hint "$SUB" ;;
            2)
                echo "${c_txt} 1) MariaDB/MySQL — рекомендуется, лучше всего протестирована LimeSurvey${c_off}"
                echo "${c_txt} 2) PostgreSQL — поддерживается${c_off}"
                case "$(ask "1/2" "1")" in
                    2) dbtype="pgsql"; img_db="postgres:16-alpine" ;;
                    *) dbtype="mysql"; img_db="mariadb:11" ;;
                esac ;;
            3)
                admin_user="$(ask "Логин админа" "$admin_user")"
                admin_name="$(ask "Отображаемое имя" "$admin_name")"
                if ask_yn "Сгенерировать новый пароль админа?"; then
                    admin_pass="$(gen_pass)"; log "Новый пароль админа: $admin_pass"
                fi ;;
            4) uploads="$(ask "Папка на хосте (uploads, темы, экспорты)" "$uploads")" ;;
            5)
                img="$(ask "Образ приложения" "$img")"
                img_db="$(ask "Образ БД ($dbtype)" "$img_db")" ;;
            6) logs_menu limesurvey limesurvey-db  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_LIMESURVEY "$SUB"; update_env LIMESURVEY_DB_TYPE "$dbtype"
    update_env LIMESURVEY_DB_IMAGE "$img_db"
    update_env LIMESURVEY_DB_PORT "$([[ "$dbtype" == "pgsql" ]] && echo 5432 || echo 3306)"
    update_env LIMESURVEY_ADMIN_USER "$admin_user"; update_env LIMESURVEY_ADMIN_NAME "$admin_name"
    update_env LIMESURVEY_ADMIN_PASSWORD "$admin_pass"; update_env LIMESURVEY_UPLOADS "$uploads"
    update_env LIMESURVEY_IMAGE "$img"
    mkdir -p "$uploads"

    docker compose up -d limesurvey-db
    wait_container limesurvey-db mariadb-admin ping -h127.0.0.1
    docker compose up -d limesurvey

    add_site 49-survey "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 50m;
    location / {
        proxy_pass http://limesurvey:80;
        include /etc/nginx/proxy_common.conf;
    }
}"
    cat <<EOF

 Готово: https://$SUB  (админка: /index.php/admin/admin)
 Логин: $admin_user | пароль: $admin_pass (в .env: LIMESURVEY_ADMIN_PASSWORD)
 БД: $dbtype ($img_db), uploads: $uploads — всё в бэкапе.
 Первая настройка: Global settings -> отключите публичный список опросов (для приватности).
EOF
}
