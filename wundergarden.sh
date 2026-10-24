#!/usr/bin/env bash
# =============================================================================
#  Домашний сервер — модульный установщик с меню.
#  Сервисы: CouchDB (Obsidian LiveSync), Radicale, SFTPGo, Syncthing,
#  Matrix (continuwuity), Luanti, SearXNG. Фасад: nginx (stream SNI + HTTPS, сертификаты acme.sh).
#  Каждый пункт меню можно запускать повторно — всё идемпотентно.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

CONFIG_ROOT="/opt/homeserver"
DATA_DIR="$CONFIG_ROOT/data"
BACKUP_DIR="$CONFIG_ROOT/backups"
ENV_FILE="$CONFIG_ROOT/.env"
COMPOSE_FILE="$CONFIG_ROOT/docker-compose.yml"

# ---------- утилиты ----------------------------------------------------------
log()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; exit 1; }
ask() { local prompt="$1" default="${2:-}" ans
    if [[ -n "$default" ]]; then read -rp "$prompt [$default]: " ans || true; echo "${ans:-$default}"
    else read -rp "$prompt: " ans || true; echo "$ans"; fi; }
ask_yn() { local ans; read -rp "$1 [Y/n]: " ans || true; [[ "${ans:-y}" =~ ^[Yy](es)?$ ]]; }
gen_pass() { openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24; }
# цвета оформления (как в vps_autosetup: баннер пурпурный, номера ярко-пурпурные)
c_mag=$'\033[1;38;5;213m'  # баннер: розовый
c_num=$'\033[1;38;5;213m'  # номера пунктов: розовый полужирный
c_txt=$'\033[96m'          # текст пунктов: бирюзовый
c_dim=$'\033[2m'           # разделители: приглушённые
c_off=$'\033[0m'
banner() {
    if [[ "${COLUMNS:-80}" -lt 80 ]]; then
        printf '%s  W U N D E R G A R D E N%s\n' "$c_mag" "$c_off"
        printf '%s  (терминал узкий: %s колонок; для полного баннера нужно >= 80)%s\n' "$c_dim" "${COLUMNS:-80}" "$c_off"
        return 0
    fi
    cat <<BAN
${c_mag}                                                                          
                       ▄▄                                  ▄▄             
                       ██                                  ██             
██   ██ ██ ██ ████▄ ▄████ ▄█▀█▄ ████▄ ▄████  ▀▀█▄ ████▄ ▄████ ▄█▀█▄ ████▄ 
██ █ ██ ██ ██ ██ ██ ██ ██ ██▄█▀ ██ ▀▀ ██ ██ ▄█▀██ ██ ▀▀ ██ ██ ██▄█▀ ██ ██ 
 ██▀██  ▀██▀█ ██ ██ ▀████ ▀█▄▄▄ ██    ▀████ ▀█▄██ ██    ▀████ ▀█▄▄▄ ██ ██ 
                                         ██                               
                                       ▀▀▀${c_off}
BAN
}

