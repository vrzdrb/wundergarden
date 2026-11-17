#!/usr/bin/env bash

GITEA_SYNC_SCRIPT="$CONFIG_ROOT/gitea-cert-sync.sh"

gitea_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qE 'gitea(-[0-9]+)?$'
}

# Собственная пересборка stream-мапы (автономно, без зависимостей от других модулей)
gitea_rebuild_stream_map() {
    local lst="${STREAM_DOMAINS:-}"
    local map_file="$NGINX_CONFIG_DIR/stream.d/00-map.conf"
    {
        echo 'map $ssl_preread_server_name $stream_upstream {'
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

# fallback на случай запуска модуля без 05-nginx.sh
command -v rm_site >/dev/null 2>&1 || rm_site() {
    rm -f "$CONFIG_ROOT/config/nginx/conf.d/${1}.conf"
    nginx -s reload 2>/dev/null || true
}

# Сертификаты gitea больше не синхронизируются: gitea работает по HTTP, TLS
# терминирует nginx на 127.0.0.1:8443 (REALITY fallback target). Переменная
# GITEA_SYNC_SCRIPT оставлена только для очистки cron при remove_gitea
# (защита от старых установок, где cert-sync ещё был).

install_gitea() {
    ensure_prepared
    check_dependencies
    log "=== Gitea (Git-хостинг, HTTPS на стороне gitea через stream passthrough) ==="

    local sub="${SUB_GITEA:+${SUB_GITEA%.$DOMAIN}}"
    sub="${sub:-git}"
    local port="${GITEA_PORT:-3000}" stream_port="${GITEA_STREAM_PORT:-}"
    local g_user="" g_email="" g_pass=""
    [[ -z "${GITEA_DB_PASSWORD:-}" ]] && { GITEA_DB_PASSWORD="$(gen_pass)"; update_env GITEA_DB_PASSWORD "$GITEA_DB_PASSWORD"; }

    while true; do
        local adm_descr="не задан (спросим при установке)"
        [[ -n "$g_user" ]] && adm_descr="$g_user / $g_email"
        clear
        cat <<SUM
${c_mag} --- Настройки Gitea ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: $sub (будет: $sub.$DOMAIN)${c_off}
  ${c_num}2.${c_off} ${c_txt}Локальный порт gitea: 127.0.0.1:$port${c_off}
  ${c_num}3.${c_off} ${c_txt}Порт stream passthrough: ${stream_port:-$port}${c_off}
  ${c_num}4.${c_off} ${c_txt}Первый админ: $adm_descr${c_off}
  ${c_num}5.${c_off} ${c_txt}Логи${c_off}
  ${c_num}6.${c_off} ${c_txt}Установить${c_off}
  ${c_num}7.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                sub="$(ask "Поддомен (только имя, пример: git)" "$sub")"
                if [[ ! "$sub" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
                    warn "некорректный поддомен — только a-z, 0-9, дефис (пример: git)"
                    sub="git"
                    continue
                fi
                dns_hint "${sub}.${DOMAIN}" ;;
            2)
                echo "${c_txt}Схема: nginx:443 (stream) → xray:<stream_port> (REALITY) → fallback на nginx:8443${c_off}"
                echo "${c_txt}(HTTPS) → proxy_pass http://127.0.0.1:<порт> (gitea HTTP). TLS терминирует nginx${c_off}"
                echo "${c_txt}на 8443, НЕ gitea — так REALITY использует nginx-TLS ServerHello как шаблон${c_off}"
                echo "${c_txt}(Go-TLS gitea ломает подмешивание auth-ответа). ROOT_URL остаётся https://.${c_off}"
                port="$(ask "Порт gitea HTTP (только 127.0.0.1)" "$port")"
                if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
                    warn "некорректный порт (1-65535)"
                    port="${GITEA_PORT:-3000}"
                    continue
                fi
                if ss -tln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
                    warn "порт $port уже занят — смотрите: ss -tlnp | grep :$port"
                fi ;;
            3)
                echo "${c_txt}nginx stream (443) направляет трафик этого домена на 127.0.0.1:<порт>${c_off}"
                echo "${c_txt}— это порт xray REALITY. По умолчанию совпадает с портом gitea, но если${c_off}"
                echo "${c_txt}между nginx и gitea стоит xray (рекомендуется), укажите порт xray.${c_off}"
                echo "${c_txt}xray при провале REALITY-auth уходит в fallback на nginx:8443 (НЕ на gitea),${c_off}"
                echo "${c_txt}а nginx:8443 proxy_pass на порт gitea HTTP.${c_off}"
                stream_port="$(ask "Порт stream passthrough (Enter = $port)" "${stream_port:-$port}")"
                [[ "$stream_port" =~ ^[0-9]+$ && "$stream_port" -ge 1 && "$stream_port" -le 65535 ]] \
                    || { warn "некорректный порт"; stream_port=""; } ;;
            4)
                g_user="$(ask "Логин первого админа" "admin")"
                [[ "$g_user" =~ ^[a-zA-Z0-9_-]+$ ]] || { warn "логин: буквы/цифры/_/-"; g_user=""; continue; }
                g_email="$(ask "Email админа" "admin@$DOMAIN")"
                [[ "$g_email" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || { warn "нужен корректный email"; g_email=""; continue; }
                g_pass="$(ask "Пароль админа (Enter — сгенерировать)" "$(gen_pass)")"
                [[ -n "$g_pass" ]] || { warn "пароль не может быть пустым"; continue; }
                log "Реквизиты админа заданы (применятся при установке)." ;;
            5) logs_menu gitea gitea-db ;;
            6) break ;;
            7) remove_gitea; return 0 ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    local SUB="${sub}.${DOMAIN}"
    stream_port="${stream_port:-$port}"
    update_env SUB_GITEA "$SUB"
    update_env GITEA_PORT "$port"
    update_env GITEA_STREAM_PORT "$stream_port"
    export SUB_GITEA="$SUB" GITEA_PORT="$port"

    # Пересобираем docker-compose.yml, если в нём ещё HTTPS-конфигурация gitea
    # (старая схема, где gitea сама терминировала TLS).
    if ! grep -q 'GITEA__server__PROTOCOL=http' "$COMPOSE_FILE" 2>/dev/null; then
        log "Обновляю docker-compose.yml (HTTP-конфигурация gitea, TLS на nginx:8443)..."
        gen_compose || die "не удалось пересобрать $COMPOSE_FILE — проверьте права и повторите"
        warn "compose-файл пересобран; другие контейнеры не затронуты (пересоздаются только при up)."
    fi

    if [[ -n "$(ls -A "$DATA_DIR/gitea" 2>/dev/null)" ]]; then
        ask_yn "Обнаружена существующая установка в $DATA_DIR/gitea — продолжить? Репозитории и пользователи сохранятся." \
            || return 0
    fi

    mkdir -p "$DATA_DIR/gitea" "$DATA_DIR/gitea-db"
    chown -R 1000:1000 "$DATA_DIR/gitea" 2>/dev/null || true

    docker compose -f "$COMPOSE_FILE" up -d gitea-db \
        || die "gitea-db не запустилась. Логи: docker compose -f $COMPOSE_FILE logs --tail 100 gitea-db
Типичные причины: нет места на диске (df -h), не задан GITEA_DB_PASSWORD, занят порт postgres."
    wait_container gitea-db pg_isready -U gitea -d gitea \
        || die "postgres не стал готов за отведённое время. Логи: docker compose -f $COMPOSE_FILE logs --tail 100 gitea-db
Проверьте: docker ps -a | grep gitea-db"

    docker compose -f "$COMPOSE_FILE" up -d gitea \
        || die "контейнер gitea не запустился. Логи: docker compose -f $COMPOSE_FILE logs --tail 100 gitea gitea-db
Типичные причины:
  - порт $port занят: ss -tlnp | grep :$port
  - нет прав на запись в $DATA_DIR/gitea"

    log "Жду готовности Gitea (http://127.0.0.1:$port)..."
    local tries=0 ready=0
    while [[ $tries -lt 30 ]]; do
        if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${port}/"; then ready=1; break; fi
        sleep 2; tries=$((tries + 1))
    done
    if [[ "$ready" != "1" ]]; then
        die "Gitea не отвечает по http://127.0.0.1:$port за 60 с. Логи: docker compose -f $COMPOSE_FILE logs --tail 100 gitea
Проверьте:
  - занятость порта: ss -tlnp | grep :$port
  - статус контейнера: docker ps -a | grep gitea"
    fi

    if docker compose -f "$COMPOSE_FILE" exec -T -u git gitea gitea admin user list 2>/dev/null | grep -q .; then
        log "Пользователи уже есть — создание админа пропущено."
        # Восстанавливаем для показа данные, введённые ранее (переменные сбрасываются при повторном прогоне)
        if [[ -z "$g_user" ]]; then
            g_user="$(docker compose -f "$COMPOSE_FILE" exec -T -u git gitea gitea admin user list 2>/dev/null | awk 'NR>1 {print $2; exit}')"
            [[ -z "$g_user" ]] && g_user="<список пользователей: docker compose -f $COMPOSE_FILE exec -T -u git gitea gitea admin user list>"
        fi
        [[ -z "$g_email" ]] && g_email="<задан при создании пользователя>"
        [[ -z "$g_pass" ]] && g_pass="<задан при создании; скрипт его не хранит. Сброс: docker compose -f $COMPOSE_FILE exec -T -u git gitea gitea admin user change-password -u <логин> -p <новый_пароль>"
    else
        [[ -z "$g_user" ]] && g_user="$(ask "Логин первого админа" "admin")"
        [[ -z "$g_email" ]] && g_email="$(ask "Email админа" "admin@$DOMAIN")"
        [[ -z "$g_pass" ]] && g_pass="$(ask "Пароль админа (Enter — сгенерировать)" "$(gen_pass)")"
        if docker compose -f "$COMPOSE_FILE" exec -T -u git gitea gitea admin user create --admin \
                --username "$g_user" --password "$g_pass" --email "$g_email" --must-change-password=false; then
            log "Админ '$g_user' создан."
        else
            warn "Не удалось создать админа. Повторите вручную:"
            warn "docker compose -f $COMPOSE_FILE exec -T -u git gitea gitea admin user create --admin --username <логин> --password <пароль> --email <email>"
            warn "Логи: docker compose -f $COMPOSE_FILE logs --tail 100 gitea"
        fi
    fi

    # Stream passthrough: nginx:443 -> 127.0.0.1:<stream_port> (gitea или xray)
    # Важно: синхронизируем .env и переменную сессии ДО пересборки мапы,
    # иначе rebuild пройдёт по устаревшему значению STREAM_DOMAINS.
    local new_entry="${SUB}:${stream_port}"
    if [[ -n "${STREAM_DOMAINS:-}" && ",${STREAM_DOMAINS}," == *",${SUB}:"* ]]; then
        STREAM_DOMAINS="$(echo "$STREAM_DOMAINS" | sed "s|[^,]*${SUB}:[0-9]*|${new_entry}|g")"
    elif [[ -n "${STREAM_DOMAINS:-}" ]]; then
        STREAM_DOMAINS="${STREAM_DOMAINS},${new_entry}"
    else
        STREAM_DOMAINS="$new_entry"
    fi
    update_env STREAM_DOMAINS "$STREAM_DOMAINS"
    export STREAM_DOMAINS
    gitea_rebuild_stream_map
    # nginx reverse-proxy на 127.0.0.1:8443: терминирует TLS и proxy_pass на gitea HTTP.
    # Это REALITY fallback target — xray:<stream_port> при провале auth уходит сюда,
    # nginx отвечает валидным TLS (nginx-TLS, не Go-TLS gitea), и REALITY-клиент
    # получает корректный ServerHello-шаблон. add_site сам вызывает reload_nginx,
    # который подхватывает и свежую stream-мапу, и этот site-конфиг.
    add_site 140-gitea "server {
    listen 127.0.0.1:8443 ssl;
    server_name $SUB;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://127.0.0.1:${port};
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
        include $CONFIG_ROOT/config/nginx/ws_common.conf;
    }
}"

    show_connection_info "Gitea" \
        "URL: https://$SUB" \
        "Логин: $g_user" \
        "Email: $g_email" \
        "Пароль: $g_pass" \
        "" \
        "Gitea слушает: 127.0.0.1:$port (HTTP)" \
        "Stream: nginx:443 → 127.0.0.1:$stream_port (xray REALITY)" \
        "REALITY fallback: 127.0.0.1:8443 (nginx HTTPS) → 127.0.0.1:$port (gitea HTTP)" \
        "Регистрация закрыта, SSH/LFS/OpenID выключены" \
        "Данные: $DATA_DIR/gitea + $DATA_DIR/gitea-db"

    log_connection_params "Gitea" \
        "URL: https://$SUB" \
        "Логин: $g_user" \
        "Email: $g_email" \
        "Пароль: $g_pass"
}

