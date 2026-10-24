#!/usr/bin/env bash

install_mumble() {
    ensure_prepared
    log "=== Mumble (Murmur) — голосовой сервер ==="
    local server_pw="${MUMBLE_SERVER_PASSWORD:-}" su_pw="${MUMBLE_SUPERUSER_PASSWORD:-$(gen_pass)}" \
          welcome="${MUMBLE_WELCOMETEXT:-Добро пожаловать на сервер}" \
          bw="${MUMBLE_BANDWIDTH:-72000}" users="${MUMBLE_USERS:-10}" \
          ptt="${MUMBLE_SUGGEST_PTT:-true}" img="${MUMBLE_IMAGE:-mumblevoip/mumble-server:latest}" \
          tls_mode="${MUMBLE_TLS_MODE:-acme}"

    while true; do
        local pw_descr="нет (вход по сертификату/паролю SuperUser)" ptt_descr="вкл" tls_descr="acme.sh (config/nginx/certs)"
        [[ -n "$server_pw" ]] && pw_descr="задан"
        [[ "$ptt" == "false" ]] && ptt_descr="выкл"
        case "$tls_mode" in
            le) tls_descr="certbot/acme.sh (/etc/letsencrypt)" ;;
            manual) tls_descr="свой путь" ;;
            auto) tls_descr="АВАРИЙНЫЙ self-signed" ;;
        esac
        clear
        cat <<SUM

