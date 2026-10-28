#!/usr/bin/env bash

install_matrix() {
    ensure_prepared
    check_dependencies
    log "=== Matrix (continuwuity) + TURN/STUN (coturn) ==="
    SUB_MATRIX="$(ask "Поддомен для Matrix" "${SUB_MATRIX:-matrix.$DOMAIN}")"; update_env SUB_MATRIX "$SUB_MATRIX"
    SUB_TURN="$(ask "Поддомен для TURN/STUN" "${SUB_TURN:-turn.$DOMAIN}")"; update_env SUB_TURN "$SUB_TURN"
    dns_hint "$SUB_MATRIX"; dns_hint "$SUB_TURN"

    local pub_ip=""
    while [[ -z "$pub_ip" ]]; do
        local detected
        detected="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
        pub_ip="$(ask "Ваш публичный статический IP (coturn рекламирует его клиентам)" "${detected:-$PUBLIC_IP}")"
        [[ -z "$pub_ip" ]] && warn "IP обязателен — без него coturn будет рекламировать клиентам неверный адрес."
    done
    update_env PUBLIC_IP "$pub_ip"

    # Открываем порты Coturn в UFW
    require_cmd ufw ufw
    ufw allow 3478/tcp comment 'Coturn STUN/TURN' >/dev/null 2>&1 && log "UFW: порт 3478/tcp открыт" || warn "Ошибка UFW"
    ufw allow 3478/udp comment 'Coturn STUN/TURN' >/dev/null 2>&1 && log "UFW: порт 3478/udp открыт" || warn "Ошибка UFW"
    ufw allow 5349/tcp comment 'Coturn TURNS' >/dev/null 2>&1 && log "UFW: порт 5349/tcp открыт" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1 || true

    local desc="" reg_mode="closed" reg_token="${REGISTRATION_TOKEN:-}" suspend_new="false" \
          e2ee="true" suffix_mode="flag" suffix_custom="" block_invites="false" \
          auto_join="" ann="false" cache_mode="default" fed="false" online_backup="true" \
          coturn_protocol="udp+tcp"

    while true; do
        local reg_descr="закрыта" suffix_descr="флаг 🏳️‍⚧️ (по умолчанию)" cache_descr="по умолчанию"
        [[ "$reg_mode" == "token" ]] && reg_descr="по токену"
        [[ "$reg_mode" == "open" ]] && reg_descr="открыта (любой!)"
        [[ "$suffix_mode" == "none" ]] && suffix_descr="без суффикса"
        [[ "$suffix_mode" == "custom" ]] && suffix_descr="\"$suffix_custom\""
        [[ "$cache_mode" == "low" ]] && cache_descr="экономный (×0.5)"
        [[ "$cache_mode" == "high" ]] && cache_descr="увеличенный (×2.0)"
        clear
        cat <<SUM

${c_mag} --- Настройки continuwuity ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Описание сервера: ${desc:-—}${c_off}
  ${c_num}2.${c_off} ${c_txt}Регистрация: $reg_descr${reg_token:+}${suspend_new:+; новые — заморожены до одобрения}${c_off}
  ${c_num}3.${c_off} ${c_txt}Сквозное шифрование: $(onoff "$e2ee")${c_off}
  ${c_num}4.${c_off} ${c_txt}Суффикс имени новых юзеров: $suffix_descr${c_off}
  ${c_num}5.${c_off} ${c_txt}Блокировать приглашения не-админам: $(onoff "$block_invites")${c_off}
  ${c_num}6.${c_off} ${c_txt}Автовступление новых юзеров в комнаты: ${auto_join:-—}${c_off}
  ${c_num}7.${c_off} ${c_txt}Проверка анонсов: $${c_off}
  ${c_num}8.${c_off} ${c_txt}Профиль кэша БД: $cache_descr${c_off}
  ${c_num}9.${c_off} ${c_txt}Федерация с другими серверами: $(onoff "$fed")${c_off}
 ${c_num}10.${c_off} ${c_txt}Онлайн-бэкапы базы: $(onoff "$online_backup")${c_off}
 ${c_num}11.${c_off} ${c_txt}TURN/STUN протокол: $coturn_protocol${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) desc="$(ask "Описание (видно в клиентах; пусто — без описания)" "$desc")" ;;
            2)
                echo "${c_txt} 1) закрыта — только вы сами (первый юзер — админ)${c_off}"
                echo "${c_txt} 2) по токену — друзья регистрируются по секретному токену${c_off}"
                echo "${c_txt} 3) открыта — любой, кто найдёт сервер${c_off}"
                reg_mode="$(ask "1/2/3" "$([[ -n "$reg_token" ]] && echo 2 || echo 1)")"
                case "$reg_mode" in
                    2) reg_mode="token"
                       [[ -z "$reg_token" ]] && reg_token="$(gen_pass)"
                       update_env REGISTRATION_TOKEN "$reg_token"
                       log "Токен регистрации: $reg_token (хранится в .env: REGISTRATION_TOKEN)"
                       ask_yn "Замораживать новых юзеров до одобрения админом (suspend_on_register)?" && suspend_new="true" || suspend_new="false" ;;
                    3) reg_mode="open"; warn "открытая регистрация — ваш сервер рано или поздно найдут спамеры." ;;
                    *) reg_mode="closed"; reg_token=""; update_env REGISTRATION_TOKEN "" ;;
                esac ;;
            3)
                echo "${c_txt}E2EE — сквозное шифрование комнат (ключи только у участников).${c_off}"
                echo "${c_txt}Выкл.: сервер видит всё, но упрощает поиск/бэкапы. Обычно оставляют вкл.${c_off}"
                ask_yn "Оставить E2EE включённым?" && e2ee="true" || e2ee="false" ;;
            4)
                echo "${c_txt} 1) флаг 🏳️‍⚧️ (дефолт continuwuity)  2) без суффикса  3) свой текст${c_off}"
                local sc; sc="$(ask "1/2/3" "1")"
                case "$sc" in
                    2) suffix_mode="none" ;;
                    3) suffix_mode="custom"; suffix_custom="$(ask "Текст суффикса" "")" ;;
                    *) suffix_mode="flag" ;;
                esac ;;
            5) [[ "$block_invites" == "true" ]] && block_invites="false" || block_invites="true" ;;
            6) auto_join="$(ask "Алиасы комнат через запятую (#общая:$SUB_MATRIX, ...); пусто — выкл" "$auto_join")" ;;
            7) [[ "$ann" == "true" ]] && ann="false" || ann="true" ;;
            8)
                echo "${c_txt} 1) по умолчанию  2) экономный (×0.5 — мало RAM)  3) увеличенный (×2.0 — запас памяти)${c_off}"
                cache_mode="$(ask "1/2/3" "1")"; [[ "$cache_mode" == "1" ]] && cache_mode="default" ;;
            9)
                echo "${c_txt}Федерация: общение с юзерами других серверов. Требует: .well-known,${c_off}"
                echo "${c_txt}порт 8448 (или 443), постоянную модерацию. Для сервера на двоих — не нужна.${c_off}"
                ask_yn "Включить федерацию?" && fed="true" || fed="false" ;;
            10) [[ "$online_backup" == "true" ]] && online_backup="false" || online_backup="true" ;;
            11)
                echo "${c_txt}Протокол TURN/STUN:${c_off}"
                echo "${c_txt}  1) UDP + TCP (рекомендуется — максимальная совместимость)${c_off}"
                echo "${c_txt}  2) Только TCP (если UDP заблокирован или занят)${c_off}"
                local proto_choice; proto_choice="$(ask "1/2" "1")"
                case "$proto_choice" in
                    2) coturn_protocol="tcp" ;;
                    *) coturn_protocol="udp+tcp" ;;
                esac
                ;;
            12) logs_menu matrix coturn  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    for f in "$CONFIG_ROOT/config/matrix/continuwuity.toml" "$DATA_DIR/coturn/turnserver.conf"; do
        [[ -d "$f" ]] && { warn "убираю директорию-заглушку $f"; rm -rf "$f"; }
    done
    mkdir -p "$DATA_DIR/matrix" "$DATA_DIR/matrix-backups" "$DATA_DIR/coturn" "$CONFIG_ROOT/config/matrix"

    local suffix_value='"🏳️‍⚧️"'
    [[ "$suffix_mode" == "none" ]] && suffix_value='""'
    [[ "$suffix_mode" == "custom" ]] && suffix_value="\"$suffix_custom\""
    local cache_line="" autojoin_block="" desc_line="" regtoken_line="" backup_block=""
    [[ "$cache_mode" == "low" ]] && cache_line="cache_capacity_modifier = 0.5"
    [[ "$cache_mode" == "high" ]] && cache_line="cache_capacity_modifier = 2.0"
    [[ -n "$auto_join" ]] && {
        autojoin_block="auto_join_rooms = ["
        local a; IFS=','; for a in $auto_join; do a="$(echo "$a" | xargs)"; [[ -n "$a" ]] && autojoin_block+=" \"$a\","; done; unset IFS
        autojoin_block="${autojoin_block%,} ]"
    }
    [[ -n "$desc" ]] && desc_line="server_description = \"$desc\""
    [[ "$reg_mode" == "token" && -n "$reg_token" ]] && regtoken_line="registration_token = \"$reg_token\""
    [[ "$online_backup" == "true" ]] && backup_block=$'database_backup_path = "/backup"\ndatabase_backups_to_keep = 3'

    cat > "$CONFIG_ROOT/config/matrix/continuwuity.toml" <<EOF