LANG_UI="${LANG_UI:-ru}"
_t() { # _t KEY — строка интерфейса по LANG_UI (fallback: ru)
    if [[ "${LANG_UI:-ru}" == "en" ]]; then
        case "$1" in
            MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
            M01) echo "Server setup (host: SSH/UFW/fail2ban/swap/BBR/...)" ;;
            M02) echo "Docker — system preparation (docker, .env, compose)" ;;
            M03) echo "nginx and certificates (acme.sh wildcard, startup, stream)" ;;
            M04) echo "CouchDB — Obsidian LiveSync" ;;
            M05) echo "Radicale — CalDAV (Fossify calendar <-> calcurse)" ;;
            M06) echo "SFTPGo — files and share links for friends" ;;
            M07) echo "Syncthing (KeePassXC, backups)" ;;
            M08) echo "Matrix — continuwuity + coturn (TURN for calls)" ;;
            M09) echo "Luanti server (worlds/mods/game mode configurable)" ;;
            M10) echo "SearXNG — meta-search (configured during install)" ;;
            M11) echo "Excalidraw — whiteboard + saving + rooms" ;;
            M12) echo "Etherpad — collaborative text editor" ;;
            M13) echo "Mumble (Murmur) — voice for lessons" ;;
            M14) echo "ClassQuiz — Kahoot-style quizzes" ;;
            M15) echo "LimeSurvey — surveys and tests" ;;
            M16) echo "Backups (cron 03:30)" ;;
            M17) echo "Status" ;;
            M18) echo "Updates (per service)" ;;
            M19) echo "Language / Язык" ;;
            M20) echo "Netdata (monitoring: network, containers, DBs, nginx)" ;;
            M21) echo "Gitea (self-hosted Git behind nginx)" ;;
            M22) echo "Jitsi Meet (video conferencing)" ;;
            MQ)   echo "  q. Exit" ;;
            MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
            PROMPT_SETTINGS) echo "Item number (L — container logs, Enter — apply): " ;;
            PROMPT_BACK)     echo "Item number (Enter — back): " ;;
            PROMPT_NGINX)    echo "Item number (L — nginx logs, Enter — back): " ;;
            PROMPT_UPD)      echo "What to update? (Enter — back): " ;;
            LOGS_TITLE) echo " --- Which container's logs? ---" ;;
            LOGS_ALL)   echo "  a) all of them" ;;
            LOGS_NUM)   echo "Number (Enter — back): " ;;
            LOGS_BAD)   echo "no such number" ;;
            LOGS_NOTRUN) echo "container not running (install the service or see item 17 'Status')" ;;
            LOGS_TAIL)  echo "(last 50 lines)" ;;
            BACK_SETTINGS) echo "Enter — back to settings " ;;
            BACK)          echo "Enter — back " ;;
            SRV_TITLE) echo " --- Server setup (order = activation order) ---" ;;
            SRV01) echo "Timezone" ;; SRV02) echo "User and sudo" ;;
            SRV03) echo "sudo logging (on/off)" ;;
            SRV04) echo "View sudo log" ;; SRV05) echo "SSH hardening (keys, port, drop-in + rollback)" ;;
            SRV06) echo "Unattended-upgrades (host security updates)" ;; SRV07) echo "UFW (firewall)" ;;
            SRV08) echo "Fail2ban" ;; SRV09) echo "Swap (size/disable)" ;;
            SRV10) echo "BBR (TCP acceleration)" ;; SRV11) echo "DNS-over-TLS (systemd-resolved)" ;;
            SRV12) echo "IPv6 (on/off)" ;; SRV13) echo "RKN AS blocklist (ipset, auto-update)" ;;
            SRV14) echo "Scheduled reboot" ;; SRV15) echo "VPS diagnostics (third-party scripts)" ;;
            SRV16) echo "Shell history (tuning + view)" ;;
            SRV16) echo "Root mail (cron/unattended alerts via external SMTP)" ;;
            PREP_W1) echo "Next: item 3 (nginx and certificates: certificates first, then startup)." ;;
            PREP_W2) echo "Don't forget: A-records of subdomains -> your static IP, forward 80/443 on the router." ;;
        esac
        return
    fi
    case "$1" in
        MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        M01) echo "Настройка сервера (хост: SSH/UFW/fail2ban/swap/BBR/...)" ;;
        M02) echo "Docker — подготовка системы (docker, .env, compose)" ;;
        M03) echo "nginx и сертификаты (acme.sh wildcard, запуск, stream)" ;;
        M04) echo "CouchDB — Obsidian LiveSync" ;;
        M05) echo "Radicale — CalDAV (календарь Fossify ↔ calcurse)" ;;
        M06) echo "SFTPGo — файлы и ссылки для друзей" ;;
        M07) echo "Syncthing (KeePassXC, бэкапы)" ;;
        M08) echo "Matrix — continuwuity + coturn (TURN для звонков)" ;;
        M09) echo "Luanti-сервер (миры/моды/режим настраиваются)" ;;
        M10) echo "SearXNG — мета-поиск (настраивается при установке)" ;;
        M11) echo "Excalidraw — доска + сохранение + комнаты" ;;
        M12) echo "Etherpad — совместный текстовый редактор" ;;
        M13) echo "Mumble (Murmur) — голос для уроков" ;;
        M14) echo "ClassQuiz — викторины Kahoot-стиля" ;;
        M15) echo "LimeSurvey — опросы и тесты" ;;
        M16) echo "Бэкапы (cron 03:30)" ;;
        M17) echo "Статус" ;;
        M18) echo "Обновления (по одному сервису)" ;;
        M19) echo "Язык / Language" ;;
        M20) echo "Netdata — мониторинг (сеть, контейнеры, БД, nginx)" ;;
        M21) echo "Gitea — свой Git-хостинг за nginx" ;;
        M22) echo "Jitsi Meet (видеоконференции)" ;;
        MQ)   echo "  q. Выход" ;;
        MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        PROMPT_SETTINGS) echo "Номер пункта (L — логи контейнеров, Enter — установить): " ;;
        PROMPT_BACK)     echo "Номер пункта (Enter — назад): " ;;
        PROMPT_NGINX)    echo "Номер пункта (L — логи nginx, Enter — назад): " ;;
        PROMPT_UPD)      echo "Что обновить? (Enter — назад): " ;;
        LOGS_TITLE) echo " --- Логи какого контейнера? ---" ;;
        LOGS_ALL)   echo "  a) $(_t LOGS_ALL)" ;;
        LOGS_NUM)   echo "Номер (Enter — назад): " ;;
        LOGS_BAD)   echo "нет такого номера" ;;
        LOGS_NOTRUN) echo "контейнер не запущен (установите сервис или смотрите пункт 17 'Статус')" ;;
        LOGS_TAIL)  echo "(последние 50 строк)" ;;
        BACK_SETTINGS) echo "Enter — вернуться в меню настроек " ;;
        BACK)          echo "Enter — назад " ;;
        SRV_TITLE) echo " --- Настройка сервера (порядок = порядок активации) ---" ;;
        SRV01) echo "Часовой пояс" ;; SRV02) echo "Пользователь и sudo" ;;
        SRV03) echo "Логирование sudo (вкл/выкл)" ;;
        SRV04) echo "Просмотр лога sudo" ;; SRV05) echo "SSH-hardening (ключи, порт, drop-in + откат)" ;;
        SRV06) echo "Unattended-upgrades (security-обновления хоста)" ;; SRV07) echo "UFW (фаервол)" ;;
        SRV08) echo "Fail2ban" ;; SRV09) echo "Swap (размер/отключение)" ;;
        SRV10) echo "BBR (ускорение TCP)" ;; SRV11) echo "DNS-over-TLS (systemd-resolved)" ;;
        SRV12) echo "IPv6 (вкл/выкл)" ;; SRV13) echo "Блок-лист AS РКН (ipset, автообновление)" ;;
        SRV14) echo "Перезагрузка по расписанию" ;; SRV15) echo "Диагностика VPS (сторонние скрипты)" ;;
        SRV16) echo "История shell (тюнинг + просмотр)" ;;
        SRV16) echo "Почта root'а (оповещения cron/unattended через внешний SMTP)" ;;
        PREP_W1) echo "Дальше: пункт 3 (nginx и сертификаты: сначала сертификаты, затем запуск)." ;;
        PREP_W2) echo "Не забудьте: A-записи поддоменов -> ваш статический IP, проброс 80/443 на роутере." ;;
    esac
}
lang_menu() { # переключатель языка / language switcher
    echo "${c_txt}Язык интерфейса / Interface language:${c_off}"
    echo "${c_txt} 1. Русский (по умолчанию)${c_off}"
    echo "${c_txt} 2. English${c_off}"
    local c; read -rp "1/2: " c || true
    case "$c" in 2) LANG_UI="en" ;; *) LANG_UI="ru" ;; esac
    [[ -f "$ENV_FILE" ]] && update_env LANG_UI "$LANG_UI"
    if [[ "$LANG_UI" == "en" ]]; then log "Language set to English."; else log "Установлен русский язык."; fi
}
onoff() { [[ "$1" == "true" ]] && echo "вкл" || echo "выкл"; }
safe_descr() { case "$1" in 0) echo "выкл" ;; 2) echo "строгий" ;; *) echo "умеренный" ;; esac; }
load_env() { set -a; # shellcheck disable=SC1090
    source "$ENV_FILE"; set +a; }
has_forbidden() { # полный набор (для .env): пробел ' " | / \ $ &
    printf '%s' "$1" | grep -q "[\"'|/\$\\& ]"
}
forbidden_json() { # кавычки и бэкслеш (для вставки в JSON)
    printf '%s' "$1" | grep -q "[\"'\\\\]"
}
update_env() { # update_env KEY VALUE — без пробелов/кавычек/|/\\/\$/& (защита sed, source .env, compose)
    if has_forbidden "$2"; then
        die "update_env: небезопасное значение для $1: '$2' (пробелы, кавычки, |, \\, \$, & не поддерживаются)"
    fi
    if grep -q "^$1=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
    else echo "$1=$2" >> "$ENV_FILE"; fi; }
trap 'die "сбой на строке $LINENO — состояние не повреждено, можно повторить пункт."' ERR

print_menu() {
    banner
    cat <<MENU
${c_mag}$(_t MHDR)${c_off}
  ${c_num}1.${c_off} ${c_txt}$(_t M01)${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t M02)${c_off}
  ${c_num}3.${c_off} ${c_txt}$(_t M03)${c_off}
  ${c_num}4.${c_off} ${c_txt}$(_t M04)${c_off}
  ${c_num}5.${c_off} ${c_txt}$(_t M05)${c_off}
  ${c_num}6.${c_off} ${c_txt}$(_t M06)${c_off}
  ${c_num}7.${c_off} ${c_txt}$(_t M07)${c_off}
  ${c_num}8.${c_off} ${c_txt}$(_t M08)${c_off}
  ${c_num}9.${c_off} ${c_txt}$(_t M09)${c_off}
 ${c_num}10.${c_off} ${c_txt}$(_t M10)${c_off}
 ${c_num}11.${c_off} ${c_txt}$(_t M11)${c_off}
 ${c_num}12.${c_off} ${c_txt}$(_t M12)${c_off}
 ${c_num}13.${c_off} ${c_txt}$(_t M13)${c_off}
 ${c_num}14.${c_off} ${c_txt}$(_t M14)${c_off}
 ${c_num}15.${c_off} ${c_txt}$(_t M15)${c_off}
 ${c_num}16.${c_off} ${c_txt}$(_t M16)${c_off}
 ${c_num}17.${c_off} ${c_txt}$(_t M17)${c_off}
 ${c_num}18.${c_off} ${c_txt}$(_t M18)${c_off}
 ${c_num}19.${c_off} ${c_txt}$(_t M19)${c_off}
${c_txt}$(_t MQ)${c_off}
${c_mag}$(_t MFTR)${c_off}
MENU
}

