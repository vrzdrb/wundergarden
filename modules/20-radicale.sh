#!/usr/bin/env bash

install_radicale() {
    ensure_prepared
    log "=== Radicale (CalDAV) ==="
    local auth_type="htpasswd" rights="owner_only" level="INFO" ruser="" rpass=""

    SUB_CAL="$(ask "Поддомен для CalDAV" "${SUB_CAL:-cal.$DOMAIN}")"
    update_env SUB_CAL "$SUB_CAL"; dns_hint "$SUB_CAL"

    while true; do
        clear
        clear
        cat <<SUM

${c_mag} --- Настройки Radicale ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB_CAL${c_off}
  ${c_num}2.${c_off} ${c_txt}Авторизация: ${auth_type/htpasswd/логин и пароль}${auth_type/none/БЕЗ пароля}${c_off}
  ${c_num}3.${c_off} ${c_txt}Пользователь: ${ruser:-—}${c_off}
  ${c_num}4.${c_off} ${c_txt}Права: $rights${c_off}
  ${c_num}5.${c_off} ${c_txt}Логирование: $level${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                SUB_CAL="$(ask "Поддомен" "$SUB_CAL")"
                update_env SUB_CAL "$SUB_CAL"; dns_hint "$SUB_CAL" ;;
            2)
                echo "${c_txt} 1) htpasswd — логин/пароль (рекомендуется)${c_off}"
                echo "${c_txt} 2) none — без авторизации (только в паре с basicauth в nginx; сам скрипт его не ставит!)${c_off}"
                case "$(ask "1/2" "1")" in
                    2) auth_type="none"; warn "тип 'none' небезопасен без доп. basicauth — вы уверены, что хотите открытый доступ?" ;;
                    *) auth_type="htpasswd" ;;
                esac ;;
            3)
                local u p hash f
                u="$(ask "Логин пользователя CalDAV" "user")"
                p="$(ask "Пароль (Enter — сгенерировать)" "$(gen_pass)")"
                hash="$(openssl passwd -apr1 "$p")"
                f="$CONFIG_ROOT/config/radicale/users"
                mkdir -p "$(dirname "$f")"; touch "$f"; chmod 600 "$f"
                grep -v "^$u:" "$f" > "$f.tmp" || true; mv "$f.tmp" "$f"
                echo "$u:$hash" >> "$f"
                ruser="$u"; rpass="$p"
                log "Пользователь '$u' записан в config/radicale/users (apr1/md5). Пароль: $p"
                warn "добавить ещё пользователей позже: openssl passwd -apr1 >> config/radicale/users" ;;
            4)
                echo "${c_txt} owner_only — каждый видит только свои календари (рекомендуется)${c_off}"
                echo "${c_txt} authenticated — любой залогиненный видит всё${c_off}"
                rights="$(ask "owner_only / authenticated" "$rights")" ;;
            5) level="$(ask "INFO / DEBUG / WARNING" "$level")" ;;
            6) logs_menu radicale  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    [[ "$auth_type" == "htpasswd" && -z "$ruser" ]] && \
        warn "пользователь не создан (пункт 3) — htpasswd-файл пуст, вход не сработает."

    mkdir -p "$CONFIG_ROOT/config/radicale" "$DATA_DIR/radicale"
    cat > "$CONFIG_ROOT/config/radicale/config" <<EOF
[auth]
type = $auth_type
delay = 1
htpasswd_filename = /etc/radicale/users
htpasswd_encryption = md5

[rights]
type = $rights

[storage]
filesystem_folder = /data

[logging]
level = $level
mask_passwords = true
EOF
    chmod 600 "$CONFIG_ROOT/config/radicale/config" 2>/dev/null || true
    chown -R 1000:1000 "$CONFIG_ROOT/config/radicale" "$DATA_DIR/radicale" 2>/dev/null || true

    docker compose up -d radicale
    add_site 20-cal "server {
    listen 8443 ssl;
    server_name $SUB_CAL;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    client_max_body_size 50m;
    location / {
        proxy_pass http://radicale:5232;
        include /etc/nginx/proxy_common.conf;
    }
}"
    local code=""
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 ${ruser:+-u "$ruser:$rpass"} "https://$SUB_CAL/" 2>/dev/null || true)
    [[ -n "$code" && "$code" != "000" ]] && log "Проверка по https://$SUB_CAL/ — HTTP $code" \
        || warn "Проверка не прошла (DNS/сертификат ещё не готовы?) — проверьте позже: curl -u $ruser https://$SUB_CAL/"
    cat <<EOF

 Готово: https://$SUB_CAL
 Fossify Calendar: DAV-аккаунт -> URL https://$SUB_CAL/$ruser/
 calcurse: ~/.config/calcurse/caldav/config -> https://$SUB_CAL, путь /$ruser/<id>.ics
 Веб-интерфейс Radicale: https://$SUB_CAL
EOF
}
