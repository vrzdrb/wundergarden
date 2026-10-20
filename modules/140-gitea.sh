#!/usr/bin/env bash
# modules/140-gitea.sh — сервис: Gitea (свой Git-хостинг за нашим nginx)
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_gitea() {
    ensure_prepared
    log "=== Gitea (Git-хостинг за nginx) ==="
    local SUB="${SUB_GITEA:-git.$DOMAIN}" g_user="" g_email="" g_pass=""
    [[ -z "${GITEA_DB_PASSWORD:-}" ]] && GITEA_DB_PASSWORD="$(gen_pass)" && update_env GITEA_DB_PASSWORD "$GITEA_DB_PASSWORD"
    dns_hint "$SUB"

    while true; do
        cat <<SUM

 --- Настройки Gitea ---
  1. Поддомен: https://$SUB
  2. Харденинг (включён всегда): регистрация закрыта, REQUIRE_SIGNIN_VIEW, INSTALL_LOCK,
     SSH выключен, LFS выключен, OpenID выключен, организации приватные
  3. Git push/pull без лимитов (nginx client_max_body_size = 0)
  4. Первый админ (создаётся через CLI при установке; регистрация закрыта)

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_GITEA "$SUB"; dns_hint "$SUB" ;;
            2) log "Фиксировано по good practice (см. gitea-autodeploy.sh + наши доработки)." ;;
            3) log "Фиксировано: большие push'и не режутся." ;;
            4)
                g_user="$(ask "Логин первого админа" "admin")"
                [[ "$g_user" =~ ^[a-zA-Z0-9_-]+$ ]] || { warn "логин: буквы/цифры/_/-"; g_user=""; continue; }
                g_email="$(ask "Email админа" "admin@$DOMAIN")"
                [[ "$g_email" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || { warn "нужен email"; g_email=""; continue; }
                g_pass="$(ask "Пароль админа (Enter — сгенерировать)" "$(gen_pass)")"
                log "Реквизиты админа заданы (применятся при установке)." ;;
            L|l|Д|д) logs_menu gitea gitea-db ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_GITEA "$SUB"

    mkdir -p "$DATA_DIR/gitea" "$DATA_DIR/gitea-db"
    chown -R 1000:1000 "$DATA_DIR/gitea" 2>/dev/null || true

    docker compose up -d gitea-db
    wait_container gitea-db pg_isready -U gitea -d gitea
    docker compose up -d gitea
    log "Жду Gitea..."
    local tries=0
    until docker compose exec -T gitea wget -qO- http://localhost:3000/ >/dev/null 2>&1 || [[ $tries -ge 30 ]]; do
        sleep 2; tries=$((tries + 1))
    done

    # INSTALL_LOCK + DISABLE_REGISTRATION => единственный путь — CLI
    if docker compose exec -T gitea gitea admin user list 2>/dev/null | grep -q .; then
        log "Пользователи уже есть — создание админа пропущено."
    else
        [[ -z "$g_user" ]] && g_user="$(ask "Логин первого админа" "admin")"
        [[ -z "$g_email" ]] && g_email="$(ask "Email админа" "admin@$DOMAIN")"
        [[ -z "$g_pass" ]] && g_pass="$(ask "Пароль админа (Enter — сгенерировать)" "$(gen_pass)")"
        docker compose exec -T gitea gitea admin user create --admin \
            --username "$g_user" --password "$g_pass" --email "$g_email" --must-change-password=false \
            && log "Админ '$g_user' создан. Пароль: $g_pass (сохраните — больше не покажется)" \
            || warn "не удалось создать админа: docker compose logs gitea"
    fi

    add_site 140-gitea "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 0;
    location / {
        proxy_pass http://gitea:3000;
        include /etc/nginx/proxy_common.conf;
        proxy_read_timeout 3600s;
    }
}"

    cat <<EOF

 Готово: https://$SUB
 Админ создан через CLI (регистрация закрыта, INSTALL_LOCK — страница установки закрыта).
 Данные: data/gitea + data/gitea-db (в бэкапе).
 Брутфорс логина: у Gitea встроенный rate-limit; при желании добавим jail по логам nginx.
EOF
}