# DEMO=1 — предпросмотр оформления меню: без root, без проверок ОС, ничего не устанавливает
if [[ "${DEMO:-0}" == "1" ]]; then
    LANG_UI="${LANG_UI:-ru}"
    print_menu
    echo "${c_txt}(DEMO=1: предпросмотр оформления. Установка — на Debian/Ubuntu под root, без DEMO.)${c_off}"
    exit 0
fi

# ---------- preflight: до любых обращений к диску/сети ----------
preflight() {
    if [[ $EUID -ne 0 ]]; then
        printf '\033[1;31m[ОШИБКА]\033[0m запустите от root: sudo bash %s\n' "$0" >&2
        exit 1
    fi
    [[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || { echo "нужен bash >= 4 (у вас: $BASH_VERSION)" >&2; exit 1; }
    command -v systemctl >/dev/null 2>&1 || { echo "нужен systemd (systemctl не найден)" >&2; exit 1; }
    [[ -r /etc/os-release ]] || { echo "не найден /etc/os-release — поддерживаются Debian/Ubuntu" >&2; exit 1; }
    local os_id os_like
    os_id="$(. /etc/os-release && echo "$ID")"
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    case " $os_id $os_like " in
        *" debian "*|*" ubuntu "*) ;;
        *) echo "поддерживаются Debian/Ubuntu (обнаружен: $os_id)" >&2; exit 1 ;;
    esac
    command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq curl; }
    command -v openssl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq openssl; }
    # ресурсы — только предупреждение о диске (RAM не проверяем: набор сервисов разворачивается выборочно)
    local free_mb
    free_mb="$({ df -m /var/lib/docker 2>/dev/null || df -m /; } | awk 'NR==2{print $4}' || true)"
    if [[ -n "$free_mb" && "$free_mb" -lt 10000 ]]; then
        warn "свободно < 10 ГБ на диске — образы и данные займут ~15–20 ГБ."
    fi
    # сеть: короткий проба, только предупреждение
    if ! curl -fsI --max-time 5 https://download.docker.com >/dev/null 2>&1; then
        warn "download.docker.com недоступен — проверьте сеть/прокси до пункта 0."
    fi
}
preflight

cd "$CONFIG_ROOT" 2>/dev/null || { mkdir -p "$CONFIG_ROOT"; cd "$CONFIG_ROOT"; }

# ---------- 0. подготовка системы -------------------------------------------






