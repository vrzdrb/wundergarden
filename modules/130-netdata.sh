#!/usr/bin/env bash

install_netdata() {
    ensure_prepared
    check_dependencies
    log "=== Netdata (мониторинг) ==="
    
    local domain="${SUB_NETDATA:-monitor.$DOMAIN}"
    domain=$(ask "Домен для Netdata" "$domain")
    update_env SUB_NETDATA "$domain"
    
    docker compose up -d netdata socket-proxy
    sleep 3
    
    add_site 004-netdata "server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    server_name $domain;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:19999;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
        include $CONFIG_ROOT/config/nginx/ws_common.conf;
    }
}"
    
    # Вывод параметров подключения
    show_connection_info "Netdata" \
        "URL: https://$domain" \
        "" \
        "Мониторинг системы в реальном времени" \
        "Метрики: CPU, RAM, диск, сеть, Docker-контейнеры"
    
    # Сохранение параметров в файл
    log_connection_params "Netdata" \
        "URL: https://$domain"
}
