#!/usr/bin/env bash

install_classquiz() {
    ensure_prepared
    check_dependencies
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
        clear
        cat <<SUM

${c_mag} --- Настройки ClassQuiz ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB${c_off}
  ${c_num}2.${c_off} ${c_txt}Secret key: задан${c_off}
  ${c_num}3.${c_off} ${c_txt}Пропуск верификации email: $se_descr${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка загрузок: $uploads${c_off}
  ${c_num}5.${c_off} ${c_txt}Образы: ${img_api##*/} | ${img_front##*/}${c_off}
  ${c_num}6.${c_off} ${c_txt}Лимит RAM Meilisearch: ${meili_mem} МБ${c_off}
  ${c_num}7.${c_off} ${c_txt}Доступ: $cq_prot_descr${c_off}
  Примечание: PostgreSQL и Valkey — требование архитектуры ClassQuiz.

 ${c_num}8.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
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
                echo "${c_txt}Meilisearch держит поисковый индекс викторин в RAM.${c_off}"
                echo "${c_txt}Минимум ~128 МБ (пара-тройка викторин); рекомендуется 256–512 МБ.${c_off}"
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
            8) logs_menu classquiz-frontend classquiz-api classquiz-worker classquiz-db classquiz-redis classquiz-meili  ;;
            0) break ;;
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
    listen [::]:8443 ssl;
    server_name $SUB;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
${cq_auth}    location /api/ {
        proxy_pass http://127.0.0.1:3014;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
        client_max_body_size 50m;
    }
    location / {
        proxy_pass http://127.0.0.1:3002;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    
    # Формируем параметры подключения
    local -a conn_params=("URL: https://$SUB")
    local -a log_params=("URL: https://$SUB")
    
    if [[ "$protected" == "true" ]]; then
        conn_params+=("Логин: $user" "Пароль: $pass" "" "Ученики могут играть по PIN без авторизации")
        log_params+=("Логин: $user" "Пароль: $pass")
    fi
    
    # Вывод параметров подключения
    show_connection_info "ClassQuiz" "${conn_params[@]}"
    
    # Сохранение параметров в файл
    log_connection_params "ClassQuiz" "${log_params[@]}"
}