show_logs() { # show_logs контейнер [контейнер...]
    local c
    for c in "$@"; do
        if [[ -z "$(docker compose ps -q "$c" 2>/dev/null)" ]]; then
            warn "$c: $(_t LOGS_NOTRUN)"
            continue
        fi
        echo "${c_txt}===== $c $(_t LOGS_TAIL) =====${c_off}"
        docker compose logs --tail=50 "$c" 2>&1 | tail -n 50
        echo
    done
    read -rp "$(_t BACK_SETTINGS)" _ || true
}
logs_menu() { # logs_menu контейнер [контейнер...]
    local -a cs=("$@")
    while true; do
        echo; echo "$(_t LOGS_TITLE)"
        local i
        for i in "${!cs[@]}"; do printf '  %d) %s\n' "$((i+1))" "${cs[$i]}"; done
        echo "${c_txt}  a) $(_t LOGS_ALL)${c_off}"
        local n
        read -rp "$(_t LOGS_NUM)" n || true
        case "$n" in
            "") return 0 ;;
            a|A|ф|Ф) show_logs "${cs[@]}" ;;
            *)
                if [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 && "$n" -le ${#cs[@]} ]]; then
                    show_logs "${cs[$((n-1))]}"
                else warn "$(_t LOGS_BAD)"; fi ;;
        esac
    done
}
wait_container() { # wait_container <имя> <команда проверки...> — до 60 с
    local name="$1"; shift
    for _ in $(seq 1 30); do
        if docker compose exec -T "$name" "$@" >/dev/null 2>&1; then
            log "$name отвечает."; return 0
        fi
        sleep 2
    done
    warn "$name не отвечает за 60с — смотрите логи (L в меню сервиса) или docker compose logs $name"
}



update_service() { # update_service "Имя" svc1 [svc2...]
    local name="$1"; shift
    log "Обновляю: $name"
    log "  docker compose pull $*"
    docker compose pull "$@"
    docker compose up -d "$@"
    log "Контейнеры пересозданы с новыми образами (если они обновились)."
    if ask_yn "Показать логи обновлённых контейнеров для проверки?"; then
        show_logs "$@"
    fi
}

updates_menu() {
    ensure_prepared
    local -a names=( "nginx (фасад)" "CouchDB (Obsidian)" "Radicale (CalDAV)" "SFTPGo" "Syncthing" \
                     "Matrix + TURN" "Luanti" "SearXNG" "Excalidraw" "Etherpad" "Mumble" \
                     "ClassQuiz" "LimeSurvey" "Netdata" "Gitea" "Jitsi" )
    local -a svcs_list=( "nginx" "couchdb" "radicale" "sftpgo sftpgo-db" "syncthing" \
                         "matrix coturn" "luanti" "searxng" "excalidraw excalidraw-room excalidraw-storage" \
                         "etherpad etherpad-db" "mumble" \
                         "classquiz-frontend classquiz-api classquiz-worker classquiz-db classquiz-redis classquiz-meili" \
                         "limesurvey limesurvey-db" "netdata socket-proxy" "gitea gitea-db" )

    while true; do
        local -a idx=() i sc running
        echo; echo " --- Обновления: развёрнутые сервисы ---"
        for i in "${!names[@]}"; do
            read -ra sc <<< "${svcs_list[$i]}"
            if docker compose ps -a -q "${sc[@]}" 2>/dev/null | grep -q .; then
                idx+=("$i")
                running=$(docker compose ps -q "${sc[@]}" 2>/dev/null | grep -c . || true)
                printf '  %d) %-20s (%s/%s контейнеров работает)\n' "${#idx[@]}" "${names[$i]}" "$running" "${#sc[@]}"
            fi
        done
        if [[ ${#idx[@]} -eq 0 ]]; then
            warn "ни одного контейнера не найдено — сначала установите сервисы (пункты 1-12)."
            return 0
        fi
        echo "${c_txt}  a) обновить ВСЁ разом (docker compose pull && up -d)${c_off}"
        echo "${c_txt}  c) очистить повисшие слои образов (docker image prune -f)${c_off}"
        local n
        read -rp "$(_t PROMPT_UPD)" n || true
        case "$n" in
            "") return 0 ;;
            c|C|с|С)
                docker image prune -f
                docker system df ;;
            a|A|ф|Ф)
                log "Обновляю всё: pull + up -d по всем сервисам."
                docker compose pull
                docker compose up -d
                log "Готово. При проблемах повторяйте по одному сервису — так проще найти виновника." ;;
            *)
                if [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 && "$n" -le ${#idx[@]} ]]; then
                    local pick="${idx[$((n-1))]}"
                    read -ra sc <<< "${svcs_list[$pick]}"
                    update_service "${names[$pick]}" "${sc[@]}"
                else
                    warn "нет такого номера"
                fi ;;
        esac
    done
}

# ---------- fail2ban ----------
f2b_jail_state() { # f2b_jail_state <jail>
    fail2ban-client status "$1" >/dev/null 2>&1 && echo "✔ jail '$1' активен" || echo "jail '$1' выкл"
}

f2b_apply() { # f2b_apply enabled bantime maxretry findtime recidive nginx_jail ssh_port
    local enabled="$1" bantime="$2" maxretry="$3" findtime="$4" recidive="$5" nginx_jail="$6"; shift 6; local ssh_port="${1:-ssh}"
    local recidive_block=""
    [[ "$recidive" == "true" ]] && recidive_block='[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = iptables-multiport
bantime  = 604800
findtime = 86400
maxretry = 3'
    local nginx_block=""
    [[ "$nginx_jail" == "true" ]] && nginx_block="# nginx опубликован через docker -> бан только в цепочке DOCKER-USER
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /opt/homeserver/data/nginx-logs/error.log
chain    = DOCKER-USER
maxretry = 3

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /opt/homeserver/data/nginx-logs/error.log
chain    = DOCKER-USER
filter   = nginx-limit-req
maxretry = 10"
    cat > /etc/fail2ban/jail.d/99-homeserver.local <<EOF
# generated by deploy_homeserver.sh
[DEFAULT]
bantime   = $bantime
findtime  = $findtime
maxretry  = $maxretry
backend   = auto
banaction = iptables-multiport

[sshd]
enabled = $enabled
port    = $7
logpath = /var/log/auth.log

$recidive_block

$nginx_block
EOF
    systemctl enable --now fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    log "fail2ban перезапущен с новой конфигурацией:"
    fail2ban-client status 2>/dev/null | sed 's/^/  /' || warn "fail2ban-client не отвечает — смотрите логи (journalctl -u fail2ban)."
}

fail2ban_menu() {
    log "=== Fail2ban ==="
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        ask_yn "fail2ban не установлен. Установить (apt)?" || return 0
        apt-get update -qq && apt-get install -y -qq fail2ban
    fi
    [[ -f "$ENV_FILE" ]] && load_env
    local f2b_enabled="${F2B_ENABLED:-true}" bantime="${F2B_BANTIME:-3600}" \
          maxretry="${F2B_MAXRETRY:-5}" findtime="${F2B_FINDTIME:-600}" \
          recidive="${F2B_RECIDIVE:-true}" nginx_jail="${F2B_NGINX:-true}" \
          ssh_port="${F2B_SSH_PORT:-ssh}"

    while true; do
        cat <<SUM

${c_mag} --- Fail2ban: порты нашего стека и защита ---${c_off}
  Порт          Сервис                  Защита
  22/tcp        SSH (sshd)              $(f2b_jail_state sshd)
  80/tcp        nginx (HTTP)            редирект на HTTPS
  443/tcp       nginx (stream+http)     SNI-роутинг (п.3); $(f2b_jail_state nginx-limit-req)
  64738/tcp+udp Mumble (docker-publish) jail требует цепочки DOCKER-USER (сложно, см. ниже)
  2022/tcp      SFTPGo SFTP             встроенный Defender — включайте там (пункт 3)
  22000/tcp+udp Syncthing               нет внешнего auth-вектора
  30000/udp     Luanti                  UDP — fail2ban не применим
  3478/tcp+udp  coturn (host-network)   jail по логу возможен; малый риск при shared-secret
  64738/tcp+udp Mumble (docker-publish) jail требует цепочки DOCKER-USER (сложно, см. ниже)
  8384,8080     админки                 только localhost — fail2ban не нужен
  19999/tcp     netdata                 только localhost (127.0.0.1) — fail2ban не нужен

${c_mag} --- Настройки ---${c_off}
  ${c_num}1.${c_off} ${c_txt}Защита SSH: $(onoff "$f2b_enabled")${c_off}
  ${c_num}2.${c_off} ${c_txt}bantime (длительность бана): ${bantime} с = $((bantime/60)) мин${c_off}
  ${c_num}3.${c_off} ${c_txt}maxretry (попыток до бана): $maxretry${c_off}
  ${c_num}4.${c_off} ${c_txt}findtime (окно подсчёта): ${findtime} с = $((findtime/60)) мин${c_off}
  ${c_num}5.${c_off} ${c_txt}Recidive (заядлые -> бан на неделю): $(onoff "$recidive")${c_off}
  ${c_num}6.${c_off} ${c_txt}Jail nginx-ботов (basicauth/лимиты; бан в DOCKER-USER): $(onoff "$nginx_jail")${c_off}
  ${c_num}7.${c_off} ${c_txt}SSH-порт для jail: $ssh_port${c_off}
  ${c_num}8.${c_off} ${c_txt}Применить и перезапустить fail2ban${c_off}

SUM
        read -rp "Номер пункта (L — логи fail2ban, Enter — назад): " c || true
        case "$c" in
            1) [[ "$f2b_enabled" == "true" ]] && f2b_enabled="false" || f2b_enabled="true" ;;
            2)
                local bt; bt="$(ask "bantime, секунд (3600 = 1 час)" "$bantime")"
                [[ "$bt" =~ ^[0-9]+$ && "$bt" -ge 60 ]] && bantime="$bt" || warn "нужно число >= 60 — оставляю $bantime" ;;
            3)
                local mr; mr="$(ask "maxretry (3-10)" "$maxretry")"
                [[ "$mr" =~ ^[0-9]+$ && "$mr" -ge 1 && "$mr" -le 50 ]] && maxretry="$mr" || warn "нужно число 1-50 — оставляю $maxretry" ;;
            4)
                local ft; ft="$(ask "findtime, секунд (600 = 10 мин)" "$findtime")"
                [[ "$ft" =~ ^[0-9]+$ && "$ft" -ge 60 ]] && findtime="$ft" || warn "нужно число >= 60 — оставляю $findtime" ;;
            5) [[ "$recidive" == "true" ]] && recidive="false" || recidive="true" ;;
            6) [[ "$nginx_jail" == "true" ]] && nginx_jail="false" || nginx_jail="true" ;;
            7)
                local sp; sp="$(ask "SSH-порт (число или 'ssh' для 22/tcp)" "$ssh_port")"
                [[ "$sp" =~ ^(ssh|[0-9]{1,5})$ ]] && ssh_port="$sp" || warn "нужно число или 'ssh' — оставляю $ssh_port" ;;
            8)
                [[ -f "$ENV_FILE" ]] && {
                    update_env F2B_ENABLED "$f2b_enabled"; update_env F2B_BANTIME "$bantime"
                    update_env F2B_MAXRETRY "$maxretry"; update_env F2B_FINDTIME "$findtime"
                    update_env F2B_RECIDIVE "$recidive"; update_env F2B_NGINX "$nginx_jail"
                    update_env F2B_SSH_PORT "$ssh_port"
                }
                f2b_apply "$f2b_enabled" "$bantime" "$maxretry" "$findtime" "$recidive" "$nginx_jail" "$ssh_port" ;;
            L|l|Д|д)
                journalctl -u fail2ban --no-pager -n 30 2>/dev/null || tail -n 30 /var/log/fail2ban.log 2>/dev/null || warn "логи недоступны"
                read -rp "$(_t BACK)" _ || true ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