[global]
server_name = "$SUB_MATRIX"
database_path = "/var/lib/continuwuity"
address = ["0.0.0.0"]
port = 8008
allow_registration = $([[ "$reg_mode" != "closed" ]] && echo true || echo false)
$regtoken_line
suspend_on_register = $suspend_new
allow_federation = $fed
allow_encryption = $e2ee
new_user_displayname_suffix = $suffix_value
block_non_admin_invites = $block_invites
allow_announcements_check = $ann
$cache_line
$autojoin_block
$backup_block
$desc_line

# Генерируем turn_uris в зависимости от выбранного протокола
    local turn_uris_line=""
    if [[ "$coturn_protocol" == "tcp" ]]; then
        turn_uris_line="turn_uris = [\"turn:$SUB_TURN:3478?transport=tcp\"]"
    else
        turn_uris_line="turn_uris = [\"turn:$SUB_TURN:3478?transport=udp\", \"turn:$SUB_TURN:3478?transport=tcp\"]"
    fi
    
    echo "$turn_uris_line" >> "$CONFIG_ROOT/config/matrix/continuwuity.toml"
    cat >> "$CONFIG_ROOT/config/matrix/continuwuity.toml" <<EOF
turn_secret = "$TURN_PASSWORD"
turn_ttl = 86400
EOF

    cat > "$DATA_DIR/coturn/turnserver.conf" <<EOF
