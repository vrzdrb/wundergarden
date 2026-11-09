#!/usr/bin/env bash

SYNCTHING_DATA="$DATA_DIR/syncthing"

# fallback если скрипт запущен не через wundergarden.sh
command -v rm_site >/dev/null 2>&1 || rm_site() {
    rm -f "$CONFIG_ROOT/config/nginx/conf.d/${1}.conf"
    nginx -s reload 2>/dev/null || true
}
command -v reload_nginx >/dev/null 2>&1 || reload_nginx() {
    nginx -s reload 2>/dev/null || true
}

syncthing_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '(^|_)syncthing(-[0-9]+)?$'
}

install_syncthing() {
    ensure_prepared
    check_dependencies
    log "=== Syncthing ==="
    local gui_mode="local" gui_user="${SYNCTHING_GUI_AUTH:-admin:changeme}" gui_pass="" \
          devname="$(hostname)" syncdir="${SYNCTHING_SYNC_DIR:-$CONFIG_ROOT/data/syncthing/sync}" SUB_SYNC="${SUB_SYNC:-sync.$DOMAIN}" \
          rescan="${SYNCTHING_RESCAN:-3600}"
    gui_pass="${gui_user#*:}"; gui_user="${gui_user%%:*}"
    # GUI слушает только loopback; единственный слой авторизации — STGUIAUTH.
    # local: только SSH-туннель; public: сайт на nginx:8443 (TLS на nginx);
    # proxy: SNI-маршрут stream -> промежуточный прокси на loopback (TLS на прокси)
    local proxy_port="${SYNCTHING_PROXY_PORT:-7443}"
    if [[ -f "$CONFIG_ROOT/config/nginx/stream.d/61-sync-proxy.conf" ]]; then
        gui_mode="proxy"
    elif [[ -n "${SUB_SYNC:-}" ]]; then
        gui_mode="public"
    fi

    while true; do
        local gui_descr="только localhost (SSH-туннель)"
        [[ "$gui_mode" == "public" ]] && gui_descr="субдомен https://$SUB_SYNC (через nginx)"
        [[ "$gui_mode" == "proxy" ]] && gui_descr="субдомен https://$SUB_SYNC (через прокси 127.0.0.1:$proxy_port)"
        clear
        cat <<SUM
${c_mag} --- Настройки Syncthing ---${c_off}
  ${c_num}1.${c_off} ${c_txt}GUI: $gui_descr${c_off}
  ${c_num}2.${c_off} ${c_txt}Логин/пароль GUI: $gui_user /${c_off}
  ${c_num}3.${c_off} ${c_txt}Имя устройства: $devname${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка синхронизации по умолчанию: $syncdir${c_off}
  ${c_num}5.${c_off} ${c_txt}Интервал пересборки папки: ${rescan} с${c_off}
  ${c_num}6.${c_off} ${c_txt}Логи${c_off}
  ${c_num}7.${c_off} ${c_txt}Установить${c_off}
  ${c_num}8.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                echo "${c_txt} 1) только localhost — GUI через SSH-туннель (безопаснее)${c_off}"
                echo "${c_txt} 2) субдомен напрямую через nginx (HTTPS терминирует nginx)${c_off}"
                echo "${c_txt} 3) субдомен через промежуточный прокси (HTTPS терминирует прокси)${c_off}"
                case "$(ask "1/2/3" "1")" in
                    2) gui_mode="public"
                       local sub_in
                       sub_in="$(ask "Поддомен GUI (без домена)" "${SUB_SYNC%%.*}")"
                       [[ "$sub_in" == *.* ]] && SUB_SYNC="$sub_in" || SUB_SYNC="$sub_in.$DOMAIN"
                       update_env SUB_SYNC "$SUB_SYNC"; dns_hint "$SUB_SYNC" ;;
                    3) gui_mode="proxy"
                       local sub_in
                       sub_in="$(ask "Поддомен GUI (без домена)" "${SUB_SYNC%%.*}")"
                       [[ "$sub_in" == *.* ]] && SUB_SYNC="$sub_in" || SUB_SYNC="$sub_in.$DOMAIN"
                       update_env SUB_SYNC "$SUB_SYNC"; dns_hint "$SUB_SYNC"
                       proxy_port="$(ask "Порт промежуточного прокси (loopback)" "$proxy_port")"
                       update_env SYNCTHING_PROXY_PORT "$proxy_port" ;;
                    *) gui_mode="local" ;;
                esac ;;
            2)
                gui_user="$(ask "Логин GUI" "$gui_user")"
                while :; do
                    gui_pass="$(ask "Пароль GUI (Enter — сгенерировать; без символа ':')" "$(gen_pass)")"
                    [[ "$gui_pass" != *:* ]] && break
                    warn "пароль не должен содержать ':' — это разделитель в STGUIAUTH"
                done ;;
            3) devname="$(ask "Имя устройства (видят пиры при синхронизации)" "$devname")" ;;
            4) syncdir="$(ask "Хост-путь папки (сюда кладите .kdbx от KeePass)" "$syncdir")" ;;
            5)
                echo "${c_txt}Как часто Syncthing сканирует папку на изменения.${c_off}"
                echo "${c_txt}0 — только события файловой системы (самый экономный, на Linux надёжен);${c_off}"
                echo "${c_txt}3600 — раз в час (дефолт); значения ниже — чаще сканирование и больше CPU на больших папках.${c_off}"
                local rs; rs="$(ask "Интервал, секунд" "$rescan")"
                [[ "$rs" =~ ^[0-9]+$ ]] && rescan="$rs" || warn "нужно число — оставляю $rescan" ;;
            6) logs_menu syncthing ;;
            7) break ;;
            8) remove_syncthing; return 0 ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    update_env SYNCTHING_GUI_AUTH "$gui_user:$gui_pass"
    update_env SYNCTHING_GUI_BIND "127.0.0.1:8384"
    update_env SYNCTHING_SYNC_DIR "$syncdir"; update_env SYNCTHING_RESCAN "$rescan"
    mkdir -p "$syncdir" "$DATA_DIR/syncthing"
    chown -R 1000:1000 "$syncdir" "$DATA_DIR/syncthing" 2>/dev/null || true

    # Открываем порты синхронизации в UFW (без дублирования правил)
    require_cmd ufw ufw
    ufw status 2>/dev/null | grep -q "22000/tcp" || ufw allow 22000/tcp comment 'Syncthing sync' >/dev/null 2>&1 && log "UFW: порт 22000/tcp открыт" || warn "Ошибка UFW"
    ufw status 2>/dev/null | grep -q "22000/udp" || ufw allow 22000/udp comment 'Syncthing sync' >/dev/null 2>&1 && log "UFW: порт 22000/udp открыт" || warn "Ошибка UFW"
    ufw status 2>/dev/null | grep -q "21027/udp" || ufw allow 21027/udp comment 'Syncthing discovery' >/dev/null 2>&1 && log "UFW: порт 21027/udp открыт" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1 || true

    docker compose -f "$COMPOSE_FILE" up -d syncthing

    # Ожидание инициализации Syncthing (до 30 секунд)
    log "Ожидание инициализации Syncthing..."
    for i in {1..15}; do
        if [[ -f "$DATA_DIR/syncthing/config.xml" ]]; then
            log "config.xml найден (попытка $i/15)"
            break
        fi
        sleep 2
    done

    local key devid
    key=$(grep -oPm1 '(?<=<apikey>)[^<]+' "$DATA_DIR/syncthing/config.xml" 2>/dev/null || true)
    if [[ -n "$key" ]]; then
        # Ждём готовности API (до 20 секунд)
        log "Ожидание готовности API Syncthing..."
        for i in {1..10}; do
            if curl -s -m 2 -H "X-API-Key: $key" http://127.0.0.1:8384/rest/system/version >/dev/null 2>&1; then
                log "API готов (попытка $i/10)"
                break
            fi
            sleep 2
        done

        devid=$(curl -s -m 5 -H "X-API-Key: $key" http://127.0.0.1:8384/rest/config/devices \
                | grep -oE '[A-Z0-9]{7}(-[A-Z0-9]{7}){7}' | head -1)
        if [[ -n "$devid" ]]; then
            curl -s -m 5 -o /dev/null -X PATCH -H "X-API-Key: $key" -H 'Content-Type: application/json' \
                "http://127.0.0.1:8384/rest/config/devices/$devid" -d "{\"name\":\"$devname\"}" \
                && log "Имя устройства: $devname" || warn "Имя устройства не применилось — задайте в GUI."
        else
            warn "Device ID не получен — имя задайте в GUI."
        fi
    else
        warn "API key не получен — настройте имя устройства вручную в GUI"
    fi

    if [[ -n "$key" ]]; then
        local fid
        while IFS= read -r fid; do
            [[ -z "$fid" ]] && continue
            curl -s -m 5 -o /dev/null -X PATCH -H "X-API-Key: $key" -H 'Content-Type: application/json' \
                "http://127.0.0.1:8384/rest/config/folders/$fid" -d "{\"rescanIntervalS\":$rescan}" \
                || warn "не удалось применить интервал к папке '$fid' — задайте в GUI (Folder -> Advanced)"
        done < <(curl -s -m 5 -H "X-API-Key: $key" http://127.0.0.1:8384/rest/config/folders \
                 | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    fi

    local map_file="$CONFIG_ROOT/config/nginx/stream.d/00-map.conf"
    local proxy_conf="$CONFIG_ROOT/config/nginx/stream.d/61-sync-proxy.conf"
    if [[ "$gui_mode" == "public" ]]; then
        # Единственный слой авторизации — STGUIAUTH самого Syncthing
        # (защищает GUI и через субдомен, и через SSH-туннель)
        rm -f "$proxy_conf"
        sed -i "/stream_syncthing;/d" "$map_file" 2>/dev/null || true
        add_site 60-sync "server {
    listen 127.0.0.1:8443 ssl;
    server_name $SUB_SYNC;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8384;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    elif [[ "$gui_mode" == "proxy" ]]; then
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/60-sync.conf"
        # SNI-маршрут stream: sync.$DOMAIN -> промежуточный прокси на loopback
        # (TLS терминируется на прокси; прокси передаёт plain HTTP на 127.0.0.1:8384)
        printf 'upstream stream_syncthing { server 127.0.0.1:%s; }\n' "$proxy_port" > "$proxy_conf"
        sed -i "/stream_syncthing;/d" "$map_file" 2>/dev/null || true
        sed -i "s|^    default web_tls;|    $SUB_SYNC stream_syncthing;\n    default web_tls;|" "$map_file"
        nginx -t >/dev/null 2>&1 && reload_nginx || die "ошибка конфигурации nginx (stream-маршрут)"
    else
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/60-sync.conf" "$proxy_conf"
        sed -i "/stream_syncthing;/d" "$map_file" 2>/dev/null || true
        reload_nginx
    fi

    # Вывод параметров подключения
    local gui_via="публичный доступ"
    [[ "$gui_mode" == "proxy" ]] && gui_via="через промежуточный прокси 127.0.0.1:$proxy_port"
    if [[ "$gui_mode" != "local" ]]; then
        show_connection_info "Syncthing" \
            "GUI ($gui_via):" \
            "  URL: https://$SUB_SYNC" \
            "  Логин: $gui_user" \
            "  Пароль: $gui_pass" \
            "" \
            "Папка синхронизации: $syncdir" \
            "Порты: 22000 tcp/udp + 21027/udp (открыты в UFW)" \
            "" \
            "Для синхронизации с другими устройствами:" \
            "  1. Откройте GUI" \
            "  2. Add Remote Device -> обмен Device ID" \
            "  3. Выберите папку для синхронизации"

        log_connection_params "Syncthing" \
            "GUI URL: https://$SUB_SYNC" \
            "Логин: $gui_user" \
            "Пароль: $gui_pass" \
            "Папка: $syncdir"
    else
        show_connection_info "Syncthing" \
            "GUI (через SSH-туннель):" \
            "  1. Откройте терминал на своём компьютере" \
            "  2. Выполните: ssh -L 8384:localhost:8384 user@$DOMAIN" \
            "  3. Откройте в браузере: http://localhost:8384" \
            "  4. Логин: $gui_user" \
            "  5. Пароль: $gui_pass" \
            "" \
            "Папка синхронизации: $syncdir" \
            "Порты: 22000 tcp/udp + 21027/udp (открыты в UFW)" \
            "" \
            "Для синхронизации с другими устройствами:" \
            "  1. Откройте GUI через SSH-туннель" \
            "  2. Add Remote Device -> обмен Device ID" \
            "  3. Выберите папку для синхронизации"

        log_connection_params "Syncthing" \
            "GUI: ssh -L 8384:localhost:8384 user@$DOMAIN -> http://localhost:8384" \
            "Логин: $gui_user" \
            "Пароль: $gui_pass" \
            "Папка: $syncdir"
    fi
}