# ================= НАСТРОЙКА СЕРВЕРА (хост) =================
tz_setup() {
    log "Часовой пояс: текущий — $(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')"
    local tz; tz="$(ask "Часовой пояс (IANA, напр. Europe/Moscow)" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo Europe/Moscow)")"
    timedatectl set-timezone "$tz" && log "Установлено: $(timedatectl show --property=Timezone --value)"
}

user_setup() {
    local u; u="$(ask "Имя пользователя (a-z, цифры, _; пусто — отмена)")"
    [[ -z "$u" ]] && return 0
    [[ "$u" =~ ^[a-z_][a-z0-9_-]*$ ]] || { warn "некорректное имя"; return 1; }
    if id "$u" >/dev/null 2>&1; then warn "пользователь '$u' уже существует"; return 1; fi
    useradd -m -s /bin/bash "$u" && usermod -aG sudo "$u"
    if ask_yn "Задать пароль (Enter — нет, вход только по SSH-ключу)?"; then
        passwd "$u"
    else
        passwd -l "$u" >/dev/null 2>&1 || true
        local ip; ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo '<IP сервера>')"
        cat <<EOF
${c_mag}=== SSH-ключ для входа $u@$ip ===${c_off}
${c_txt}1. На своём компьютере создайте ключ (Enter на все вопросы):${c_off}
   ${c_txt}ssh-keygen -t ed25519${c_off}
${c_txt}2. Загрузите его на сервер:${c_off}
   ${c_txt}Linux/macOS:  ssh-copy-id -i ~/.ssh/id_ed25519.pub $u@$ip${c_off}
   ${c_txt}Windows (PowerShell):${c_off}
   ${c_txt}type \$env:USERPROFILE\.ssh\id_ed25519.pub | ssh $u@$ip "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"${c_off}
${c_txt}3. Проверьте вход по ключу:${c_off}
   ${c_txt}ssh $u@$ip${c_off}
${c_dim}4. Только после успешного входа — отключите парольный вход: п.5 «SSH-hardening» (там же смена порта).${c_off}
EOF
    fi
    id "$u"
}

sudo_logging_toggle() {
    local f=/etc/sudoers.d/99-homeserver-logging
    if [[ -f "$f" ]]; then
        ask_yn "Логирование sudo включено — отключить?" && { rm -f "$f" && log "Логирование sudo отключено."; }
        return 0
    fi
    cat > "$f" <<'EOF'
Defaults logfile=/var/log/sudo.log
Defaults loglinelen=0
Defaults log_year,tty_tickets
EOF
    if visudo -cf "$f" >/dev/null; then
        log "Логирование sudo -> /var/log/sudo.log"
        log "Файл появится после первой sudo-команды (sudo -n true создаст его сразу)."
    else
        rm -f "$f"; die "visudo не принял конфиг — откат."
    fi
}
shell_history_setup() {
    cat > /etc/profile.d/99-homeserver-history.sh <<'EOF'
# tuned shell history (deploy_homeserver.sh)
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
# общая история между сессиями: дописать новое, перечитать файл
PROMPT_COMMAND="history -a; history -c; history -r${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
    touch /root/.bash_history
    chattr +a /root/.bash_history 2>/dev/null && log "history: append-only (chattr +a) включён" \
        || warn "chattr недоступен (файловая система?) — история без append-only защиты"
    log "История shell настроена: метки времени, 100k записей, общая между сессиями (profile.d)."
    shell_history_view
}
shell_history_view() {
    local f=/root/.bash_history
    [[ -f "$f" ]] || { warn "$f не найден"; return 1; }
    echo "--- $f ($(wc -l < "$f") строк; метки времени вида '2026-10-15 20:03:11')"
    if command -v less >/dev/null 2>&1; then less "$f"; else tail -n 100 "$f"; fi
}

sudo_log_view() {
    if [[ ! -f /var/log/sudo.log ]]; then
        if [[ -f /etc/sudoers.d/99-homeserver-logging ]]; then
            warn "Логирование включено, но событий ещё не было — файл создаётся при первой sudo-команде."
            ask_yn "Создать тестовую запись сейчас (sudo -n true)?" && sudo -n true 2>/dev/null
        else
            warn "Логирование sudo выключено — включите (п.3)."
        fi
    else
        echo "${c_txt}--- /var/log/sudo.log (последние 50 строк):${c_off}"
        tail -n 50 /var/log/sudo.log
    fi
    read -rp "Enter — назад " _ || true
}
ssh_harden() {
    log "=== SSH-hardening ==="
    warn "Не закрывайте текущую сессию! После применения проверьте вход в НОВОМ окне."
    local port pwauth
    port="$(ask "Порт SSH (Enter — не менять)" "")"
    [[ -n "$port" && ! "$port" =~ ^[0-9]{1,5}$ ]] && { warn "нужно число — порт не меняю"; port=""; }
    echo "${c_txt}PasswordAuthentication no — только ключи. Убедитесь, что ключ уже работает!${c_off}"
    ask_yn "Отключить вход по паролю?" && pwauth="no" || pwauth="yes"
    # cloud-init форсирует PasswordAuthentication yes — отключаем его drop-in
    if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
        if ask_yn "Найден 50-cloud-init.conf (форсирует PasswordAuthentication) — отключить?"; then
            mv /etc/ssh/sshd_config.d/50-cloud-init.conf "/etc/ssh/sshd_config.d/50-cloud-init.conf.disabled.$(date +%s)"
            log "50-cloud-init.conf отключён (бэкап рядом)."
        fi
    fi
    local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
    cp "$cfg" "$cfg.bak.$(date +%s)" 2>/dev/null || true
    {
        [[ -n "$port" ]] && echo "Port $port"
        echo "${c_txt}PasswordAuthentication $pwauth${c_off}"
        echo "${c_txt}PermitRootLogin prohibit-password${c_off}"
        echo "${c_txt}MaxAuthTries 3${c_off}"
        echo "${c_txt}ClientAliveInterval 300${c_off}"
        echo "${c_txt}ClientAliveCountMax 2${c_off}"
        echo "${c_txt}X11Forwarding no${c_off}"
        echo "${c_txt}LogLevel VERBOSE${c_off}"
    } > "$cfg"
    if ! sshd -t; then
        local bak; bak=$(ls -1t "$cfg".bak.* 2>/dev/null | head -1)
        [[ -n "$bak" ]] && cp "$bak" "$cfg"
        sshd -t && die "конфиг невалиден, откат выполнен — разбирайтесь вручную"
    fi
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    log "SSH-hardening применён (sshd -t пройден, reload). Проверьте новое подключение!"
}

unattended_status() {
    dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && echo "unattended-upgrades: установлен" || echo "unattended-upgrades: НЕ установлен"
    echo "--- /etc/apt/apt.conf.d/20auto-upgrades:"; cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || echo "(нет — автообновления выключены)"
    if ! grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
        ask_yn "Включить автоматические security-обновления?" && {
            apt-get install -y -qq unattended-updates 2>/dev/null || apt-get install -y -qq unattended-upgrades
            printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
            log "Включено."
        }
    fi
}

