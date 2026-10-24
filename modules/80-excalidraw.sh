#!/usr/bin/env bash

install_excalidraw() {
    ensure_prepared
    log "=== Excalidraw (доска + сохранение + комнаты) ==="
    local SUB="${SUB_EXCALIDRAW:-draw.$DOMAIN}" protected="true" collab="true" \
          storage="${EXCALIDRAW_STORAGE:-$CONFIG_ROOT/data/excalidraw}" \
          img_front="${EXCALIDRAW_IMAGE:-alswl/excalidraw:latest}" \
          img_room="${EXCALIDRAW_ROOM_IMAGE:-alswl/excalidraw-room-go:v0.1.0}" \
          img_storage="${EXCALIDRAW_STORAGE_IMAGE:-alswl/excalidraw-storage-backend:latest}" \
          user="" pass=""
    dns_hint "$SUB"

    while true; do
        local prot_descr="по паролю (basicauth)" collab_descr="вкл"
        [[ "$protected" == "false" ]] && prot_descr="открытый (любой по ссылке)"
        [[ "$collab" == "false" ]] && collab_descr="выкл (только личные доски)"
        clear
        cat <<SUM

${c_mag} --- Настройки Excalidraw ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Поддомен: https://$SUB${c_off}
  ${c_num}2.${c_off} ${c_txt}Доступ: $prot_descr${c_off}
  ${c_num}3.${c_off} ${c_txt}Live Collaboration: $collab_descr${c_off}
  ${c_num}4.${c_off} ${c_txt}Папка хранения досок: $storage${c_off}
  ${c_num}5.${c_off} ${c_txt}Образы: ${img_front##*/} | ${img_room##*/} | ${img_storage##*/}${c_off}

 ${c_num}6.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                SUB="$(ask "Поддомен" "$SUB")"; update_env SUB_EXCALIDRAW "$SUB"; dns_hint "$SUB" ;;
            2)
                if [[ "$protected" == "true" ]]; then protected="false"
                else
                    protected="true"
                    user="$(ask "Логин" "draw")"
                    while :; do
                        pass="$(ask "Пароль basicauth (Enter — сгенерировать)" "$(gen_pass)")"
                        [[ -n "$pass" ]] && break
                    done
                fi ;;
            3) [[ "$collab" == "true" ]] && collab="false" || collab="true" ;;
            4) storage="$(ask "Папка на хосте для сцен/файлов досок" "$storage")" ;;
            5)
                img_front="$(ask "Образ frontend (форк alswl)" "$img_front")"
                img_room="$(ask "Образ room-сервера (пин версии, см. README alswl)" "$img_room")"
                img_storage="$(ask "Образ storage backend" "$img_storage")" ;;
            6) logs_menu excalidraw excalidraw-room excalidraw-storage  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
    update_env SUB_EXCALIDRAW "$SUB"; update_env EXCALIDRAW_STORAGE "$storage"
    update_env EXCALIDRAW_IMAGE "$img_front"; update_env EXCALIDRAW_ROOM_IMAGE "$img_room"; update_env EXCALIDRAW_STORAGE_IMAGE "$img_storage"
    mkdir -p "$storage"

    docker compose up -d excalidraw excalidraw-room excalidraw-storage

    local collab_routes=""
    if [[ "$collab" == "true" ]]; then
        collab_routes=$(printf '    handle /socket.io/* {\n        reverse_proxy excalidraw-room:8082\n    }\n')
    fi
    local draw_auth=""
    if [[ "$protected" == "true" ]]; then
        [[ -z "$user" ]] && { user="draw"; pass="$(gen_pass)"; }
        mk_htpasswd draw "$user" "$pass"
        draw_auth=$(auth_conf draw "Excalidraw")
        log "basicauth: $user / $pass"
    fi
    add_site 45-draw "server {
    listen 8443 ssl;
    server_name $SUB;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
${draw_auth}    location /storage/ {
        proxy_pass http://excalidraw-storage:8081;
        include /etc/nginx/proxy_common.conf;
    }
    location /socket.io/ {
        proxy_pass http://excalidraw-room:8082;
        include /etc/nginx/proxy_common.conf;
        include /etc/nginx/ws_common.conf;
    }
    location / {
        proxy_pass http://excalidraw:80;
        include /etc/nginx/proxy_common.conf;
    }
}"

    local notes=""
    [[ "$protected" == "true" ]] && notes=" По комнатным ссылкам потребуется пароль basicauth ($user)."
    [[ "$collab" == "false" ]] && notes="$notes"$'\n'" Комнаты выключены (пункт 3) — Live Collaboration не подключится."
    cat <<EOF

 Готово: https://$SUB
 Доски сохраняются на сервере ($storage) и экспортируются в .excalidraw/PNG/SVG.
 Live Collaboration: меню -> Start session -> ссылка ученику (нужен HTTPS, иначе ошибка generateKey).$notes
 Порты контейнеров (80/8081/8082) сверьте с basic/docker-compose.yaml репозитория alswl при смене образов.
EOF
}