syncthing_container_logs() {
    docker compose -f "$COMPOSE_FILE" logs --tail 50 -f syncthing 2>/dev/null &
    local pid=$!
    read -rp "Enter — остановить просмотр логов " _ || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

remove_syncthing() {
    [[ -d "$SYNCTHING_DATA" ]] || { warn "Syncthing не установлен"; read -rp "Enter — продолжить " _ || true; return 1; }
    ask_yn "Удалить Syncthing? Настройки и данные синхронизации будут потеряны." || return 0

    docker compose -f "$COMPOSE_FILE" down --volumes syncthing 2>/dev/null || true
    rm_site 60-sync
    rm -f "$CONFIG_ROOT/config/nginx/stream.d/61-sync-proxy.conf"
    sed -i "/stream_syncthing;/d" "$CONFIG_ROOT/config/nginx/stream.d/00-map.conf" 2>/dev/null || true
    reload_nginx
    rm -rf "$SYNCTHING_DATA"
    update_env SUB_SYNC ""; update_env SYNCTHING_PROXY_PORT ""
    log "Syncthing удалён"
    read -rp "Enter — продолжить " _ || true
}

syncthing_menu() {
    while true; do
        local st="не установлен"
        if [[ -d "$SYNCTHING_DATA" && -n "$(ls -A "$SYNCTHING_DATA" 2>/dev/null)" ]]; then
            st="не активен"
            if syncthing_running; then
                st="активен"
            fi
        fi
        cat <<SUM
${c_mag} --- Syncthing | статус: ${st} ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Установка / переустановка${c_off}
  ${c_num}2.${c_off} ${c_txt}Логи контейнера (последние 50 строк + реальное время)${c_off}
  ${c_num}3.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) install_syncthing ;;
            2) syncthing_container_logs ;;
            3) remove_syncthing ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Enter — продолжить " _ || true ;;
        esac
    done
}