listening-port=3478
realm=$SUB_TURN
fingerprint
use-auth-secret
static-auth-secret=$TURN_PASSWORD
min-port=49152
max-port=65535
external-ip=$pub_ip
log-file=stdout
EOF
    
    # Если выбран только TCP, добавляем no-udp
    if [[ "$coturn_protocol" == "tcp" ]]; then
        echo "no-udp" >> "$DATA_DIR/coturn/turnserver.conf"
    fi
    
    cat >> "$DATA_DIR/coturn/turnserver.conf" <<EOF
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=::1
denied-peer-ip=::
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
EOF

    docker compose up -d matrix coturn
    sleep 5
    add_site 50-matrix "server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    server_name $SUB_MATRIX;
    ssl_certificate     $CONFIG_ROOT/config/nginx/certs/fullchain.pem;
    ssl_certificate_key $CONFIG_ROOT/config/nginx/certs/privkey.pem;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:8008;
        include $CONFIG_ROOT/config/nginx/proxy_common.conf;
    }
}"
    
    # Вывод параметров подключения
    show_connection_info "Matrix (continuwuity)" \
        "URL сервера: https://$SUB_MATRIX" \
        "Регистрация: $reg_descr" \
        "" \
        "Получение первого пользователя (станет админом):" \
        "  docker compose logs matrix | grep -i token" \
        "  -> токен -> регистрация в клиенте" \
        "  Либо: docker compose exec matrix continuwuity --execute \"users create_user <имя>\"" \
        "" \
        "TURN/STUN: turn:$SUB_TURN:3478 ($coturn_protocol)" \
        "Порты 3478 и 5349 открыты в UFW (tcp+udp)"
    
    # Сохранение параметров в файл
    log_connection_params "Matrix" \
        "URL: https://$SUB_MATRIX" \
        "Регистрация: $reg_descr" \
        "TURN: turn:$SUB_TURN:3478 ($coturn_protocol)"
}
