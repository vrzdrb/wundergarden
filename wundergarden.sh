#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CONFIG_ROOT="/opt/homeserver"
DATA_DIR="$CONFIG_ROOT/data"
BACKUP_DIR="$CONFIG_ROOT/backups"
ENV_FILE="$CONFIG_ROOT/.env"
COMPOSE_FILE="$CONFIG_ROOT/docker-compose.yml"

log()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; exit 1; }
ask() { local prompt="$1" default="${2:-}" ans
    if [[ -n "$default" ]]; then read -rp "$prompt [$default]: " ans || true; echo "${ans:-$default}"
    else read -rp "$prompt: " ans || true; echo "$ans"; fi; }
ask_yn() { local ans; read -rp "$1 [Y/n]: " ans || true; [[ "${ans:-y}" =~ ^[Yy](es)?$ ]]; }
gen_pass() { openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24; }
c_mag=$'\033[1;38;5;213m'
c_num=$'\033[1;38;5;213m'
c_txt=$'\033[96m'
c_dim=$'\033[2m'
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
_t() {
    if [[ "${LANG_UI:-ru}" == "en" ]]; then
        case "$1" in
            MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
            M01) echo "Server setup" ;;
            M02) echo "Docker — system preparation" ;;
            M03) echo "nginx and certificates" ;;
            M04) echo "CouchDB — Obsidian LiveSync" ;;
            M05) echo "Radicale — CalDAV" ;;
            M06) echo "SFTPGo — files and share links for friends" ;;
            M07) echo "Syncthing" ;;
            M08) echo "Matrix — continuwuity + coturn" ;;
            M09) echo "Luanti server" ;;
            M10) echo "SearXNG — meta-search" ;;
            M11) echo "Excalidraw — whiteboard + saving + rooms" ;;
            M12) echo "Etherpad — collaborative text editor" ;;
            M13) echo "Mumble — voice for lessons" ;;
            M14) echo "ClassQuiz — Kahoot-style quizzes" ;;
            M15) echo "LimeSurvey — surveys and tests" ;;
            M16) echo "Backups" ;;
            M17) echo "Status" ;;
            M18) echo "Updates" ;;
            M19) echo "Language / Язык" ;;
            M20) echo "Netdata" ;;
            M21) echo "Gitea" ;;
            M22) echo "Jitsi Meet" ;;
            MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Exit${c_off}" ;;
            MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
            PROMPT_SETTINGS) echo "Item number: " ;;
            PROMPT_BACK)     echo "Item number: " ;;
            PROMPT_NGINX)    echo "Item number: " ;;
            PROMPT_UPD)      echo "Item number: " ;;
            LOGS_TITLE) echo " --- Which container's logs? ---" ;;
            LOGS_ALL)   echo "  a) all of them" ;;
            BACK0)      echo "Back" ;;
            LOGS_NUM)   echo "Item number: " ;;
            LOGS_BAD)   echo "no such number" ;;
            LOGS_NOTRUN) echo "container not running (install the service or see item 17 'Status')" ;;
            LOGS_TAIL)  echo "(last 50 lines)" ;;
            BACK_SETTINGS) echo "Enter — back to settings " ;;
            BACK)          echo "Enter — back " ;;
            SRV_TITLE) echo " --- Server setup --- " ;;
            SRV01) echo "System update" ;;
            SRV02) echo "Network settings" ;;
            SRV03) echo "Set timezone" ;;
            SRV04) echo "Scheduled automatic reboot" ;;
            SRV05) echo "Configure password policy" ;;
            SRV06) echo "Create user" ;;
            SRV07) echo "SSH settings" ;;
            SRV08) echo "UFW settings" ;;
            SRV09) echo "Block RKN" ;;
            SRV10) echo "Add swap" ;;
            SRV11) echo "Enable sudo logging" ;;
            SRV12) echo "Fail2ban" ;; SRV02) echo "User and sudo" ;; SRV05) echo "SSH hardening" ;; SRV07) echo "UFW" ;; SRV09) echo "Swap" ;; SRV11) echo "DNS-over-TLS" ;; SRV13) echo "RKN AS blocklist" ;; SRV15) echo "VPS diagnostics" ;;
            PREP_W1) echo "Next: item 3 (nginx and certificates: certificates first, then startup)." ;;
            PREP_W2) echo "Don't forget: A-records of subdomains -> your static IP, forward 80/443 on the router." ;;
        esac
        return
    fi
    case "$1" in
        MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        M01) echo "Настройка сервера" ;;
        M02) echo "Docker — подготовка системы" ;;
        M03) echo "nginx и сертификаты" ;;
        M04) echo "CouchDB — Obsidian LiveSync" ;;
        M05) echo "Radicale — CalDAV" ;;
        M06) echo "SFTPGo — файлы и ссылки для друзей" ;;
        M07) echo "Syncthing" ;;
        M08) echo "Matrix — continuwuity + coturn" ;;
        M09) echo "Luanti-сервер" ;;
        M10) echo "SearXNG — мета-поиск" ;;
        M11) echo "Excalidraw — доска + сохранение + комнаты" ;;
        M12) echo "Etherpad — совместный текстовый редактор" ;;
        M13) echo "Mumble — голос для уроков" ;;
        M14) echo "ClassQuiz — викторины Kahoot-стиля" ;;
        M15) echo "LimeSurvey — опросы и тесты" ;;
        M16) echo "Бэкапы" ;;
        M17) echo "Статус" ;;
        M18) echo "Обновления" ;;
        M19) echo "Язык / Language" ;;
        M20) echo "Netdata — мониторинг" ;;
        M21) echo "Gitea — свой Git-хостинг за nginx" ;;
        M22) echo "Jitsi Meet" ;;
        MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Выход${c_off}" ;;
        MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        PROMPT_SETTINGS) echo "Номер пункта: " ;;
        PROMPT_BACK)     echo "Номер пункта: " ;;
        PROMPT_NGINX)    echo "Номер пункта: " ;;
        PROMPT_UPD)      echo "Номер пункта: " ;;
        LOGS_TITLE) echo " --- Логи какого контейнера? ---" ;;
        LOGS_ALL)   echo "  a) $(_t LOGS_ALL)" ;;
        LOGS_NUM)   echo "Номер пункта: " ;;
        LOGS_BAD)   echo "нет такого номера" ;;
        LOGS_NOTRUN) echo "контейнер не запущен (установите сервис или смотрите пункт 17 'Статус')" ;;
        LOGS_TAIL)  echo "(последние 50 строк)" ;;
        BACK_SETTINGS) echo "Enter — вернуться в меню настроек " ;;
        BACK)          echo "Enter — назад " ;;
        SRV_TITLE) echo " --- Настройка сервера --- " ;;
        SRV01) echo "Обновление системы" ;;
        SRV02) echo "Настройки сети" ;;
        SRV03) echo "Установка часового пояса" ;;
        SRV04) echo "Автоматическая перезагрузка по расписанию" ;;
        SRV05) echo "Установить политику паролей" ;;
        SRV06) echo "Создание пользователя" ;;
        SRV07) echo "Настройки SSH" ;;
        SRV08) echo "Настройки UFW" ;;
        SRV09) echo "Запретить РКН" ;;
        SRV10) echo "Добавить подкачку" ;;
        SRV11) echo "Включить логирование sudo" ;;
        SRV12) echo "Fail2ban" ;; SRV02) echo "Пользователь и sudo" ;; SRV05) echo "SSH-hardening" ;; SRV07) echo "UFW" ;; SRV09) echo "Swap" ;; SRV11) echo "DNS-over-TLS" ;; SRV13) echo "Блок-лист AS РКН" ;; SRV15) echo "Диагностика VPS" ;;
        PREP_W1) echo "Дальше: пункт 3 (nginx и сертификаты: сначала сертификаты, затем запуск)." ;;
        PREP_W2) echo "Не забудьте: A-записи поддоменов -> ваш статический IP, проброс 80/443 на роутере." ;;
    esac
}
lang_menu() {
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
load_env() { set -a;
    source "$ENV_FILE"; set +a; }
has_forbidden() {
    printf '%s' "$1" | grep -q "[\"'|/\$\\& ]"
}
forbidden_json() {
    printf '%s' "$1" | grep -q "[\"'\\\\]"
}
update_env() {
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

if [[ "${DEMO:-0}" == "1" ]]; then
    LANG_UI="${LANG_UI:-ru}"
    print_menu
    echo "${c_txt}(DEMO=1: предпросмотр оформления. Установка — на Debian/Ubuntu под root, без DEMO.)${c_off}"
    exit 0
fi

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
    local free_mb
    free_mb="$({ df -m /var/lib/docker 2>/dev/null || df -m /; } | awk 'NR==2{print $4}' || true)"
    if [[ -n "$free_mb" && "$free_mb" -lt 10000 ]]; then
        warn "свободно < 10 ГБ на диске — образы и данные займут ~15–20 ГБ."
    fi
    if ! curl -fsI --max-time 5 https://download.docker.com >/dev/null 2>&1; then
        warn "download.docker.com недоступен — проверьте сеть/прокси до пункта 0."
    fi
}
preflight

cd "$CONFIG_ROOT" 2>/dev/null || { mkdir -p "$CONFIG_ROOT"; cd "$CONFIG_ROOT"; }







show_logs() {
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
logs_menu() {
    local -a cs=("$@")
    while true; do
        echo; echo "$(_t LOGS_TITLE)"
        local i
        for i in "${!cs[@]}"; do printf '  %d) %s\n' "$((i+1))" "${cs[$i]}"; done
        echo "${c_txt}  a) $(_t LOGS_ALL)${c_off}"
        local n
        read -rp "$(_t LOGS_NUM)" n || true
        case "$n" in
            0) return 0 ;;
            a|A|ф|Ф) show_logs "${cs[@]}" ;;
            *)
                if [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 && "$n" -le ${#cs[@]} ]]; then
                    show_logs "${cs[$((n-1))]}"
                else warn "$(_t LOGS_BAD)"; fi ;;
        esac
    done
}
wait_container() {
    local name="$1"; shift
    for _ in $(seq 1 30); do
        if docker compose exec -T "$name" "$@" >/dev/null 2>&1; then
            log "$name отвечает."; return 0
        fi
        sleep 2
    done
    warn "$name не отвечает за 60с — смотрите логи (L в меню сервиса) или docker compose logs $name"
}



update_service() {
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
            0) return 0 ;;
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

f2b_jail_state() {
    fail2ban-client status "$1" >/dev/null 2>&1 && echo "✔ jail '$1' активен" || echo "jail '$1' выкл"
}

f2b_apply() {
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


run_update_upgrade() {
    echo "${c_txt}Обновление системы...${c_off}"
    apt update -y
    apt upgrade -y
    apt autoremove -y
    apt autoclean -y
    log "Обновление системы завершено!"
    read -rp "Enter — продолжить " _ || true
}

setup_network() {
    echo "${c_txt}Настройка сети...${c_off}"
    echo "${c_txt}Установка и настройка systemd-resolved...${c_off}"
    apt install -y systemd-resolved
    tee /etc/systemd/resolved.conf >/dev/null <<EOF
[Resolve]
DNS=1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
Domains=~.
DNSSEC=yes
DNSOverTLS=yes
EOF
    systemctl enable systemd-resolved.service
    systemctl start systemd-resolved.service
    systemctl restart systemd-resolved.service
    echo "${c_txt}Настройка BBR и отключение IPv6...${c_off}"
    grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf || echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.default.disable_ipv6 = 1" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.lo.disable_ipv6 = 1" /etc/sysctl.conf || echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
    sysctl -p
    log "Настройки сети завершены!"
    read -rp "Enter — продолжить " _ || true
}

setup_timezone() {
    echo "${c_txt}=== Настройка часового пояса ===${c_off}"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || timedatectl | grep "Time zone" | awk '{print $3}')
    echo "${c_txt}Текущий часовой пояс: ${current_tz}${c_off}"
    echo ""
    echo "${c_txt}Популярные часовые пояса:${c_off}"
    echo "  Europe/Moscow     — Москва"
    echo "  Europe/Kiev       — Киев"
    echo "  Europe/Minsk      — Минск"
    echo "  Europe/Berlin     — Берлин"
    echo "  Europe/London     — Лондон"
    echo "  America/New_York  — Нью-Йорк"
    echo "  Asia/Almaty       — Алматы"
    echo "  Asia/Tashkent     — Ташкент"
    echo ""
    echo "${c_txt}Полный список: timedatectl list-timezones${c_off}"
    echo ""
    local new_tz
    new_tz=$(ask "Новый часовой пояс" "")
    if [[ -n "$new_tz" ]]; then
        if timedatectl set-timezone "$new_tz" 2>/dev/null; then
            log "Часовой пояс установлен: $new_tz"
        else
            warn "Ошибка: не удалось установить часовой пояс '$new_tz'"
            warn "Проверьте написание. Список: timedatectl list-timezones"
        fi
    else
        warn "Изменения отменены."
    fi
    read -rp "Enter — продолжить " _ || true
}

setup_auto_reboot() {
    echo "${c_txt}=== Автоматическая перезагрузка по расписанию ===${c_off}"
    local current_reboot
    current_reboot=$(crontab -l 2>/dev/null | grep "/sbin/reboot" || echo "не настроено")
    echo "${c_txt}Текущее расписание перезагрузки: ${current_reboot}${c_off}"
    echo ""
    echo "  1. Ежедневно"
    echo "  2. Еженедельно"
    echo "  3. Ежемесячно"
    echo "  4. Отключить автоперезагрузку"
    echo ""
    local freq; freq=$(ask "Частота" "")
    case $freq in
        4)
            crontab -l 2>/dev/null | grep -v "/sbin/reboot" | crontab - 2>/dev/null || true
            log "Автоперезагрузка отключена"
            ;;
        1|2|3)
            local hour minute cron_expr desc dow dom
            hour=$(ask "Час перезагрузки (0-23)" "")
            if ! [[ "$hour" =~ ^[0-9]+$ ]] || [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ]; then
                warn "Некорректный час. Отменено."
                read -rp "Enter — продолжить " _ || true
                return 0
            fi
            minute=$(ask "Минуты (0-59)" "")
            if ! [[ "$minute" =~ ^[0-9]+$ ]] || [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ]; then
                warn "Некорректные минуты. Отменено."
                read -rp "Enter — продолжить " _ || true
                return 0
            fi
            case $freq in
                1) cron_expr="$minute $hour * * *"; desc="Ежедневно в $hour:$(printf '%02d' "$minute")" ;;
                2)
                    echo "Выберите день недели:"
                    echo "  1 — Понедельник"; echo "  2 — Вторник"; echo "  3 — Среда"
                    echo "  4 — Четверг"; echo "  5 — Пятница"; echo "  6 — Суббота"; echo "  7 — Воскресенье"
                    dow=$(ask "День" "")
                    if ! [[ "$dow" =~ ^[1-7]$ ]]; then
                        warn "Некорректный день. Отменено."
                        read -rp "Enter — продолжить " _ || true
                        return 0
                    fi
                    cron_expr="$minute $hour * * $dow"
                    desc="Еженедельно, день $dow в $hour:$(printf '%02d' "$minute")"
                    ;;
                3)
                    dom=$(ask "День месяца (1-28)" "")
                    if ! [[ "$dom" =~ ^[0-9]+$ ]] || [ "$dom" -lt 1 ] || [ "$dom" -gt 28 ]; then
                        warn "Некорректный день месяца. Отменено."
                        read -rp "Enter — продолжить " _ || true
                        return 0
                    fi
                    cron_expr="$minute $hour $dom * *"
                    desc="Ежемесячно, $dom-го числа в $hour:$(printf '%02d' "$minute")"
                    ;;
            esac
            crontab -l 2>/dev/null | grep -v "/sbin/reboot" | crontab - 2>/dev/null || true
            ( crontab -l 2>/dev/null; echo "$cron_expr /sbin/reboot" ) | crontab -
            log "Расписание установлено: $desc"
            log "Cron: $cron_expr /sbin/reboot"
            ;;
        *)
            warn "Неверный выбор!"
            ;;
    esac
    read -rp "Enter — продолжить " _ || true
}

