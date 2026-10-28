#!/usr/bin/env bash

# Цветовые переменные (на случай, если не загружены из основного скрипта)
c_txt=${c_txt:-$'\033[96m'}
c_off=${c_off:-$'\033[0m'}

install_mumble() {
    ensure_prepared
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
    
    local port_flags=""
    local protocol_desc=""
    
    case "$protocol_choice" in
        2)
            port_flags="-p 64738:64738/tcp"
            protocol_desc="TCP only"
            ;;
        *)
            port_flags="-p 64738:64738/tcp -p 64738:64738/udp"
            protocol_desc="TCP + UDP"
            ;;
    esac
    
    update_env MUMBLE_PROTOCOL "$protocol_choice"
    
    # Открываем порты в UFW
    require_cmd ufw ufw
    log "Открываем порты в UFW..."
    ufw allow 64738/tcp comment 'Mumble' >/dev/null 2>&1 && log "UFW: порт 64738/tcp открыт" || warn "Ошибка UFW"
    
    if [[ "$protocol_choice" == "1" ]]; then
        ufw allow 64738/udp comment 'Mumble' >/dev/null 2>&1 && log "UFW: порт 64738/udp открыт" || warn "Ошибка UFW"
    fi
    
    ufw reload >/dev/null 2>&1 && log "UFW перезапущен" || warn "Ошибка перезапуска UFW"
    
    # Создаём директорию для данных
    mkdir -p "$CONFIG_ROOT/data/mumble"
    
    # Удаляем старый контейнер если есть
    if docker ps -a | grep -q "^.*mumble$"; then
        log "Удаляем старый контейнер mumble..."
        docker rm -f mumble >/dev/null 2>&1 || true
    fi
    
    # Запускаем контейнер Mumble напрямую на портах 64738
    log "Запускаем Mumble в режиме $protocol_desc..."
    docker run -d \
        --name mumble \
        --restart unless-stopped \
        $port_flags \
        -e MUMBLE_SUPERUSER_PASSWORD="$superuser_password" \
        -e MUMBLE_CONFIG_serverpassword="$server_password" \
        -e MUMBLE_CONFIG_welcometext="$welcome_text" \
        -e MUMBLE_CONFIG_bandwidth="$bandwidth" \
        -e MUMBLE_CONFIG_users="$max_users" \
        -e MUMBLE_CONFIG_suggestpushtotalk=true \
        -e MUMBLE_CONFIG_opusthreshold=0 \
        -e MUMBLE_CONFIG_autobanAttempts=10 \
        -v "$CONFIG_ROOT/data/mumble:/data" \
        mumblevoip/mumble-server:latest
    
    sleep 2
    
    # Проверяем, что контейнер запущен
    if docker ps | grep -q mumble; then
        log "Mumble успешно запущен"
        echo ""
        echo "${c_txt}Настройки Mumble:${c_off}"
        echo "${c_txt}  Протокол: $protocol_desc${c_off}"
        echo "${c_txt}  Порт: 64738${c_off}"
        echo "${c_txt}  Пароль суперпользователя: $superuser_password${c_off}"
        if [[ -n "$server_password" ]]; then
            echo "${c_txt}  Пароль сервера: $server_password${c_off}"
        fi
        echo "${c_txt}  Максимум пользователей: $max_users${c_off}"
        echo ""
        echo "${c_txt}Подключение:${c_off}"
        echo "${c_txt}  Адрес: <ваш-IP>:64738${c_off}"
        echo "${c_txt}  Логин: SuperUser${c_off}"
        echo "${c_txt}  Пароль: $superuser_password${c_off}"
        
        if [[ "$protocol_choice" == "2" ]]; then
            echo ""
            echo "${c_txt}⚠ Внимание: Mumble работает только по TCP.${c_off}"
            echo "${c_txt}  Голосовая связь может работать хуже, чем по UDP.${c_off}"
        fi
    else
        warn "Mumble не запустился. Проверьте логи: docker logs mumble"
    fi
    
    read -rp "Enter — продолжить " _ || true
}