swap_setup() {
    echo "--- текущее состояние:"; free -h; swapon --show || true
    local g; g="$(ask "Размер swap, ГБ (0 — отключить и удалить)" "2")"
    [[ "$g" =~ ^[0-9]+$ ]] || { warn "нужно число"; return 1; }
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapfile; then
        swapoff /swapfile && sed -i '\|^/swapfile |d' /etc/fstab && rm -f /swapfile && log "старый /swapfile удалён"
    fi
    if [[ "$g" -gt 0 ]]; then
        fallocate -l "${g}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((g*1024)) status=none
        chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
        grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo 'vm.swappiness=10' > /etc/sysctl.d/99-homeserver-swap.conf && sysctl -q -p /etc/sysctl.d/99-homeserver-swap.conf
        log "swap ${g}ГБ активен (swappiness=10)."
    fi
    free -h
}

bbr_setup() {
    if ! modprobe tcp_bbr 2>/dev/null; then warn "модуль tcp_bbr недоступен (ядро <4.9?) — BBR не применён"; return 1; fi
    printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-homeserver-bbr.conf
    sysctl -q -p /etc/sysctl.d/99-homeserver-bbr.conf
    log "BBR: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) (ожидается bbr)"
}

dot_setup() {
    local f=/etc/systemd/resolved.conf.d/99-homeserver.conf
    if [[ -f "$f" ]]; then
        ask_yn "DNS-over-TLS уже настроен — отключить?" && { rm -f "$f"; systemctl restart systemd-resolved; log "DoT отключён."; }
        return 0
    fi
    mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com\nDNSOverTLS=opportunistic\nDomains=~.\n' > "$f"
    systemctl restart systemd-resolved
    log "DoT (opportunistic, Cloudflare) включён. Если у контейнеров/сервисов появятся DNS-проблемы — отключите здесь же."
}

ipv6_setup() {
    local f=/etc/sysctl.d/99-homeserver-ipv6.conf
    if [[ -f "$f" ]]; then
        ask_yn "IPv6 сейчас ОТКЛЮЧЕН — включить обратно?" && { rm -f "$f"; sysctl -q -p; log "IPv6 включён."; }
        return 0
    fi
    warn "Отключение IPv6 решит вопрос AAAA-записей, обходящих docker (порты публикуются только на IPv4)."
    ask_yn "Отключить IPv6?" || return 0
    printf 'net.ipv6.conf.all.disable_ipv6=1\nnet.ipv6.conf.default.disable_ipv6=1\nnet.ipv6.conf.lo.disable_ipv6=1\n' > "$f"
    sysctl -q -p "$f" && log "IPv6 отключён. AAAA-записи можно не трогать — трафик по ним просто не пойдёт на хост."
}

abuse_block_setup() { # проактивный abuse-ipset (репутационные фиды)
    local script=/opt/homeserver/abuse-block.sh cron=/etc/cron.d/homeserver-abuse
    if [[ -f "$script" ]]; then
        echo "${c_txt}Abuse-лист: активен ($(ipset list abuse4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей)${c_off}"
        echo "${c_txt}  фид: ${ABUSE_FEED:-не задан}${c_off}"
        ask_yn "Отключить и удалить?" && {
            iptables -D INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null
            iptables -D DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null
            ipset destroy abuse4 2>/dev/null; rm -f "$script" "$cron"; log "Abuse-лист удалён."
        }
        return 0
    fi
    command -v ipset >/dev/null || apt-get install -y -qq ipset
    echo "${c_txt}Abuse-фид: список IP/сетей с плохой репутацией (сканеры, брутфорсеры, спамеры).${c_off}"
    echo "${c_txt}В отличие от fail2ban (реагирует) и RKN-листа (реестр) — дроп ДО первой попытки.${c_off}"
    echo "${c_txt}Применяется на входящие (INPUT + DOCKER-USER). Внимание: большие фиды могут задеть VPN/шейред-IP.${c_off}"
    echo "${c_txt} 1) dshield.netset — топ-20 атакующих /24 за 30 дней; ~20 записей, минимум ложных (рекомендуется)${c_off}"
    echo "${c_txt} 2) firehol_level1.netset — жёсткая агрегация (Spamhaus DROP/EDROP, DShield...); ~30k записей${c_off}"
    echo "${c_txt} 3) firehol_level2.netset — шире; ~80k записей, заметно больше ложных срабатываний${c_off}"
    echo "${c_txt} 4) свой URL (plain text, CIDR по одному на строку)${c_off}"
    local url
    case "$(ask "1-4" "1")" in
        2) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset" ;;
        3) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level2.netset" ;;
        4) url="$(ask "URL списка")" ;;
        *) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/dshield.netset" ;;
    esac
    [[ "$url" =~ ^https?://[a-zA-Z0-9./_-]+$ ]] || die "некорректный URL: '$url'"
    [[ -f "$ENV_FILE" ]] && update_env ABUSE_FEED "$url"
    cat > "$script" <<ABEOF
#!/usr/bin/env bash
# Abuse-ipset (firehol/dshield) — обновление + восстановление правил после ребута
set -e
URL="$url"
TMP="\$(mktemp)"
curl -fsSL --max-time 300 "\$URL" -o "\$TMP"
ipset create abuse4_tmp hash:net
grep -E '^[0-9]' "\$TMP" | sed 's/^/add abuse4_tmp /' | ipset restore
ipset create abuse4 hash:net 2>/dev/null || true
ipset swap abuse4_tmp abuse4
ipset destroy abuse4_tmp
rm -f "\$TMP"
iptables -C INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set abuse4 src -j DROP
iptables -C DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -m set --match-set abuse4 src -j DROP 2>/dev/null || true
ABEOF
    chmod +x "$script"
    "$script" || { rm -f "$script"; die "не удалось скачать/применить фид — откат."; }
    printf '@reboot root /opt/homeserver/abuse-block.sh\n17 4 * * * root /opt/homeserver/abuse-block.sh\n' > "$cron"
    log "Abuse-лист применён ($(ipset list abuse4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей), обновление ежедневно 4:17 + @reboot."
}

rkn_block_menu() { # п.12: оба списка
    while true; do
        echo
        echo "${c_txt} --- IP-блок-листы (ipset) ---${c_off}"
        [[ -f /opt/homeserver/rkn-block.sh ]] && st_rkn="активен" || st_rkn="выкл"
        [[ -f /opt/homeserver/abuse-block.sh ]] && st_ab="активен" || st_ab="выкл"
        echo "${c_txt} 1) Блок-лист AS РКН: $st_rkn${c_off}"
        echo "${c_txt} 2) Abuse-лист (репутационные фиды): $st_ab${c_off}"
        read -rp "Номер (Enter — назад): " c || true
        case "$c" in
            1) rkn_block_setup ;; 2) abuse_block_setup ;;
            "") return 0 ;; *) warn "нет такого пункта" ;;
        esac
    done
}

