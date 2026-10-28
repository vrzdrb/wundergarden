#!/usr/bin/env bash

install_luanti() {
    ensure_prepared
    check_dependencies
    log "=== Luanti-сервер ==="
    local worlds="${LUANTI_WORLDS:-$CONFIG_ROOT/data/luanti/worlds}" \
          mods="${LUANTI_MODS:-$CONFIG_ROOT/data/luanti/mods}" \
          games="${LUANTI_GAMES:-$CONFIG_ROOT/data/luanti/games}" \
          world="world" game="minetest" sname="HomeLuanti" motd="" \
          mode="survival" pvp="true" mg="v7" seed="" maxusers=8 \
          announce="false" admin="admin"

    while true; do
        local mode_descr="выживание" announce_descr="выкл (приватный)"
        [[ "$mode" == "peaceful" ]] && mode_descr="мирный (без урона)"
        [[ "$mode" == "creative" ]] && mode_descr="креатив"
        [[ "$announce" == "true" ]] && announce_descr="вкл (публичный список!)"
        clear
        cat <<SUM

${c_mag} --- Настройки Luanti ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Папки: миры $worlds | моды $mods | игры $games${c_off}
  ${c_num}2.${c_off} ${c_txt}Мир: $world | игра: $game${c_off}
  ${c_num}3.${c_off} ${c_txt}Название сервера: $sname | MOTD: ${motd:-—}${c_off}
  ${c_num}4.${c_off} ${c_txt}Режим игры: $mode_descr${c_off}
  ${c_num}5.${c_off} ${c_txt}PvP: $(onoff "$pvp")${c_off}
  ${c_num}6.${c_off} ${c_txt}Мирогенерация: $mg | seed: ${seed:-случайный}${c_off}
  ${c_num}7.${c_off} ${c_txt}Макс. игроков: $maxusers${c_off}
  ${c_num}8.${c_off} ${c_txt}Публикация в списке серверов: $announce_descr${c_off}
  ${c_num}9.${c_off} ${c_txt}Админ: $admin${c_off}

  ${c_num}0.${c_off} ${c_txt}Назад${c_off}
SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1)
                worlds="$(ask "Папка миров (map.sqlite любит быстрый диск — лучше SSD)" "$worlds")"
                mods="$(ask "Папка модов (статика — можно и на eMMC)" "$mods")"
                games="$(ask "Папка игр" "$games")" ;;
            2)
                world="$(ask "Имя мира (подпапка в папке миров)" "$world")"
                game="$(ask "ID игры (minetest, mineclonia, ... — должна лежать в папке игр)" "$game")" ;;
            3)
                sname="$(ask "Название сервера" "$sname")"
                motd="$(ask "MOTD (приветствие при входе; пусто — без него)" "$motd")" ;;
            4)
                echo "${c_txt} 1) выживание  2) мирный (урона нет)  3) креатив${c_off}"
                case "$(ask "1/2/3" "1")" in
                    2) mode="peaceful" ;; 3) mode="creative" ;; *) mode="survival" ;;
                esac ;;
            5) [[ "$pvp" == "true" ]] && pvp="false" || pvp="true" ;;
            6)
                mg="$(ask "Карта: v7 / v5 / valleys / carpathian / flat / singlenode" "$mg")"
                seed="$(ask "Seed (число; пусто — случайный при создании мира)" "$seed")" ;;
            7)
                local mu; mu="$(ask "Макс. игроков (число)" "$maxusers")"
                [[ "$mu" =~ ^[0-9]+$ ]] && maxusers="$mu" || warn "нужно число — оставляю $maxusers" ;;
            8)
                echo "${c_txt}Сервер появится в публичном списке servers.minetest.net — зайти сможет кто угодно.${c_off}"
                ask_yn "Публиковать сервер?" && announce="true" || announce="false" ;;
            9) admin="$(ask "Ник админа (в minetest.conf: name =)" "$admin")" ;;
            10) logs_menu luanti  ;;
            0) break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    mkdir -p "$worlds" "$mods" "$games" "$CONFIG_ROOT/data/luanti/config"
    chown -R 1000:1000 "$worlds" "$mods" "$games" "$CONFIG_ROOT/data/luanti/config" 2>/dev/null || true
    update_env LUANTI_WORLDS "$worlds"; update_env LUANTI_MODS "$mods"; update_env LUANTI_GAMES "$games"

    # Открываем порт в UFW
    require_cmd ufw ufw
    ufw allow 30000/udp comment 'Luanti' >/dev/null 2>&1 && log "UFW: порт 30000/udp открыт" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1 || true

    local conf="$CONFIG_ROOT/data/luanti/config/minetest.conf"
    cat > "$conf" <<EOF