configure_password_policy() {
    echo "${c_txt}=== Настройка политики паролей ===${c_off}"
    local pam_file="/etc/pam.d/common-password"
    local pwquality_conf="/etc/security/pwquality.conf"
    apt-get install -y libpam-pwquality
    sed -i '/pam_pwquality.so/d' "$pam_file"
    echo 'password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 enforce_for_root' >> "$pam_file"
    cat > "$pwquality_conf" <<EOF
minlen = 12
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
EOF
    pam-auth-update --force
    log "Политика паролей настроена."
    warn "Если пользователь уже создан — смените ему пароль, чтобы политика вступила в силу."
    read -rp "Enter — продолжить " _ || true
}

create_user() {
    echo "${c_txt}Создание нового пользователя...${c_off}"
    local username; username=$(ask "Имя пользователя" "")
    if id "$username" >/dev/null 2>&1; then
        warn "Пользователь $username уже существует!"
    else
        useradd -m -s /bin/bash "$username"
        passwd "$username"
        usermod -aG sudo "$username"
        log "Пользователь $username создан и добавлен в группу sudo"
    fi
    read -rp "Enter — продолжить " _ || true
}

setup_ufw() {
    echo "${c_txt}Настройка UFW...${c_off}"
    local port; port=$(ask "Введите ваш SSH порт" "")
    ufw --force reset
    ufw limit "$port/tcp" comment 'SSH'
    ufw allow 443/tcp comment 'WEB'
    ufw --force enable
    log "Настройки UFW завершены!"
    read -rp "Enter — продолжить " _ || true
}

