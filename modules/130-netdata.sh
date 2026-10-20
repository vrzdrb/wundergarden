#!/usr/bin/env bash
# modules/130-netdata.sh — сервис: netdata (мониторинг)
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_netdata() {
    ensure_prepared
    log "=== Netdata (мониторинг: сеть, контейнеры, БД, nginx) ==="
    local SUB="${SUB_NETDATA:-monitor.$DOMAIN}" access="tunnel" user="" pass=""

    while true; do
        local acc_descr="SSH-туннель (ssh -L 19999:localhost:19999)"
        [[ "$access" == "basicauth" ]] && acc_descr="https://$SUB (basicauth)"
        cat <<SUM

 --- Настройки Netdata ---
  1. Доступ: $acc_descr
  2. История: 12 часов (RAM-режим; теряется при рестарте контейнера)
  3. Netdata Cloud: выключен (всё остаётся локально)
  4. Поддомен (для basicauth): $SUB

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                echo " 1) только localhost + SSH-туннель (безопаснее, рекомендуется)"
                echo " 2) поддомен с basicauth через nginx — удобно из браузера"
                case "$(ask "1/2" "1")" in
                    2) access="basicauth"
                       SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_NETDATA "$SUB"
                       user="$(ask "Логин basicauth" "monitor")"
                       pass="$(ask "Пароль (Enter — сгенерировать)" "$(gen_pass)")" ;;
                    *) access="tunnel" ;;
                esac ;;
            2) log "История фиксирована: 12 часов в RAM (mode = ram, retention = 43200)." ;;
            3) log "Cloud выключен конфигом [cloud] enabled = no." ;;
            4)
                if [[ "$access" == "basicauth" ]]; then
                    SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_NETDATA "$SUB"; dns_hint "$SUB"
                else warn "актуально только при доступе 'basicauth' (пункт 1)"; fi ;;
            L|l|Д|д) logs_menu netdata socket-proxy ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    mkdir -p "$DATA_DIR/netdata"
    cat > "$DATA_DIR/netdata/netdata.conf" <<'EOF'
[db]
    mode = ram
    retention = 43200

[cloud]
    enabled = no

[web]
    bind to = 0.0.0.0:19999
EOF
    chmod 600 "$DATA_DIR/netdata/netdata.conf" 2>/dev/null || true

    docker compose up -d socket-proxy netdata

    if [[ "$access" == "basicauth" ]]; then
        mk_htpasswd monitor "$user" "$pass"
        add_site 130-monitor "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
$(auth_conf monitor "Netdata")
    location / {
        proxy_pass http://netdata:19999;
        include /etc/nginx/proxy_common.conf;
    }
}"
        log "basicauth: $user / $pass"
    else
        rm -f "$CONFIG_ROOT/config/nginx/conf.d/130-monitor.conf"; reload_nginx
    fi

    cat <<EOF

 Готово.
 Локально: http://localhost:19999 (опубликовано только на 127.0.0.1 хоста).
${access:+ }$([[ "$access" == "tunnel" ]] && echo "Извне: ssh -L 19999:localhost:19999 user@$DOMAIN -> http://localhost:19999")
$([[ "$access" == "basicauth" ]] && echo "Извне: https://$SUB")
 Дашборды: сеть (по интерфейсам), контейнеры (CPU/RAM/диск/сеть каждого), nginx, MariaDB/PostgreSQL/Valkey.
 Алерты: настраиваются в разделе Alarms; уведомления — через sendmail (см. п.16 почта root'а).
EOF
}