${c_mag} --- Настройки Mumble ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Пароль сервера: $pw_descr${c_off}
  ${c_num}2.${c_off} ${c_txt}SuperUser-пароль: задан${c_off}
  ${c_num}3.${c_off} ${c_txt}Приветствие: $welcome${c_off}
  ${c_num}4.${c_off} ${c_txt}Битрейт на пользователя: $bw бит/с${c_off}
  ${c_num}5.${c_off} ${c_txt}Лимит пользователей: $users${c_off}
  ${c_num}6.${c_off} ${c_txt}Подсказка Push-to-Talk: $ptt_descr${c_off}
  ${c_num}7.${c_off} ${c_txt}Образ: $img${c_off}
  ${c_num}8.${c_off} ${c_txt}TLS-сертификат: $tls_descr${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) server_pw="$(ask "Пароль входа на сервер (пусто — без пароля)" "$server_pw")" ;;
            2) su_pw="$(gen_pass)"; log "Новый SuperUser-пароль: $su_pw" ;;
            3) welcome="$(ask "Приветствие (без кавычек)" "$welcome")" ;;
            4)
                echo "${c_txt} 72000 — отличное качество, до ~50 юзеров (вам хватит с запасом)${c_off}"
                echo "${c_txt} 54000 — чуть ниже качество, 50+ юзеров | 36000 — экономия канала${c_off}"
                local bw_new; bw_new="$(ask "Битрейт (число)" "$bw")"
                [[ "$bw_new" =~ ^[0-9]+$ ]] && bw="$bw_new" || warn "нужно число — оставляю $bw" ;;
            5)
                local us_new; us_new="$(ask "Макс. одновременных пользователей (число)" "$users")"
                [[ "$us_new" =~ ^[0-9]+$ ]] && users="$us_new" || warn "нужно число — оставляю $users" ;;
            6) [[ "$ptt" == "true" ]] && ptt="false" || ptt="true" ;;
            7) img="$(ask "Образ (latest / latest-acme для ACME-сертификатов)" "$img")" ;;
            8)
                echo "${c_txt}Mumble терминирует TLS сам (контейнер публикует 64738 напрямую). Источник сертификата:${c_off}"
                echo "${c_txt} 1) acme.sh — wildcard из config/nginx/certs (пункт 13), рекомендуется${c_off}"
                echo "${c_txt} 2) /etc/letsencrypt — certbot/другой acme-клиент${c_off}"
                echo "${c_txt} 3) указать пути к fullchain.pem/privkey.pem вручную${c_off}"
                echo "${c_txt} 4) аварийный self-signed (НЕ рекомендуется — клиенты увидят предупреждение)${c_off}"
                case "$(ask "1-4" "1")" in
                    2) tls_mode="le" ;; 3) tls_mode="manual" ;; 4) tls_mode="auto" ;; *) tls_mode="acme" ;;
                esac ;;
            9) logs_menu mumble  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    update_env MUMBLE_SERVER_PASSWORD "$server_pw"
    update_env MUMBLE_SUPERUSER_PASSWORD "$su_pw"
    update_env MUMBLE_WELCOMETEXT "$welcome"
    update_env MUMBLE_BANDWIDTH "$bw"; update_env MUMBLE_USERS "$users"
    update_env MUMBLE_SUGGEST_PTT "$ptt"; update_env MUMBLE_IMAGE "$img"
    update_env MUMBLE_TLS_MODE "$tls_mode"

    mkdir -p "$CONFIG_ROOT/config/mumble"
    if [[ "$tls_mode" == "acme" ]]; then
        local cdir="$CONFIG_ROOT/config/nginx/certs"
        [[ -f "$cdir/fullchain.pem" && -f "$cdir/privkey.pem" ]] \
            || die "сертификаты не найдены в $cdir — сначала выполните пункт 3 (acme.sh), либо выберите другой источник."
        cp "$cdir/fullchain.pem" "$CONFIG_ROOT/config/mumble/fullchain.pem"
        cp "$cdir/privkey.pem" "$CONFIG_ROOT/config/mumble/privkey.pem"
        log "Подключён wildcard-сертификат из $cdir"
    elif [[ "$tls_mode" == "le" ]]; then
        local cert_dir found
        found=$(find /etc/letsencrypt/live -maxdepth 2 -name fullchain.pem 2>/dev/null | sed 's|/fullchain\.pem$||' || true)
        [[ -n "$found" ]] || die "в /etc/letsencrypt/live ничего не найдено — выберите другой источник"
        echo "Найдены сертификаты:"; echo "$found"
        cert_dir="$(ask "Каталог сертификата" "$(echo "$found" | head -1)")"
        [[ -f "$cert_dir/fullchain.pem" && -f "$cert_dir/privkey.pem" ]] || die "в $cert_dir не найдены fullchain.pem и privkey.pem"
        cp "$cert_dir/fullchain.pem" "$CONFIG_ROOT/config/mumble/fullchain.pem"
        cp "$cert_dir/privkey.pem" "$CONFIG_ROOT/config/mumble/privkey.pem"
        log "Подключён сертификат: $cert_dir"
    elif [[ "$tls_mode" == "manual" ]]; then
        local mcrt mkey
        mcrt="$(ask "Путь к fullchain.pem")"; mkey="$(ask "Путь к privkey.pem")"
        [[ -f "$mcrt" && -f "$mkey" ]] || die "файлы не найдены: $mcrt / $mkey"
        cp "$mcrt" "$CONFIG_ROOT/config/mumble/fullchain.pem"
        cp "$mkey" "$CONFIG_ROOT/config/mumble/privkey.pem"
        log "Подключён сертификат из $mcrt"
    else
        warn "АВАРИЙНЫЙ РЕЖИМ: self-signed сертификат. Клиенты Mumble увидят предупреждение."
        if [[ ! -f "$CONFIG_ROOT/config/mumble/fullchain.pem" ]]; then
            openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=mumble" \
                -keyout "$CONFIG_ROOT/config/mumble/privkey.pem" \
                -out "$CONFIG_ROOT/config/mumble/fullchain.pem" 2>/dev/null
            log "Сгенерирован самоподписанный сертификат (3650 дней)."
        fi
    fi
    chmod 644 "$CONFIG_ROOT/config/mumble/fullchain.pem" "$CONFIG_ROOT/config/mumble/privkey.pem" 2>/dev/null || true

    docker compose up -d mumble

    cat <<EOF

 Готово. Адрес сервера: ваш IP :64738 (UDP+TCP).
 Клиент Mumble: подключение -> $PUBLIC_IP, порт 64738, ник ученика.
${server_pw:+ Пароль сервера: $server_pw}
 SuperUser-пароль (администрирование из клиента): $su_pw (в .env: MUMBLE_SUPERUSER_PASSWORD)
 Каналы-комнаты и права: подключитесь как SuperUser -> правый клик по Root -> Add.
 Проброс на роутере: 64738 tcp+udp; UFW — Настройка сервера, п.6.
EOF
}