block_rkn() {
    echo "${c_txt}Блокировка IP-адресов РКН...${c_off}"
    cat > add_blacklist.sh <<'EOF'
wget -O blacklist.txt https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist.txt
if [[ ! -f blacklist.txt ]]; then
echo "Файл blacklist.txt не найден!"
exit 1
fi
while read -r subnet; do
ufw deny from "$subnet"
done < blacklist.txt
ufw status
EOF
    chmod +x add_blacklist.sh
    log "Запускаем add_blacklist.sh..."
    ./add_blacklist.sh
    if ! crontab -l 2>/dev/null | grep -q "add_blacklist.sh"; then
        ( crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/add_blacklist.sh" ) | crontab -
        log "Задание добавлено в crontab: ежедневно в 3:00"
    else
        warn "Задание уже существует в crontab"
    fi
    log "Настройка ufw под РКН завершена!"
    read -rp "Enter — продолжить " _ || true
}

add_swap() {
    echo "${c_txt}Добавление swap файла...${c_off}"
    local swapfile="/swapfile"
    if [[ -f "$swapfile" ]]; then
        warn "Swap файл уже существует"
    else
        dd if=/dev/zero of=$swapfile bs=1M count=1024
        chmod 600 $swapfile
        mkswap $swapfile
        swapon $swapfile
        echo "$swapfile none swap sw 0 0" >> /etc/fstab
        log "1Гб подкачки создан и активирован"
    fi
    read -rp "Enter — продолжить " _ || true
}

enable_sudo_logging() {
    local sudoers_file="/etc/sudoers"
    sed -i '/Defaults logfile/d' "$sudoers_file"
    echo 'Defaults logfile="/var/log/sudo.log"' >> "$sudoers_file"
    if visudo -cf "$sudoers_file" >/dev/null; then
        log "Sudo logging enabled. Logs will be in /var/log/sudo.log"
    else
        warn "Failed to configure sudo logging"
    fi
    read -rp "Enter — продолжить " _ || true
}

fail2ban_menu() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        ask_yn "fail2ban не установлен. Установить?" || return 0
        apt-get update -qq && apt-get install -y -qq fail2ban
    fi
    [[ -f "$ENV_FILE" ]] && load_env
    local f2b_enabled="${F2B_ENABLED:-true}" bantime="${F2B_BANTIME:-3600}" \
          maxretry="${F2B_MAXRETRY:-5}" findtime="${F2B_FINDTIME:-600}" \
          recidive="${F2B_RECIDIVE:-true}" nginx_jail="${F2B_NGINX:-true}" \
          ssh_port="${F2B_SSH_PORT:-ssh}"

    while true; do
        cat <<SUM

${c_mag} --- Fail2ban --- ${c_off}
${c_mag} --- Текущие использованные порты --- ${c_off}
${c_txt}  Порт          Сервис
  22/tcp        SSH
  80/tcp        nginx
  443/tcp       nginx
  2022/tcp      SFTPGo
  22000/tcp+udp Syncthing
  21027/udp     Syncthing
  30000/udp     Luanti
  3478/tcp+udp  coturn
  64738/tcp+udp Mumble
  19999/tcp     netdata
  10000/udp     Jitsi${c_off}

${c_mag} --- Настройки --- ${c_off}
  ${c_num}1.${c_off} ${c_txt}SSH: $(onoff "$f2b_enabled")${c_off}
  ${c_num}2.${c_off} ${c_txt}bantime, с: $bantime${c_off}
  ${c_num}3.${c_off} ${c_txt}maxretry: $maxretry${c_off}
  ${c_num}4.${c_off} ${c_txt}findtime, с: $findtime${c_off}
  ${c_num}5.${c_off} ${c_txt}Recidive: $(onoff "$recidive")${c_off}
  ${c_num}6.${c_off} ${c_txt}Jail nginx: $(onoff "$nginx_jail")${c_off}
  ${c_num}7.${c_off} ${c_txt}SSH-порт: $ssh_port${c_off}
  ${c_num}8.${c_off} ${c_txt}Применить и перезапустить${c_off}
  ${c_num}9.${c_off} ${c_txt}Логи${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}

SUM
        read -rp "Номер пункта: " c || true
        case "$c" in
            1) [[ "$f2b_enabled" == "true" ]] && f2b_enabled="false" || f2b_enabled="true" ;;
            2)
                local bt; bt="$(ask "bantime, с" "$bantime")"
                [[ "$bt" =~ ^[0-9]+$ && "$bt" -ge 60 ]] && bantime="$bt" || warn "нужно число >= 60 — оставляю $bantime" ;;
            3)
                local mr; mr="$(ask "maxretry" "$maxretry")"
                [[ "$mr" =~ ^[0-9]+$ && "$mr" -ge 1 && "$mr" -le 50 ]] && maxretry="$mr" || warn "нужно число 1-50 — оставляю $maxretry" ;;
            4)
                local ft; ft="$(ask "findtime, с" "$findtime")"
                [[ "$ft" =~ ^[0-9]+$ && "$ft" -ge 60 ]] && findtime="$ft" || warn "нужно число >= 60 — оставляю $findtime" ;;
            5) [[ "$recidive" == "true" ]] && recidive="false" || recidive="true" ;;
            6) [[ "$nginx_jail" == "true" ]] && nginx_jail="false" || nginx_jail="true" ;;
            7)
                local sp; sp="$(ask "SSH-порт (число или 'ssh')" "$ssh_port")"
                [[ "$sp" =~ ^(ssh|[0-9]{1,5})$ ]] && ssh_port="$sp" || warn "нужно число или 'ssh' — оставляю $ssh_port" ;;
            8)
                [[ -f "$ENV_FILE" ]] && {
                    update_env F2B_ENABLED "$f2b_enabled"; update_env F2B_BANTIME "$bantime"
                    update_env F2B_MAXRETRY "$maxretry"; update_env F2B_FINDTIME "$findtime"
                    update_env F2B_RECIDIVE "$recidive"; update_env F2B_NGINX "$nginx_jail"
                    update_env F2B_SSH_PORT "$ssh_port"
                }
                f2b_apply "$f2b_enabled" "$bantime" "$maxretry" "$findtime" "$recidive" "$nginx_jail" "$ssh_port" ;;
            9)
                journalctl -u fail2ban --no-pager -n 30 2>/dev/null || tail -n 30 /var/log/fail2ban.log 2>/dev/null || warn "логи недоступны"
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}




