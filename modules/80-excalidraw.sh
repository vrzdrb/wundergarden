#!/usr/bin/env bash

EXCALIDRAW_DATA="${EXCALIDRAW_STORAGE:-$DATA_DIR/excalidraw}"

# fallback если скрипт запущен не через wundergarden.sh
command -v rm_site >/dev/null 2>&1 || rm_site() {
    rm -f "$CONFIG_ROOT/config/nginx/conf.d/${1}.conf"
    nginx -s reload 2>/dev/null || true
}
command -v reload_nginx >/dev/null 2>&1 || reload_nginx() {
    nginx -s reload 2>/dev/null || true
}

excalidraw_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qE 'excalidraw(-[0-9]+)?$'
}

install_excalidraw() {
    ensure_prepared
    check_dependencies
    log "=== Excalidraw (доска + сохранение + комнаты) ==="
    local SUB="${SUB_EXCALIDRAW:-draw.$DOMAIN}" protected="true" collab="true" \
          storage="${EXCALIDRAW_STORAGE:-$DATA_DIR/excalidraw}" \
          img_front="${EXCALIDRAW_IMAGE:-alswl/excalidraw:latest}" \
          img_room="${EXCALIDRAW_ROOM_IMAGE:-alswl/excalidraw-room-go:v0.1.0}" \
          img_storage="${EXCALIDRAW_STORAGE_IMAGE:-alswl/excalidraw-storage-backend:latest}" \
          user="" pass=""
    dns_hint "$SUB"

    while true; do
        local prot_descr="по паролю (basicauth)" collab_descr="вкл"
        [[ "$protected" == "false" ]] && prot_descr="открытый (любой по ссылке)"
        [[ "$collab" == "false" ]] && collab_descr="выкл (только личные доски)"
        clear
        cat <<SUM

${c_mag} --- Настройки Excalidraw ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB${c_off}
  ${c_num}2.${c_off} ${c_txt}Доступ: $prot_descr${c_off}
  ${c_num}3.${c_off} ${c_txt}Live Collaboration: $collab_descr${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка хранения досок: $storage${c_off}
  ${c_num}5.${c_off} ${c_txt}Образы: ${img_front##*/} | ${img_room##*/} | ${img_storage##*/}${c_off}

 ${c_num}6.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_EXCALIDRAW "$SUB"; dns_hint "$SUB" ;;
            2)
                if [[ "$protected" == "true" ]]; then protected="false"
                else
                    protected="true"
                    user="$(ask "Логин" "draw")"
                    while :; do
                        pass="$(ask "Пароль basicauth (Enter — сгенерировать)" "$(gen_pass)")"
                        [[ -n "$pass" ]] && break
                    done
                fi ;;
            3) [[ "$collab" == "true" ]] && collab="false" || collab="true" ;;
            4) storage="$(ask "Папка на хосте для сцен/файлов досок" "$storage")" ;;
            5)
                img_front="$(ask "Образ frontend (форк alswl)" "$img_front")"
                img_room="$(ask "Образ room-сервера (пин версии, см. README alswl)" "$img_room")"
                img_storage="$(ask "Образ storage backend" "$img_storage")" ;;
            6) logs_menu excalidraw excalidraw-room excalidraw-storage excalidraw-db ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_EXCALIDRAW "$SUB"; update_env EXCALIDRAW_STORAGE "$storage"
    update_env EXCALIDRAW_IMAGE "$img_front"; update_env EXCALIDRAW_ROOM_IMAGE "$img_room"; update_env EXCALIDRAW_STORAGE_IMAGE "$img_storage"
    local db_data="${EXCALIDRAW_DB_DATA:-$DATA_DIR/excalidraw-db}" db_pass="${EXCALIDRAW_DB_PASSWORD:-}"
    [[ -z "$db_pass" ]] && { db_pass="$(gen_pass)"; update_env EXCALIDRAW_DB_PASSWORD "$db_pass"; }
    mkdir -p "$storage" "$db_data"
    chown -R 1000:1000 "$storage" "$db_data" 2>/dev/null || true

    # Проверяем доступность образов
    log "Проверяю доступность образов..."
    for img in "$img_front" "$img_room" "$img_storage"; do
        if ! docker pull "$img" >/dev/null 2>&1; then
            die "Образ $img недоступен. Проверьте имя образа и доступ к Docker Hub."
        fi
    done

    docker compose -f "$COMPOSE_FILE" up -d excalidraw excalidraw-room excalidraw-storage excalidraw-db

    # Ожидаем готовности контейнеров
    log "Ожидание готовности Excalidraw..."
    for i in {1..15}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/ 2>/dev/null | grep -q "200"; then
            log "Excalidraw готов (попытка $i/15)"
            break
        fi
        sleep 2
    done

    if [[ "$collab" == "true" ]]; then
        log "Ожидание готовности Excalidraw Room..."
        for i in {1..10}; do
            if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3012/ 2>/dev/null | grep -qE "200|404"; then
                log "Excalidraw Room готов (попытка $i/10)"
                break
            fi
            sleep 2
        done
    fi
    local draw_auth=""
    if [[ "$protected" == "true" ]]; then
        [[ -z "$user" ]] && { user="draw"; pass="$(gen_pass)"; }
        mk_htpasswd draw "$user" "$pass"
        draw_auth=$(auth_conf draw "Excalidraw")
        log "basicauth: $user / $pass"
    fi
    add_site 45-draw "server {
    listen 127.0.0.1:8443 ssl;
    server_name $SUB;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