server_name = $sname
port = 30000
bind_address = 0.0.0.0
max_users = $maxusers
enable_damage = $([[ "$mode" == "survival" ]] && echo true || echo false)
creative_mode = $([[ "$mode" == "creative" ]] && echo true || echo false)
enable_pvp = $pvp
default_privs = interact, shout
name = $admin
mg_name = $mg
server_announce = $announce
disallow_empty_password = true
EOF
    [[ -n "$motd" ]] && echo "motd = $motd" >> "$conf"
    [[ -n "$seed" ]] && echo "fixed_map_seed = $seed" >> "$conf"

    local wdir="$worlds/$world" wmt="$wdir/world.mt"
    if [[ ! -f "$wmt" ]]; then
        mkdir -p "$wdir"
        printf 'gameid = %s\nbackend = sqlite3\n' "$game" > "$wmt"
        log "Создан новый мир '$world' (игра: $game)."
    else
        log "Мир '$world' уже существует — world.mt не тронут (игра и seed берутся из него)."
    fi

    local -a modlist=()
    if [[ -d "$mods" ]]; then
        while IFS= read -r d; do
            if [[ -f "$d/modpack.conf" ]]; then modlist+=("$(basename "$d") (modpack)")
            else modlist+=("$(basename "$d")"); fi
        done < <(find "$mods" -maxdepth 2 -name mod.conf -printf '%h\n' 2>/dev/null | sort -u)
    fi
    if [[ ${#modlist[@]} -gt 0 ]]; then
        echo "${c_txt}Найдены моды в $mods:${c_off}"
        local i sel n mname
        for i in "${!modlist[@]}"; do printf '  %d) %s\n' "$((i+1))" "${modlist[$i]}"; done
        sel="$(ask "Номера для автовключения (через запятую; пусто — ничего)" "")"
        for n in ${sel//,/ }; do
            [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 && "$n" -le ${#modlist[@]} ]] || continue
            mname="${modlist[$((n-1))]%% *}"
            grep -q "^load_mod_$mname=" "$wmt" 2>/dev/null || echo "load_mod_$mname = true" >> "$wmt"
        done
    fi

    docker compose up -d luanti
    
    # Формируем параметры подключения
    local -a conn_params=(
        "Адрес: ${PUBLIC_IP:-<ваш-IP>}:30000 (UDP)"
        "Мир: $wdir"
        "Игра: $game"
        "Макс. игроков: $maxusers"
        "Режим: $mode"
        "PvP: $pvp"
        "Порт 30000/udp открыт в UFW"
    )
    
    if [[ "$announce" == "true" ]]; then
        conn_params+=("" "⚠ ВНИМАНИЕ: сервер опубликован в публичном списке servers.minetest.net!")
    fi
    
    # Вывод параметров подключения
    show_connection_info "Luanti (Minetest)" "${conn_params[@]}"
    
    # Сохранение параметров в файл
    log_connection_params "Luanti" \
        "Адрес: ${PUBLIC_IP:-<ваш-IP>}:30000 (UDP)" \
        "Мир: $wdir" \
        "Игра: $game"
}