rkn_block_setup() {
    local script=/opt/homeserver/rkn-block.sh cron=/etc/cron.d/homeserver-rkn
    if [[ -f "$script" ]]; then
        echo "${c_txt}Блок-лист АС РКН: активен ($(ipset list rkn4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей)${c_off}"
        ask_yn "Отключить и удалить?" && {
            iptables -D INPUT -m set --match-set rkn4 src -j DROP 2>/dev/null
            iptables -D DOCKER-USER -m set --match-set rkn4 src -j DROP 2>/dev/null
            ipset destroy rkn4 2>/dev/null; rm -f "$script" "$cron"; log "Блок-лист удалён."
        }
        return 0
    fi
    command -v ipset >/dev/null || apt-get install -y -qq ipset
    cat > "$script" <<'RKNEOF'
#!/usr/bin/env bash
# Обновление ipset rkn4 из AS_Network_List (C24Be), восстановление правил после ребута
set -e
URL="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/firewall_rules/allow_single_ipv4.txt"
TMP="$(mktemp)"
curl -fsSL --max-time 300 "$URL" -o "$TMP"
ipset create rkn4_tmp hash:net
grep -E '^[0-9]' "$TMP" | sed 's/^/add rkn4_tmp /' | ipset restore
ipset create rkn4 hash:net 2>/dev/null || true
ipset swap rkn4_tmp rkn4
ipset destroy rkn4_tmp
rm -f "$TMP"
iptables -C INPUT -m set --match-set rkn4 src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set rkn4 src -j DROP
iptables -C DOCKER-USER -m set --match-set rkn4 src -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -m set --match-set rkn4 src -j DROP 2>/dev/null || true
RKNEOF
    chmod +x "$script"
    "$script" || { rm -f "$script"; die "не удалось скачать/применить список — откат."; }
    printf '@reboot root /opt/homeserver/rkn-block.sh\n23 3 * * * root /opt/homeserver/rkn-block.sh\n' > "$cron"
    log "Блок-лист применён и будет обновляться ежедневно (3:23) + после ребута."
    warn "Правила действуют на входящие (INPUT + DOCKER-USER): заблокированные диапазоны не достучатся до SSH/веба."
}

root_mail_setup() { # оповещения root'а через внешний SMTP (без открытого 25-го порта)
    if command -v msmtp >/dev/null && grep -qs "account default" /etc/msmtprc 2>/dev/null; then
        echo "${c_txt}Почта root'а уже настроена:${c_off}"
        grep -E '^(host|port|from):' /etc/msmtprc | sed 's/^/  /'
        grep -q '^MAILTO=' /etc/cron.d/homeserver-backup 2>/dev/null && echo "  cron MAILTO: задан"
        ask_yn "Перенастроить?" || return 0
    fi
    apt-get install -y -qq msmtp msmtp-mta
    echo "${c_txt}Внешний SMTP для оповещений (cron, unattended-upgrades). Исходящие только, 465/587 — порт 25 не нужен.${c_off}"
    echo "${c_txt}Для Gmail/Yandex нужен ПАРОЛЬ ПРИЛОЖЕНИЯ (не основной пароль).${c_off}"
    local host port user pass rcpt only_err
    host="$(ask "SMTP-хост (напр. smtp.gmail.com, smtp.yandex.ru)" "smtp.yandex.ru")"
    [[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] || die "некорректный хост: '$host'"
    port="$(ask "Порт (465 = SMTPS, 587 = STARTTLS)" "465")"
    [[ "$port" =~ ^(465|587)$ ]] || die "нужен 465 или 587"
    user="$(ask "Логин (полный email)")"
    [[ "$user" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || die "нужен email: '$user'"
    while :; do
        read -rsp "Пароль приложения: " pass; echo
        [[ -n "$pass" ]] && break
        warn "пароль пустой"
    done
    rcpt="$(ask "Ящик получателя оповещений" "$user")"
    [[ "$rcpt" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || die "некорректный ящик: '$rcpt'"
    ask_yn "Писать только при ОШИБКАХ unattended-upgrades (рекомендуется)?" && only_err="true" || only_err="false"

    local starttls="off"; [[ "$port" == "587" ]] && starttls="on"
    cp /etc/msmtprc "/etc/msmtprc.bak.$(date +%s)" 2>/dev/null || true
    cat > /etc/msmtprc <<EOF
defaults
auth on
tls on
tls_starttls $starttls
aliases /etc/aliases
logfile /var/log/msmtp.log

account default
host $host
port $port
from $user
user $user
password $pass
EOF
    chmod 600 /etc/msmtprc
    cp /etc/aliases "/etc/aliases.bak.$(date +%s)" 2>/dev/null || true
    printf 'root: %s\n' "$rcpt" > /etc/aliases

    # unattended-upgrades -> почта
    cat > /etc/apt/apt.conf.d/52homemail <<EOF
Unattended-Upgrade::Mail "$rcpt";
Unattended-Upgrade::MailOnlyOnError "$only_err";
EOF
    # cron наших заданий -> MAILTO
    local f
    for f in /etc/cron.d/homeserver-*; do
        [[ -f "$f" ]] || continue
        grep -q '^MAILTO=' "$f" || sed -i "1i MAILTO=$rcpt" "$f"
    done

    # тестовое письмо
    if printf "From: root\nTo: %s\nSubject: homeserver: mail test OK\n\nПочта root'а настроена.\n" "$rcpt" \
        | /usr/sbin/sendmail -t >/dev/null 2>&1; then
        log "Тестовое письмо отправлено на $rcpt — проверьте ящик (и папку Спам)."
    else
        warn "sendmail вернул ошибку — смотрите /var/log/msmtp.log (обычно: неверный пароль приложения или хост)."
    fi
    log "Почта root'а: $host:$port, оповещения cron/unattended -> $rcpt (only-on-error: $only_err)."
}

sched_reboot_setup() {
    local cron=/etc/cron.d/homeserver-reboot
    echo "Текущее расписание: $(cat "$cron" 2>/dev/null | grep -v '^#' || echo 'нет')"
    echo "${c_txt} 1) выключить  2) еженедельно (понедельник 05:00)  3) ежемесячно (1-е число 05:00)${c_off}"
    case "$(ask "1/2/3" "2")" in
        1) rm -f "$cron"; log "автоперезагрузка выключена" ;;
        3) printf '0 5 1 * * root /sbin/reboot\n' > "$cron"; log "перезагрузка: ежемесячно, 1-е, 05:00" ;;
        *) printf '0 5 * * 1 root /sbin/reboot\n' > "$cron"; log "перезагрузка: еженедельно, пн, 05:00" ;;
    esac
}

diag_menu() {
    warn "Диагностика — сторонний код, исполняется через curl | bash. Смотрите скрипты перед запуском!"
    echo "${c_txt} 1) vps-audit (аудит базовой защищённости)${c_off}"
    echo "${c_txt} 2) ipregion (регион/маршрут IP)${c_off}"
    echo "${c_txt} 3) Check.Place (IP-качество: скорость/пинг/стриминг)${c_off}"
    echo "${c_txt} 4) LemonBench (бенчмарк CPU/диска/сети)${c_off}"
    local n; n="$(ask "1-4 (Enter — назад)" "")"
    case "$n" in
        1) bash <(curl -fsSL https://raw.githubusercontent.com/hidden-refuge/vps-audit/main/vps-audit.sh) ;;
        2) bash <(curl -fsSL https://raw.githubusercontent.com/uxh/sh/main/ipregion.sh) ;;
        3) bash <(curl -sL https://check.place) -i ;;
        4) bash <(curl -fsSL https://raw.githubusercontent.com/LemonBench/LemonBench/main/LemonBench.sh) fast ;;
    esac
    [[ -n "$n" ]] && read -rp "$(_t BACK)" _ || true
}

server_menu() {
    [[ $EUID -eq 0 ]] || { warn "нужен root"; return 1; }
    while true; do
        cat <<SUM

$(_t SRV_TITLE)
  ${c_num}1.${c_off} ${c_txt}$(_t SRV01)${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t SRV02)${c_off}
  ${c_num}3.${c_off} ${c_txt}$(_t SRV03)${c_off}
  ${c_num}4.${c_off} ${c_txt}$(_t SRV04)${c_off}
  ${c_num}5.${c_off} ${c_txt}$(_t SRV05)${c_off}
  ${c_num}6.${c_off} ${c_txt}$(_t SRV06)${c_off}
  ${c_num}7.${c_off} ${c_txt}$(_t SRV07)${c_off}
  ${c_num}8.${c_off} ${c_txt}$(_t SRV08)${c_off}
  ${c_num}9.${c_off} ${c_txt}$(_t SRV09)${c_off}
 ${c_num}10.${c_off} ${c_txt}$(_t SRV10)${c_off}
 ${c_num}11.${c_off} ${c_txt}$(_t SRV11)${c_off}
 ${c_num}12.${c_off} ${c_txt}$(_t SRV12)${c_off}
 ${c_num}13.${c_off} ${c_txt}$(_t SRV13)${c_off}
 ${c_num}14.${c_off} ${c_txt}$(_t SRV14)${c_off}
 ${c_num}15.${c_off} ${c_txt}$(_t SRV15)${c_off}
 ${c_num}16.${c_off} ${c_txt}$(_t SRV16)${c_off}
SUM
        read -rp "$(_t PROMPT_BACK)" c || true
        case "$c" in
            1) tz_setup ;; 2) user_setup ;; 3) sudo_logging_toggle ;; 4) sudo_log_view ;;
            5) ssh_harden ;; 6) unattended_status ;; 7) setup_ufw ;; 8) fail2ban_menu ;;
            9) swap_setup ;; 10) bbr_setup ;; 11) dot_setup ;; 12) ipv6_setup ;;
            13) rkn_block_menu ;; 14) sched_reboot_setup ;; 15) diag_menu ;; 16) shell_history_setup ;; 16) root_mail_setup ;;
            "") return 0 ;; *) warn "нет такого пункта" ;;
        esac
    done
}


