#!/usr/bin/env bash
# modules/40-syncthing.sh — сервис: syncthing
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_syncthing() {
    ensure_prepared
    log "=== Syncthing ==="
    local gui_mode="local" gui_user="${SYNCTHING_GUI_AUTH:-admin:changeme}" gui_pass="" \
          devname="$(hostname)" syncdir="${SYNCTHING_SYNC_DIR:-$CONFIG_ROOT/data/syncthing/sync}" SUB_SYNC="${SUB_SYNC:-sync.$DOMAIN}" \
          rescan="${SYNCTHING_RESCAN:-3600}"
    gui_pass="${gui_user#*:}"; gui_user="${gui_user%%:*}"
    [[ "${SYNCTHING_GUI_BIND:-127.0.0.1:8384}" != "127.0.0.1:8384" ]] && gui_mode="public"

    while true; do
        local gui_descr="только localhost (SSH-туннель)"
        [[ "$gui_mode" == "public" ]] && gui_descr="субдомен https://$SUB_SYNC (+basicauth и пароль GUI)"
        cat <<SUM

${c_mag} --- Настройки Syncthing ---${c_off}
  ${c_num}1.${c_off} ${c_txt}GUI: $gui_descr${c_off}
  ${c_num}2.${c_off} ${c_txt}Логин/пароль GUI: $gui_user / (см. .env: SYNCTHING_GUI_AUTH)${c_off}
  ${c_num}3.${c_off} ${c_txt}Имя устройства: $devname${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка синхронизации по умолчанию: $syncdir${c_off}
  ${c_num}5.${c_off} ${c_txt}Интервал пересборки папки: ${rescan} с (0 — только события ФС)${c_off}

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                echo "${c_txt} 1) только localhost — GUI через SSH-туннель (безопаснее)${c_off}"
                echo "${c_txt} 2) субдомен с basicauth — удобно из браузера, но GUI торчит наружу${c_off}"
                case "$(ask "1/2" "1")" in
                    2) gui_mode="public"
                       SUB_SYNC="$(ask "Поддомен GUI" "$SUB_SYNC")"; update_env SUB_SYNC "$SUB_SYNC"
                       dns_hint "$SUB_SYNC" ;;
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
            L|l|Д|д) logs_menu syncthing ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    update_env SYNCTHING_GUI_AUTH "$gui_user:$gui_pass"
    update_env SYNCTHING_GUI_BIND "$([[ "$gui_mode" == "public" ]] && echo 8384 || echo 127.0.0.1:8384)"
    update_env SYNCTHING_SYNC_DIR "$syncdir"; update_env SYNCTHING_RESCAN "$rescan"
    mkdir -p "$syncdir" "$DATA_DIR/syncthing"
    chown -R 1000:1000 "$syncdir" "$DATA_DIR/syncthing" 2>/dev/null || true

    docker compose up -d syncthing
    sleep 6

    # --- имя устройства через REST API ---
    local key devid
    key=$(grep -oPm1 '(?<=<apikey>)[^<]+' "$DATA_DIR/syncthing/config.xml" 2>/dev/null || true)
    if [[ -n "$key" ]]; then
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
        warn "config.xml ещё не создан — имя устройства задайте в GUI при первом входе."
    fi

    # --- интервал пересборки для всех папок ---
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

    if [[ "$gui_mode" == "public" ]]; then
        mk_htpasswd sync "$gui_user" "$gui_pass"
        add_site 60-sync "server {
    listen 8443 ssl;
    server_name $SUB_SYNC;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
$(auth_conf sync "Syncthing GUI")
    location / {
        proxy_pass http://syncthing:8384;
        include /etc/nginx/proxy_common.conf;
    }
}"
    else
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/60-sync.conf"; reload_nginx
    fi

    cat <<EOF

 Готово.
 GUI: $([[ "$gui_mode" == "public" ]] && echo "https://$SUB_SYNC (basicauth '$gui_user' + пароль GUI)" || echo "ssh -L 8384:localhost:8384 user@$DOMAIN -> http://localhost:8384")
 Пароль GUI: $gui_pass (.env: SYNCTHING_GUI_AUTH)
 Папка синхронизации: $syncdir (внутри контейнера /var/syncthing/Sync)
 Синхронизация: порты 22000 tcp/udp + 21027/udp открыты; в GUI: Add Remote Device -> обмен ID -> выбрать папку.
EOF
}