remove_gitea() {
    [[ -d "$DATA_DIR/gitea" ]] || { warn "Gitea не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    ask_yn "Удалить Gitea? Контейнеры и настройки nginx будут удалены." || return 0
    [[ -f "$ENV_FILE" ]] && load_env

    local SUB="${SUB_GITEA:-}"
    docker compose -f "$COMPOSE_FILE" stop gitea 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" rm -f gitea 2>/dev/null || true

    if [[ -n "$SUB" && -n "${STREAM_DOMAINS:-}" ]]; then
        STREAM_DOMAINS="$(echo "$STREAM_DOMAINS" | sed "s|[^,]*${SUB}:[0-9]*||g")"
        STREAM_DOMAINS="${STREAM_DOMAINS#,}"; STREAM_DOMAINS="${STREAM_DOMAINS%,}"; STREAM_DOMAINS="${STREAM_DOMAINS//,,/,}"
        update_env STREAM_DOMAINS "$STREAM_DOMAINS"
        export STREAM_DOMAINS
        gitea_rebuild_stream_map
        reload_nginx 2>/dev/null || true
    fi

    ( crontab -l 2>/dev/null | grep -vF "$GITEA_SYNC_SCRIPT" ) | crontab - 2>/dev/null || true
    rm -f "$GITEA_SYNC_SCRIPT"
    rm_site 140-gitea
    update_env SUB_GITEA ""
    update_env GITEA_STREAM_PORT ""

    if ask_yn "Удалить данные (репозитории и БД)? Без удаления можно переустановить с сохранением данных."; then
        docker compose -f "$COMPOSE_FILE" stop gitea-db 2>/dev/null || true
        docker compose -f "$COMPOSE_FILE" rm -f gitea-db 2>/dev/null || true
        rm -rf "$DATA_DIR/gitea" "$DATA_DIR/gitea-db"
        log "Данные Gitea удалены"
    else
        log "Данные сохранены: $DATA_DIR/gitea и $DATA_DIR/gitea-db"
    fi
    log "Gitea удалён"
    read -rp "Enter — продолжить " _ || true
}

gitea_menu() {
    while true; do
        clear
        local st="не установлен"
        if [[ -d "$DATA_DIR/gitea" && -n "$(ls -A "$DATA_DIR/gitea" 2>/dev/null)" ]]; then
            st="выкл"
            gitea_running && st="вкл"
        fi
        cat <<SUM
${c_mag} --- Gitea | статус: ${st} ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Логи контейнеров (последние 100 строк)${c_off}
  ${c_num}3.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_gitea ;;
            2)
                docker compose -f "$COMPOSE_FILE" logs --tail 100 gitea gitea-db 2>/dev/null \
                    || warn "не удалось получить логи: docker compose -f $COMPOSE_FILE logs gitea gitea-db"
                read -rp "Enter — продолжить " _ || true ;;
            3) remove_gitea ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}