# ---------- инфраструктурные пункты ------------------------------------------



setup_ufw() {
    log "=== UFW (фаервол) ==="
    echo "${c_txt}UFW фильтрует трафик хоста (цепочка INPUT). Важно: порты, опубликованные Docker'ом${c_off}"
    echo "${c_txt}(Luanti 30000/udp, Mumble 64738, SFTP 2022 при режиме 'наружу', JVB 10000/udp) идут через${c_off}"
    echo "${c_txt}цепочку DOCKER мимо UFW — 'ufw allow/deny' на них НЕ действует. Ими управляют:${c_off}"
    echo "${c_txt}  - bind 127.0.0.1 vs 0.0.0.0 в меню сервиса (SFTPGo, Syncthing GUI — уже так);${c_off}"
    echo "${c_txt}  - внешний фаервол: проброс портов на роутере / security group у провайдера VPS;${c_off}"
    echo "${c_txt}  - цепочка DOCKER-USER (её используют наши IP-блок-листы, п.13).${c_off}"
    echo "${c_txt}Host-network сервисы (coturn) и SSH/80/443 — фильтруются UFW напрямую.${c_off}"
    command -v ufw >/dev/null || { apt-get install -y -qq ufw; }
    ufw allow OpenSSH >/dev/null
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ask_yn "Открыть порты TURN (3478 + 49152-65535/udp)? coturn работает в host-network — UFW здесь реально фильтрует." \
        && { ufw allow 3478/tcp >/dev/null; ufw allow 3478/udp >/dev/null; ufw allow 49152:65535/udp >/dev/null; } || true
    ufw --force enable >/dev/null
    log "UFW включён: OpenSSH, 80/tcp, 443/tcp + TURN (если разрешили). Docker-порты — см. пояснение выше."
}

setup_backups() {
    ensure_prepared
    cat > "$CONFIG_ROOT/backup.sh" <<'BKP_EOF'
#!/usr/bin/env bash
# Ночной бэкап: короткая остановка БД -> tar -> запуск. Храним 14 дней.
set -euo pipefail
cd /opt/homeserver
set -a; [ -f .env ] && . ./.env; set +a
TS=$(date +%Y%m%d-%H%M)
WORLDS="${LUANTI_WORLDS:-data/luanti/worlds}"
docker compose stop couchdb matrix luanti sftpgo-db etherpad-db classquiz-db limesurvey-db 2>/dev/null || true
tar czf "backups/homeserver-$TS.tar.gz" data/couchdb data/radicale data/matrix data/luanti data/excalidraw data/etherpad data/etherpad-db data/mumble data/classquiz data/classquiz-db data/classquiz-meili data/limesurvey data/limesurvey-db data/sftpgo-db "$WORLDS" 2>/dev/null || true
docker compose start couchdb matrix luanti sftpgo-db etherpad-db classquiz-db limesurvey-db 2>/dev/null || true
find backups -name 'homeserver-*.tar.gz' -mtime +14 -delete
BKP_EOF
    chmod +x "$CONFIG_ROOT/backup.sh"
    if ! crontab -l 2>/dev/null | grep -q backup.sh; then
        (crontab -l 2>/dev/null; echo "30 3 * * * $CONFIG_ROOT/backup.sh >> $BACKUP_DIR/backup.log 2>&1") | crontab -
    fi
    log "Бэкап: ежедневно 03:30 -> $BACKUP_DIR (14 дней хранения). Реплицируйте эту папку Syncthing на другое устройство."
}

show_status() {
    if docker compose ls >/dev/null 2>&1; then docker compose ps; fi
    echo "--- сайты nginx:"; ls -1 "$CONFIG_ROOT/config/nginx/conf.d" 2>/dev/null || true
    echo "--- stream nginx:"; ls -1 "$CONFIG_ROOT/config/nginx/stream.d" 2>/dev/null || true
}

# ---------- меню --------------------------------------------------------------


main() {
    [[ $EUID -eq 0 ]] || die "запустите от root: sudo bash $0"
    while true; do
        print_menu
        read -rp "Выбор: " choice || true
        case "$choice" in
            1) server_menu ;;
            2) prep_system ;;
            3) front_nginx_menu ;;
            4) install_couchdb ;;
            5) install_radicale ;;
            6) install_sftpgo ;;
            7) install_syncthing ;;
            8) install_matrix ;;
            9) install_luanti ;;
            10) install_searxng ;;
            11) install_excalidraw ;;
            12) install_etherpad ;;
            13) install_mumble ;;
            14) install_classquiz ;;
            15) install_limesurvey ;;
            16) setup_backups ;;
            17) show_status ;;
            18) updates_menu ;;
            19) lang_menu ;;
            20) install_netdata ;;
            21) install_gitea ;;
            22) jitsi_menu ;;
            q|Q|"") exit 0 ;;
            *) warn "нет такого пункта" ;;
        esac
        echo; read -rp "Enter — вернуться в меню " _ || true
    done
}

# ---------- загрузка модулей (лежат рядом, в modules/) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for m in "$SCRIPT_DIR"/modules/*.sh; do
    [[ -r "$m" ]] && source "$m"
done

main "$@"

