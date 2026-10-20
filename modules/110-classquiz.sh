#!/usr/bin/env bash
# modules/110-classquiz.sh — сервис: classquiz
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_classquiz() {
    ensure_prepared
    log "=== ClassQuiz (викторины Kahoot-стиля) ==="
    local SUB="${SUB_CLASSQUIZ:-quiz.$DOMAIN}" secret="${CLASSQUIZ_SECRET_KEY:-$(gen_pass)}" \
          skip_email="${CLASSQUIZ_SKIP_EMAIL:-True}" uploads="${CLASSQUIZ_UPLOADS:-$CONFIG_ROOT/data/classquiz}" \
          meili_mem="${CLASSQUIZ_MEILI_MEM:-256m}"; meili_mem="${meili_mem%m}" \
          protected="true" user="" pass="" \
          img_api="${CLASSQUIZ_IMAGE:-ghcr.io/mawoka-myblock/classquiz-backend:master}" \
          img_front="${CLASSQUIZ_FRONTEND_IMAGE:-ghcr.io/mawoka-myblock/classquiz-frontend:master}"
    dns_hint "$SUB"

    while true; do
        local se_descr="вкл (без подтверждения email — SMTP не нужен)" cq_prot_descr="по паролю (basicauth)"
        [[ "$skip_email" == "False" ]] && se_descr="выкл (понадобится SMTP!)"
        [[ "$protected" == "false" ]] && cq_prot_descr="открытый (регистрация для всех!)"
        cat <<SUM

 --- Настройки ClassQuiz ---
  1. Поддомен: https://$SUB
  2. Secret key: задан (в .env)
  3. Пропуск верификации email: $se_descr
  4. Папка загрузок (картинки викторин): $uploads
  5. Образы: ${img_api##*/} | ${img_front##*/}
  6. Лимит RAM Meilisearch: ${meili_mem} МБ
  7. Доступ: $cq_prot_descr
  Примечание: PostgreSQL и Valkey — требование архитектуры ClassQuiz (не MySQL-совместимо).

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_CLASSQUIZ "$SUB"; dns_hint "$SUB" ;;
            2) secret="$(gen_pass)"; log "Новый SECRET_KEY: $secret" ;;
            3) [[ "$skip_email" == "True" ]] && skip_email="False" || skip_email="True" ;;
            4) uploads="$(ask "Папка на хосте" "$uploads")" ;;
            5)
                img_api="$(ask "Образ backend" "$img_api")"
                img_front="$(ask "Образ frontend" "$img_front")" ;;
            6)
                echo "Meilisearch держит поисковый индекс викторин в RAM."
                echo "Минимум ~128 МБ (пара-тройка викторин); рекомендуется 256–512 МБ."
                local mm; mm="$(ask "Лимит, МБ (мин. 64)" "$meili_mem")"
                [[ "$mm" =~ ^[0-9]+$ && "$mm" -ge 64 ]] && meili_mem="$mm" || warn "нужно число >= 64 — оставляю $meili_mem" ;;
            7)
                if [[ "$protected" == "true" ]]; then protected="false"
                else
                    protected="true"
                    user="$(ask "Логин" "quiz")"
                    while :; do
                        pass="$(ask "Пароль basicauth (Enter — сгенерировать)" "$(gen_pass)")"
                        [[ -n "$pass" ]] && break
                    done
                fi ;;
            L|l|Д|д) logs_menu classquiz-frontend classquiz-api classquiz-worker classquiz-db classquiz-redis classquiz-meili ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_CLASSQUIZ "$SUB"; update_env CLASSQUIZ_SECRET_KEY "$secret"
    update_env CLASSQUIZ_SKIP_EMAIL "$skip_email"; update_env CLASSQUIZ_UPLOADS "$uploads"
    update_env CLASSQUIZ_IMAGE "$img_api"; update_env CLASSQUIZ_FRONTEND_IMAGE "$img_front"
    update_env CLASSQUIZ_MEILI_MEM "${meili_mem}m"
    mkdir -p "$uploads"

    docker compose up -d classquiz-db
    wait_container classquiz-db pg_isready -U classquiz
    docker compose up -d classquiz-redis classquiz-meili classquiz-api classquiz-worker classquiz-frontend

    local cq_auth=""
    if [[ "$protected" == "true" ]]; then
        [[ -z "$user" ]] && { user="quiz"; pass="$(gen_pass)"; }
        mk_htpasswd quiz "$user" "$pass"
        cq_auth=$(auth_conf quiz "ClassQuiz")
        log "basicauth: $user / $pass (ученикам сообщите пароль один раз — браузер его запомнит; игра по PIN работает)"
    fi
    add_site 48-quiz "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
${cq_auth}    location /api/ {
        proxy_pass http://classquiz-api:80;
        include /etc/nginx/proxy_common.conf;
        client_max_body_size 50m;
    }
    location / {
        proxy_pass http://classquiz-frontend:3000;
        include /etc/nginx/proxy_common.conf;
    }
}"
    log "Готово: https://$SUB"
}