${draw_auth}    location /storage/ {
        proxy_pass http://127.0.0.1:3013/;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
    location /socket.io/ {
        proxy_pass http://127.0.0.1:3012;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
        include $CONFIG_ROOT/config/nginx/ws_common.conf;
    }
    location / {
        proxy_pass http://127.0.0.1:3001;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"

    # Формируем параметры подключения
    local -a conn_params=("URL: https://$SUB")
    local -a log_params=("URL: https://$SUB")

    if [[ "$protected" == "true" ]]; then
        conn_params+=("Логин: $user" "Пароль: $pass")
        log_params+=("Логин: $user" "Пароль: $pass")
    fi

    conn_params+=("" "Доски сохраняются на сервере: $storage" "Экспорт: .excalidraw/PNG/SVG")

    if [[ "$collab" == "true" ]]; then
        conn_params+=("" "Live Collaboration: меню -> Start session -> ссылка ученику")
    else
        conn_params+=("" "⚠ Комнаты выключены — Live Collaboration не подключится")
    fi

    # Вывод параметров подключения (с обязательной паузой)
    show_connection_info "Excalidraw" "${conn_params[@]}"

    # Сохранение параметров в файл
    log_connection_params "Excalidraw" "${log_params[@]}"
}

excalidraw_container_logs() {
    docker compose -f "$COMPOSE_FILE" logs --tail 100 excalidraw excalidraw-room excalidraw-storage excalidraw-db 2>/dev/null \
        || warn "не удалось получить логи контейнеров"
    read -rp "Enter — продолжить " _ || true
}

remove_excalidraw() {
    [[ -d "$EXCALIDRAW_DATA" ]] || { warn "Excalidraw не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    ask_yn "Удалить Excalidraw? Все доски и сцены будут потеряны." || return 0

    docker compose -f "$COMPOSE_FILE" down --volumes excalidraw excalidraw-room excalidraw-storage excalidraw-db 2>/dev/null || true
    rm_site 45-draw
    rm -rf "$EXCALIDRAW_DATA" "${EXCALIDRAW_DB_DATA:-$DATA_DIR/excalidraw-db}"
    update_env SUB_EXCALIDRAW ""; update_env EXCALIDRAW_DB_PASSWORD ""
    log "Excalidraw удалён"
    read -rp "Enter — продолжить " _ || true
}

excalidraw_menu() {
    while true; do
        local st="не установлен"
        if [[ -d "$EXCALIDRAW_DATA" && -n "$(ls -A "$EXCALIDRAW_DATA" 2>/dev/null)" ]]; then
            st="не активен"
            if excalidraw_running; then
                st="активен"
            fi
        fi
        cat <<SUM
${c_mag} --- Excalidraw | статус: ${st} ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Логи контейнеров (последние 100 строк)${c_off}
  ${c_num}3.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_excalidraw ;;
            2) excalidraw_container_logs ;;
            3) remove_excalidraw ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Enter — продолжить " _ || true ;;
        esac
    done
}
