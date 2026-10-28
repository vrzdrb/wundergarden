#!/usr/bin/env bash

install_mumble() {
    ensure_prepared
    check_dependencies
    log "=== Mumble (голосовой сервер) ==="
    
    # Загружаем .env если есть
    [[ -f "$ENV_FILE" ]] && load_env
    
    # Запрашиваем настройки
    local superuser_password="${MUMBLE_SUPERUSER_PASSWORD:-}"
    if [[ -z "$superuser_password" ]]; then
        superuser_password=$(ask "Пароль суперпользователя (SuperUser)" "$(gen_pass)")
        update_env MUMBLE_SUPERUSER_PASSWORD "$superuser_password"
    fi
    
    local server_password="${MUMBLE_SERVER_PASSWORD:-}"
    server_password=$(ask "Пароль сервера (пусто = без пароля)" "$server_password")
    update_env MUMBLE_SERVER_PASSWORD "$server_password"
    
    local welcome_text="${MUMBLE_WELCOMETEXT:-Welcome to Mumble server}"
    welcome_text=$(ask "Приветственное сообщение" "$welcome_text")
    update_env MUMBLE_WELCOMETEXT "$welcome_text"
    
    local bandwidth="${MUMBLE_BANDWIDTH:-72000}"
    bandwidth=$(ask "Максимальный битрейт (бит/с)" "$bandwidth")
    update_env MUMBLE_BANDWIDTH "$bandwidth"
    
    local max_users="${MUMBLE_USERS:-10}"
    max_users=$(ask "Максимум пользователей" "$max_users")
    update_env MUMBLE_USERS "$max_users"
    
    # Выбор протокола
    echo ""
    echo "${c_txt}Выберите режим работы:${c_off}"
    echo "${c_txt}  1. TCP + UDP (рекомендуется для голосовой связи)${c_off}"
    echo "${c_txt}  2. Только TCP (если UDP порт занят другим сервисом)${c_off}"
    local protocol_choice=$(ask "Ваш выбор (1/2)" "1")
    
    update_env MUMBLE_PROTOCOL "$protocol_choice"
    
    # Открываем порты в UFW
    require_cmd ufw ufw
    log "Открываем порты в UFW..."
    ufw allow 64738/tcp comment 'Mumble' >/dev/null 2>&1 && log "UFW: порт 64738/tcp открыт" || warn "Ошибка UFW"
    
    if [[ "$protocol_choice" == "1" ]]; then
        ufw allow 64738/udp comment 'Mumble' >/dev/null 2>&1 && log "UFW: порт 64738/udp открыт" || warn "Ошибка UFW"
    fi
    
    ufw reload >/dev/null 2>&1 && log "UFW перезапущен" || warn "Ошибка перезапуска UFW"
    
    # Создаём директорию для данных и сертификатов
    mkdir -p "$CONFIG_ROOT/data/mumble"
    mkdir -p "$CONFIG_ROOT/config/mumble"
    
    # Копируем сертификаты для Mumble (если они есть)
    if [[ -f "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" && -f "$CONFIG_ROOT/config/nginx/certs/privkey.pem" ]]; then
        cp "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" "$CONFIG_ROOT/config/mumble/"
        cp "$CONFIG_ROOT/config/nginx/certs/privkey.pem" "$CONFIG_ROOT/config/mumble/"
        chmod 644 "$CONFIG_ROOT/config/mumble/fullchain.pem"
        chmod 600 "$CONFIG_ROOT/config/mumble/privkey.pem"
        log "SSL-сертификаты скопированы для Mumble"
    else
        warn "SSL-сертификаты не найдены — Mumble будет работать без TLS или с самоподписанным сертификатом"
    fi
    
    # Запускаем Mumble через docker compose
    log "Запускаем Mumble через docker compose..."
    docker compose up -d mumble
    
    sleep 3
    
    # Проверяем, что контейнер запущен
    if docker compose ps mumble | grep -q "Up"; then
        log "Mumble успешно запущен"
        
        # Формируем параметры подключения
        local -a conn_params=(
            "Адрес: ${PUBLIC_IP:-<ваш-IP>}:64738"
            "Протокол: $([ "$protocol_choice" == "1" ] && echo "TCP + UDP" || echo "TCP only")"
            "Логин: SuperUser"
            "Пароль: $superuser_password"
            "Максимум пользователей: $max_users"
        )
        local -a log_params=(
            "Адрес: ${PUBLIC_IP:-<ваш-IP>}:64738"
            "Логин: SuperUser"
            "Пароль: $superuser_password"
        )
        
        if [[ -n "$server_password" ]]; then
            conn_params+=("Пароль сервера: $server_password")
            log_params+=("Пароль сервера: $server_password")
        fi
        
        if [[ "$protocol_choice" == "2" ]]; then
            conn_params+=("" "⚠ Внимание: Mumble работает только по TCP. Голосовая связь может работать хуже.")
        fi
        
        # Вывод параметров подключения
        show_connection_info "Mumble" "${conn_params[@]}"
        
        # Сохранение параметров в файл
        log_connection_params "Mumble" "${log_params[@]}"
    else
        warn "Mumble не запустился. Проверьте логи: docker compose logs mumble"
    fi
}
