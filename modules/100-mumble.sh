#!/usr/bin/env bash

install_mumble() {
    ensure_prepared
    check_dependencies
    log "=== Mumble (голосовой сервер) ==="

    [[ -f "$ENV_FILE" ]] && load_env

    local superuser_password="${MUMBLE_SUPERUSER_PASSWORD:-}"
    local server_password="${MUMBLE_SERVER_PASSWORD:-}"
    local welcome_text="${MUMBLE_WELCOMETEXT:-Welcome to Mumble server}"
    local bandwidth="${MUMBLE_BANDWIDTH:-72000}"
    local max_users="${MUMBLE_USERS:-10}"
    local protocol_choice="${MUMBLE_PROTOCOL:-1}"
    local mumble_domain="${MUMBLE_DOMAIN:-}"

    while true; do
        local proto_descr="TCP + UDP (рекомендуется)"
        local st="не установлен"
        [[ "$protocol_choice" == "2" ]] && proto_descr="только TCP"
        docker compose ps -q mumble 2>/dev/null | grep -q . && st="установлен"

        clear
        cat <<SUM

${c_mag} --- Настройки Mumble ---${c_off}   Статус: $st
  ${c_num}1.${c_off} ${c_txt}Пароль SuperUser: $([[ -n "$superuser_password" ]] && echo "******" || echo "не задан")${c_off}
  ${c_num}2.${c_off} ${c_txt}Пароль сервера: $([[ -n "$server_password" ]] && echo "******" || echo "нет")${c_off}
  ${c_num}3.${c_off} ${c_txt}Приветствие: $welcome_text${c_off}
  ${c_num}4.${c_off} ${c_txt}Битрейт: $bandwidth бит/с${c_off}
  ${c_num}5.${c_off} ${c_txt}Макс. пользователей: $max_users${c_off}
  ${c_num}6.${c_off} ${c_txt}Протокол: $proto_descr${c_off}
  ${c_num}7.${c_off} ${c_txt}Поддомен: $([[ -n "$mumble_domain" ]] && echo "$mumble_domain" || echo "не задан (используется IP)")${c_off}
  ${c_num}8.${c_off} ${c_txt}Логи${c_off}
  ${c_num}9.${c_off} ${c_txt}Установить / Применить${c_off}
  ${c_num}10.${c_off} ${c_txt}Удалить${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад (без установки)${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                if [[ -n "$superuser_password" ]] && ! ask_yn "Сменить пароль SuperUser?"; then true
                else
                    superuser_password="$(ask "Пароль SuperUser" "$(gen_pass)")"
                fi ;;
            2)
                server_password="$(ask "Пароль сервера (пусто = без пароля)" "$server_password")"
                ;;
            3) welcome_text="$(ask "Приветственное сообщение" "$welcome_text")" ;;
            4) bandwidth="$(ask "Максимальный битрейт (бит/с)" "$bandwidth")" ;;
            5) max_users="$(ask "Максимум пользователей" "$max_users")" ;;
            6)
                if [[ "$protocol_choice" == "1" ]]; then protocol_choice="2"
                else protocol_choice="1"; fi ;;
            7)
                mumble_domain="$(ask "Поддомен для Mumble (пусто = использовать IP)" "$mumble_domain")"
                update_env MUMBLE_DOMAIN "$mumble_domain"
                ;;
            8) logs_menu mumble ;;
            9) break ;;
            10) remove_mumble ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    # --- Применение настроек ---
    update_env MUMBLE_SUPERUSER_PASSWORD "$superuser_password"
    update_env MUMBLE_SERVER_PASSWORD    "$server_password"
    # Прямая запись: has_forbidden отклоняет пробелы в значениях
    if grep -q "^MUMBLE_WELCOMETEXT=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^MUMBLE_WELCOMETEXT=.*|MUMBLE_WELCOMETEXT=$welcome_text|" "$ENV_FILE"
    else
        echo "MUMBLE_WELCOMETEXT=$welcome_text" >> "$ENV_FILE"
    fi
    update_env MUMBLE_BANDWIDTH          "$bandwidth"
    update_env MUMBLE_USERS              "$max_users"
    update_env MUMBLE_PROTOCOL           "$protocol_choice"
    update_env MUMBLE_DOMAIN             "$mumble_domain"

    # Директории
    mkdir -p "$CONFIG_ROOT/data/mumble"
    mkdir -p "$CONFIG_ROOT/config/mumble"

    # Сертификаты
    if [[ -f "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" && -f "$CONFIG_ROOT/config/nginx/certs/privkey.pem" ]]; then
        cp "$CONFIG_ROOT/config/nginx/certs/fullchain.pem" "$CONFIG_ROOT/config/mumble/"
        cp "$CONFIG_ROOT/config/nginx/certs/privkey.pem"   "$CONFIG_ROOT/config/mumble/"
        chmod 644 "$CONFIG_ROOT/config/mumble/fullchain.pem"
        chmod 644 "$CONFIG_ROOT/config/mumble/privkey.pem"
        log "SSL-сертификаты скопированы для Mumble"
    else
        warn "SSL-сертификаты не найдены — Mumble будет работать без TLS"
        read -rp "Enter — продолжить " _ || true
    fi

    # UFW (всегда оба протокола)
    require_cmd ufw ufw
    log "Открываем порты в UFW..."
    if ufw allow 64738/tcp comment 'Mumble' >/dev/null 2>&1; then
        log "UFW: порт 64738/tcp открыт"
    else
        warn "Ошибка UFW: не удалось открыть 64738/tcp"
        read -rp "Enter — продолжить " _ || true
    fi
    if ufw allow 64738/udp comment 'Mumble' >/dev/null 2>&1; then
        log "UFW: порт 64738/udp открыт"
    else
        warn "Ошибка UFW: не удалось открыть 64738/udp"
        read -rp "Enter — продолжить " _ || true
    fi
    if ufw reload >/dev/null 2>&1; then
        log "UFW перезапущен"
    else
        warn "Ошибка перезапуска UFW"
        read -rp "Enter — продолжить " _ || true
    fi

    # Идемпотентная настройка UDP-порта в compose
    if [[ -f "$COMPOSE_FILE" ]]; then
        if [[ "$protocol_choice" == "2" ]]; then
            # TCP-only: закомментировать UDP-строку, если она есть и не закомментирована
            if grep -qE '^[[:space:]]*- "64738:64738/udp"[[:space:]]*$' "$COMPOSE_FILE"; then
                sed -i '/^[[:space:]]*- "64738:64738\/udp"[[:space:]]*$/s/^/# /' "$COMPOSE_FILE"
                log "UDP-порт закомментирован в compose (TCP-only)"
            fi
        else
            # TCP+UDP: раскомментировать UDP-строку, если она закомментирована
            if grep -qE '^[[:space:]]*#+[[:space:]]*- "64738:64738/udp"[[:space:]]*$' "$COMPOSE_FILE"; then
                sed -i '/^[[:space:]]*#+[[:space:]]*- "64738:64738\/udp"[[:space:]]*$/s/^[[:space:]]*#+[[:space:]]*//' "$COMPOSE_FILE"
                log "UDP-порт раскомментирован в compose (TCP+UDP)"
            fi
        fi
    fi

    # Запуск
    log "Запускаем Mumble..."
    docker compose up -d --force-recreate mumble

    log "Ожидание готовности Mumble..."
    local ready="false"
    for i in {1..15}; do
        if docker compose ps mumble | grep -q "Up"; then
            ready="true"; break
        fi
        sleep 2
    done

    if [[ "$ready" != "true" ]]; then
        warn "Mumble не запустился после 30 секунд"
        docker compose logs --tail 20 mumble
        read -rp "Enter — продолжить " _ || true
        return 1
    fi

    log "Mumble успешно запущен"

    # --- Параметры подключения ---
    local server_ip="${PUBLIC_IP:-}"
    [[ -z "$server_ip" ]] && server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$server_ip" ]] && server_ip="<IP сервера>"

    local conn_addr="${server_ip}:64738"
    local cert_hint=""
    [[ -n "$mumble_domain" ]] && conn_addr="${mumble_domain}:64738" && cert_hint=" (сертификат проверяется автоматически)"

    local -a conn_params=(
        "Адрес сервера: ${conn_addr}${cert_hint}"
        "Протокол: $([[ "$protocol_choice" == "1" ]] && echo "TCP + UDP" || echo "только TCP")"
        ""
        "Управление сервером (Mumble-клиент):"
        "  Логин: SuperUser"
        "  Пароль: $superuser_password"
        ""
        "Обычные пользователи подключаются тем же адресом,"
        "  используя созданные вами учётные записи в Mumble-клиенте."
        ""
        "Макс. пользователей: $max_users"
        "Битрейт: $bandwidth бит/с"
    )
    local -a log_params=(
        "Адрес: ${conn_addr}"
        "SuperUser: $superuser_password"
    )

    if [[ -n "$server_password" ]]; then
        conn_params+=("Пароль сервера (для входа): $server_password")
        log_params+=("Пароль сервера: $server_password")
    fi

    if [[ "$protocol_choice" == "2" ]]; then
        conn_params+=("" "⚠ Внимание: UDP выключен в compose. Голос может работать хуже.")
    fi

    conn_params+=(
        ""
        "Данные сервера: $CONFIG_ROOT/data/mumble"
        "Сертификаты:    $CONFIG_ROOT/config/mumble"
    )

    show_connection_info "Mumble" "${conn_params[@]}"
    log_connection_params "Mumble" "${log_params[@]}"
}

remove_mumble() {
    log "=== Удаление Mumble ==="
    docker compose -f "$COMPOSE_FILE" stop mumble 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" rm -f mumble 2>/dev/null || true

    require_cmd ufw ufw
    if ufw delete allow 64738/tcp >/dev/null 2>&1; then
        log "UFW: 64738/tcp закрыт"
    else
        warn "Не удалось удалить правило 64738/tcp из UFW (возможно, уже отсутствует)"
    fi
    if ufw delete allow 64738/udp >/dev/null 2>&1; then
        log "UFW: 64738/udp закрыт"
    else
        warn "Не удалось удалить правило 64738/udp из UFW (возможно, уже отсутствует)"
    fi
    ufw reload >/dev/null 2>&1 || true

    log "Mumble остановлен. Данные в $CONFIG_ROOT/data/mumble сохранены."
    read -rp "Enter — продолжить " _ || true
}