ssh_harden() {
    echo "${c_txt}Настройка SSH...${c_off}"
    local username; username="$(ask "Имя созданного пользователя (НЕ ROOT)")"
    [[ -z "$username" ]] && { warn "имя обязательно"; return 1; }
    id "$username" >/dev/null 2>&1 || warn "пользователь '$username' не найден — проверьте имя"

    local port; port="$(ask "Новый SSH-порт" "22")"
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || die "некорректный порт: '$port'"

    local IP; IP="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || echo '<IP сервера>')"

    echo "${c_mag}=======================================================================================${c_off}"
    echo "${c_mag}ВНИМАТЕЛЬНО ПРОЧТИТЕ: сейчас вам нужно открыть терминал на своём компьютере${c_off}"
    echo "${c_mag}И создать ssh-ключ для входа на сервер следующей командой:${c_off}"
    echo "${c_txt}ssh-keygen -t ed25519${c_off}"
    echo ""
    echo "${c_mag}Загрузите ключ на сервер (команда для Linux):${c_off}"
    echo "${c_txt}ssh-copy-id -i имяключа.pub $username@$IP${c_off}"
    echo ""
    echo "${c_mag}Команда для Windows:${c_off}"
    echo "${c_txt}cat id_ed25519.pub | ssh $username@$IP mkdir -p && cat >> ~/.ssh/authorized_keys${c_off}"
    echo ""
    echo "${c_mag}Попробуйте подключиться к вашему серверу при помощи этого ключа:${c_off}"
    echo "${c_txt}ssh -i имяключа $username@$IP${c_off}"
    echo ""
    echo "${c_mag}ТОЛЬКО ЕСЛИ ВХОД УСПЕШЕН, нажмите здесь Enter для ОТКЛЮЧЕНИЯ ВХОДА В SSH ПО ПАРОЛЮ${c_off}"
    echo "${c_mag}=======================================================================================${c_off}"
    read -r

    local SSHD_CONFIG="/etc/ssh/sshd_config"
    [[ -f "$SSHD_CONFIG" ]] || die "не найден $SSHD_CONFIG"
    local BACKUP_FILE="/etc/ssh/sshd_config.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$SSHD_CONFIG" "$BACKUP_FILE"
    log "Резервная копия: $BACKUP_FILE"

    if ls /etc/ssh/sshd_config.d/99-homeserver.conf* >/dev/null 2>&1; then
        warn "Найден старый drop-in 99-homeserver.conf — перемещаю в /root/ssh-fix-backup/"
        mkdir -p /root/ssh-fix-backup
        mv /etc/ssh/sshd_config.d/99-homeserver.conf* /root/ssh-fix-backup/ 2>/dev/null || true
    fi

    local k v
    set_kv() {
        k="$1"; v="$2"
        if grep -q "^$k" "$SSHD_CONFIG"; then sed -i "s|^$k.*|$k $v|" "$SSHD_CONFIG"
        else echo "$k $v" >> "$SSHD_CONFIG"; fi
    }
    set_kv PubkeyAuthentication yes
    set_kv PasswordAuthentication no
    set_kv GSSAPIAuthentication no
    set_kv PermitRootLogin prohibit-password
    local SSH_CONFIG="/etc/ssh/ssh_config"
    if grep -q "^GSSAPIAuthentication" "$SSH_CONFIG" 2>/dev/null; then
        sed -i 's/^GSSAPIAuthentication.*/GSSAPIAuthentication no/' "$SSH_CONFIG"
    else echo "GSSAPIAuthentication no" >> "$SSH_CONFIG"; fi

    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-security-settings.conf <<EOF
Port $port
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
GSSAPIAuthentication no
Protocol 2
X11Forwarding no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
ChallengeResponseAuthentication no
KerberosAuthentication no
EOF

    if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
        ask_yn "Найден 50-cloud-init.conf (форсирует PasswordAuthentication) — отключить?" && {
            mv /etc/ssh/sshd_config.d/50-cloud-init.conf "/etc/ssh/sshd_config.d/50-cloud-init.conf.disabled.$(date +%s)"
            log "50-cloud-init.conf отключён (бэкап рядом)."
        }
    fi

    mkdir -p "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"
    chown -R "$username:$username" "/home/$username/.ssh"
    if [[ -f "/home/$username/.ssh/authorized_keys" ]]; then
        chmod 600 "/home/$username/.ssh/authorized_keys"
        chown "$username:$username" "/home/$username/.ssh/authorized_keys"
    fi

    if ! sshd -t; then
        warn "Ошибка в конфигурации SSH! Восстанавливаю из резервной копии..."
        cp "$BACKUP_FILE" "$SSHD_CONFIG"
        die "Конфигурация восстановлена из бэкапа. Разбирайтесь вручную."
    fi

    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi "Status: active"; then
        ufw limit "$port/tcp" comment 'SSH' >/dev/null 2>&1 || ufw allow "$port/tcp" >/dev/null
        ufw delete allow OpenSSH >/dev/null 2>&1 || true
        log "UFW: порт $port/tcp открыт (limit), правило OpenSSH удалено."
    fi

    if systemctl restart sshd 2>/dev/null; then
        log "Служба SSH перезапущена (sshd)."
    else
        systemctl restart ssh && log "Служба SSH перезапущена (ssh)."
    fi
    log "SSH порт: $port | вход по паролю: ОТКЛЮЧЁН"
    warn "Не закрывайте текущую сессию! Проверьте вход в новом окне: ssh -p $port $username@$IP"
    read -rp "Enter — продолжить " _ || true
}












server_menu() {
    [[ $EUID -eq 0 ]] || { warn "нужен root"; return 1; }
    while true; do
        cat 
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
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}

SUM
        read -rp "$(_t PROMPT_BACK)" c || true
        case "$c" in
            1) run_update_upgrade ;;
            2) setup_network ;;
            3) setup_timezone ;;
            4) setup_auto_reboot ;;
            5) configure_password_policy ;;
            6) create_user ;;
            7) ssh_harden ;;
            8) setup_ufw ;;
            9) block_rkn ;;
            10) add_swap ;;
            11) enable_sudo_logging ;;
            12) fail2ban_menu ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}






setup_backups() {
    ensure_prepared
    cat > "$CONFIG_ROOT/backup.sh" <<'BKP_EOF'
#!/usr/bin/env bash
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
            0) exit 0 ;;
            *) warn "нет такого пункта" ;;
        esac
        echo; read -rp "Enter — вернуться в меню " _ || true
    done
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for m in "$SCRIPT_DIR"/modules/*.sh; do
    [[ -r "$m" ]] && source "$m"
done

main "$@"

