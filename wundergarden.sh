#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ВАЖНО: Определяем SCRIPT_DIR ДО смены директории!
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Проверка наличия команды и установка если нужно
require_cmd() {
    local cmd="$1" pkg="${2:-$1}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "$cmd не найден — устанавливаю $pkg..."
        apt-get update -qq && apt-get install -y -qq "$pkg"
    fi
}

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
            M04) echo "Netdata — monitoring" ;;
            M05) echo "Gitea — Git hosting" ;;
            M06) echo "Jitsi Meet" ;;
            M07) echo "CouchDB — Obsidian LiveSync" ;;
            M08) echo "Radicale — CalDAV" ;;
            M09) echo "SFTPGo — files" ;;
            M10) echo "Syncthing" ;;
            M11) echo "Matrix — continuwuity + coturn" ;;
            M12) echo "Luanti server" ;;
            M13) echo "SearXNG — meta-search" ;;
            M14) echo "Excalidraw" ;;
            M15) echo "Etherpad" ;;
            M16) echo "Mumble" ;;
            M17) echo "ClassQuiz" ;;
            M18) echo "LimeSurvey" ;;
            M19) echo "Backups" ;;
            M20) echo "Status" ;;
            M21) echo "Updates" ;;
            M22) echo "Language / Язык" ;;
            MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Exit${c_off}" ;;
            MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        SRV01) echo "Timezone" ;;
        SRV02) echo "BBR, IPv6, DNS" ;;
        SRV03) echo "Scheduled reboot" ;;
        SRV04) echo "Password policy" ;;
        SRV05) echo "Create user" ;;
        SRV06) echo "SSH settings" ;;
        SRV07) echo "UFW settings" ;;
        SRV10) echo "Swap" ;;
        SRV11) echo "Sudo logging" ;;
        SRV12) echo "Fail2ban" ;;
        SRV13) echo "Unattended upgrades" ;;
        SRV14) echo "Root mail (SMTP)" ;;
        SRV15) echo "Shell history" ;;
        SRV16) echo "VPS diagnostics" ;;        esac
        return
    fi
    case "$1" in
        MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        M01) echo "Настройка сервера" ;;
        M02) echo "Docker — подготовка системы" ;;
        M03) echo "nginx и сертификаты" ;;
        M04) echo "Netdata — мониторинг" ;;
        M05) echo "Gitea — Git-хостинг" ;;
        M06) echo "Jitsi Meet" ;;
        M07) echo "CouchDB — Obsidian LiveSync" ;;
        M08) echo "Radicale — CalDAV" ;;
        M09) echo "SFTPGo — файлы" ;;
        M10) echo "Syncthing" ;;
        M11) echo "Matrix — continuwuity + coturn" ;;
        M12) echo "Luanti-сервер" ;;
        M13) echo "SearXNG — мета-поиск" ;;
        M14) echo "Excalidraw — доска" ;;
        M15) echo "Etherpad — редактор" ;;
        M16) echo "Mumble — голос" ;;
        M17) echo "ClassQuiz — викторины" ;;
        M18) echo "LimeSurvey — опросы" ;;
        M19) echo "Бэкапы" ;;
        M20) echo "Статус" ;;
        M21) echo "Обновления" ;;
        M22) echo "Язык / Language" ;;
        MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Выход${c_off}" ;;
        MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        SRV01) echo "Часовой пояс" ;;
        SRV02) echo "BBR, IPv6, DNS" ;;
        SRV03) echo "Перезагрузка по расписанию" ;;
        SRV04) echo "Политика паролей" ;;
        SRV05) echo "Создание пользователя" ;;
        SRV06) echo "Настройки SSH" ;;
        SRV07) echo "Настройки UFW" ;;
        SRV10) echo "Swap (подкачка)" ;;
        SRV11) echo "Логирование sudo" ;;
        SRV12) echo "Fail2ban" ;;
        SRV13) echo "Автообновления (unattended)" ;;
        SRV14) echo "Почта root (SMTP)" ;;
        SRV15) echo "История shell" ;;
        SRV16) echo "Диагностика VPS" ;;
    esac
}

lang_menu() {
    clear
    echo "${c_txt}Язык интерфейса / Interface language:${c_off}"
    echo "${c_txt} 1. Русский (по умолчанию)${c_off}"
    echo "${c_txt} 2. English${c_off}"
    local c; read -rp "1/2: " c || true
    case "$c" in 2) LANG_UI="en" ;; *) LANG_UI="ru" ;; esac
    [[ -f "$ENV_FILE" ]] && update_env LANG_UI "$LANG_UI"
    if [[ "$LANG_UI" == "en" ]]; then log "Language set to English."; else log "Установлен русский язык."; fi
}

onoff() { [[ "$1" == "true" ]] && echo "вкл" || echo "выкл"; }
load_env() { set -a; source "$ENV_FILE"; set +a; }
has_forbidden() { printf '%s' "$1" | grep -q "[\"'|/\$\\& ]"; }
update_env() {
    if has_forbidden "$2"; then
        die "update_env: небезопасное значение для $1: '$2'"
    fi
    if grep -q "^$1=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
    else echo "$1=$2" >> "$ENV_FILE"; fi;
}
trap 'die "сбой на строке $LINENO"' ERR

print_menu() {
    clear
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
 ${c_num}20.${c_off} ${c_txt}$(_t M20)${c_off}
 ${c_num}21.${c_off} ${c_txt}$(_t M21)${c_off}
 ${c_num}22.${c_off} ${c_txt}$(_t M22)${c_off}
${c_txt}$(_t MQ)${c_off}
${c_mag}$(_t MFTR)${c_off}
MENU
}

preflight() {
    if [[ $EUID -ne 0 ]]; then
        printf '\033[1;31m[ОШИБКА]\033[0m запустите от root: sudo bash %s\n' "$0" >&2
        exit 1
    fi
    [[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || { echo "нужен bash >= 4" >&2; exit 1; }
    command -v systemctl >/dev/null 2>&1 || { echo "нужен systemd" >&2; exit 1; }
    [[ -r /etc/os-release ]] || { echo "не найден /etc/os-release" >&2; exit 1; }
    local os_id os_like
    os_id="$(. /etc/os-release && echo "$ID")"
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    case " $os_id $os_like " in
        *" debian "*|*" ubuntu "*) ;;
        *) echo "поддерживаются Debian/Ubuntu (обнаружен: $os_id)" >&2; exit 1 ;;
    esac
    require_cmd curl curl
    require_cmd openssl openssl
}
preflight

cd "$CONFIG_ROOT" 2>/dev/null || { mkdir -p "$CONFIG_ROOT"; cd "$CONFIG_ROOT"; }

# ========== ФУНКЦИИ НАСТРОЙКИ СЕРВЕРА ==========

setup_timezone() {
    clear
    echo "${c_txt}=== Часовой пояс ===${c_off}"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')
    echo "Текущий: $current_tz"
    local new_tz; new_tz=$(ask "Новый часовой пояс (IANA, напр. Europe/Moscow)" "$current_tz")
    timedatectl set-timezone "$new_tz" && log "Установлено: $new_tz"
}

setup_network_bbr_ipv6_dns() {
    clear
    while true; do
        echo "${c_txt}=== BBR, IPv6, DNS ===${c_off}"
        echo "  1. BBR (ускорение TCP): $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')"
        echo "  2. IPv6: $([ -f /etc/sysctl.d/99-homeserver-ipv6.conf ] && echo 'отключён' || echo 'включён')"
        echo "  3. DNS-over-TLS: $([ -f /etc/systemd/resolved.conf.d/99-homeserver.conf ] && echo 'включён (Cloudflare)' || echo 'выкл')"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                if ! modprobe tcp_bbr 2>/dev/null; then warn "модуль tcp_bbr недоступен"; continue; fi
                printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-homeserver-bbr.conf
                sysctl -q -p /etc/sysctl.d/99-homeserver-bbr.conf
                log "BBR включён: $(sysctl -n net.ipv4.tcp_congestion_control)" ;;
            2)
                local f=/etc/sysctl.d/99-homeserver-ipv6.conf
                if [[ -f "$f" ]]; then
                    ask_yn "IPv6 отключён — включить?" && { rm -f "$f"; sysctl -q -p; log "IPv6 включён"; }
                else
                    warn "Отключение IPv6 решит вопрос AAAA-записей"
                    ask_yn "Отключить IPv6?" || continue
                    printf 'net.ipv6.conf.all.disable_ipv6=1\nnet.ipv6.conf.default.disable_ipv6=1\nnet.ipv6.conf.lo.disable_ipv6=1\n' > "$f"
                    sysctl -q -p "$f" && log "IPv6 отключён"
                fi ;;
            3)
                local f=/etc/systemd/resolved.conf.d/99-homeserver.conf
                if [[ -f "$f" ]]; then
                    ask_yn "DoT включён — отключить?" && { rm -f "$f"; systemctl restart systemd-resolved; log "DoT отключён"; }
                else
                    require_cmd resolvectl systemd
                    mkdir -p /etc/systemd/resolved.conf.d
                    # Удаление симлинка и создание статичного файла
                    rm -f /etc/resolv.conf
                    cat > /etc/resolv.conf <<EOF
# Статический resolv.conf (не управляется systemd-resolved)
nameserver 1.1.1.1
nameserver 9.9.9.9
nameserver 8.8.8.8
EOF
                    chmod 644 /etc/resolv.conf
                    # DoT через systemd-resolved
                    printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net 8.8.8.8#dns.google\nDNSOverTLS=opportunistic\nDomains=~.\n' > "$f"
                    systemctl restart systemd-resolved
                    log "DoT включён (Cloudflare, Quad9, Google)"
                fi ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

setup_scheduled_reboot() {
    clear
    require_cmd crontab cron
    echo "${c_txt}=== Перезагрузка по расписанию ===${c_off}"
    local cron=/etc/cron.d/homeserver-reboot
    echo "Текущее: $(cat "$cron" 2>/dev/null | grep -v '^#' || echo 'нет')"
    echo "  1. Выключить"
    echo "  2. Еженедельно (пн 05:00)"
    echo "  3. Ежемесячно (1-е число 05:00)"
    case "$(ask "1/2/3" "2")" in
        1) rm -f "$cron"; log "выключено" ;;
        3) printf '0 5 1 * * root /sbin/reboot\n' > "$cron"; log "ежемесячно" ;;
        *) printf '0 5 * * 1 root /sbin/reboot\n' > "$cron"; log "еженедельно" ;;
    esac
}

configure_password_policy() {
    clear
    echo "${c_txt}=== Политика паролей ===${c_off}"
    require_cmd pam_pwquality libpam-pwquality
    local pam_file="/etc/pam.d/common-password"
    sed -i '/pam_pwquality.so/d' "$pam_file"
    echo 'password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1' >> "$pam_file"
    log "Политика: мин. 12 символов, верхний/нижний/цифры/спецсимволы"
}

create_user() {
    clear
    echo "${c_txt}=== Создание пользователя ===${c_off}"
    local username; username=$(ask "Имя пользователя" "")
    [[ -z "$username" ]] && return 0
    if id "$username" >/dev/null 2>&1; then
        warn "пользователь $username уже существует"
    else
        useradd -m -s /bin/bash "$username"
        passwd "$username"
        usermod -aG sudo "$username"
        log "Пользователь $username создан"
    fi
}

ssh_settings_menu() {
    clear
    while true; do
        echo "${c_txt}=== Настройки SSH ===${c_off}"
        echo "  1. Изменить SSH-порт"
        echo "  2. Добавить SSH-ключ"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                require_cmd ufw ufw
                local port; port=$(ask "Новый SSH-порт" "22")
                [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || { warn "некорректный порт"; continue; }
                ufw allow "$port/tcp" comment 'SSH' >/dev/null
                ufw reload >/dev/null
                # Обновляем sshd_config
                local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
                mkdir -p /etc/ssh/sshd_config.d
                grep -q "^Port " "$cfg" 2>/dev/null && sed -i "s|^Port .*|Port $port|" "$cfg" || echo "Port $port" >> "$cfg"
                systemctl reload ssh 2>/dev/null || systemctl reload sshd
                log "SSH-порт изменён на $port" ;;
            2)
                local username; username=$(ask "Имя пользователя" "")
                [[ -z "$username" ]] && continue
                id "$username" >/dev/null 2>&1 || { warn "пользователь не найден"; continue; }
                local IP; IP="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || echo '<IP>')"
                echo "${c_mag}Создайте ключ на своём компьютере:${c_off}"
                echo "${c_txt}ssh-keygen -t ed25519${c_off}"
                echo "${c_mag}Загрузите ключ:${c_off}"
                echo "${c_txt}ssh-copy-id -i ~/.ssh/id_ed25519.pub $username@$IP${c_off}"
                echo "${c_mag}Проверьте вход ключом, затем нажмите Enter для отключения пароля${c_off}"
                read -r
                # Отключаем пароль
                local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
                mkdir -p /etc/ssh/sshd_config.d
                grep -q "^PasswordAuthentication" "$cfg" 2>/dev/null && sed -i 's|^PasswordAuthentication.*|PasswordAuthentication no|' "$cfg" || echo "PasswordAuthentication no" >> "$cfg"
                # Удаляем 50-cloud-init если есть
                if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
                    mv /etc/ssh/sshd_config.d/50-cloud-init.conf "/etc/ssh/sshd_config.d/50-cloud-init.conf.disabled.$(date +%s)"
                    log "50-cloud-init.conf отключён"
                fi
                systemctl reload ssh 2>/dev/null || systemctl reload sshd
                log "Вход по паролю отключён" ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

ufw_settings_menu() {
    clear
    require_cmd ufw ufw
    while true; do
        echo "${c_txt}=== Настройки UFW ===${c_off}"
        echo "  1. Изменить SSH-порт"
        echo "  2. Блокировка ботов (abuse-ipset)"
        echo "  3. Блокировка РКН"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1) ssh_settings_menu ;;
            2) abuse_block_setup ;;
            3) block_rkn ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

abuse_block_setup() {
    clear
    require_cmd ipset ipset
    local script=/opt/homeserver/abuse-block.sh cron=/etc/cron.d/homeserver-abuse
    if [[ -f "$script" ]]; then
        echo "Abuse-лист: активен ($(ipset list abuse4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей)"
        ask_yn "Отключить и удалить?" && {
            iptables -D INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null
            iptables -D DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null
            ipset destroy abuse4 2>/dev/null; rm -f "$script" "$cron"; log "Abuse-лист удалён."
        }
        return
    fi
    echo "Abuse-фид: список IP/сетей с плохой репутацией (сканеры, брутфорсеры, спамеры)."
    echo "  1) dshield.netset — топ-20 атакующих /24 (рекомендуется)"
    echo "  2) firehol_level1.netset — жёсткая агрегация (~30k записей)"
    echo "  3) firehol_level2.netset — шире (~80k записей)"
    echo "  4) свой URL"
    local url
    case "$(ask "1-4" "1")" in
        2) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset" ;;
        3) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level2.netset" ;;
        4) url="$(ask "URL списка")" ;;
        *) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/dshield.netset" ;;
    esac
    cat > "$script" <<ABEOF
#!/usr/bin/env bash
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
    "$script" || { rm -f "$script"; die "не удалось применить фид"; }
    printf '@reboot root /opt/homeserver/abuse-block.sh\n17 4 * * * root /opt/homeserver/abuse-block.sh\n' > "$cron"
    log "Abuse-лист применён, обновление ежедневно 4:17 + @reboot"
}

block_rkn() {
    clear
    require_cmd ipset ipset
    local script=/opt/homeserver/rkn-block.sh cron=/etc/cron.d/homeserver-rkn
    if [[ -f "$script" ]]; then
        echo "Блок-лист РКН: активен"
        ask_yn "Отключить?" && { rm -f "$script" "$cron"; log "удалён"; }
        return
    fi
    cat > "$script" <<'RKNEOF'
#!/usr/bin/env bash
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
RKNEOF
    chmod +x "$script"
    "$script"
    printf '@reboot root /opt/homeserver/rkn-block.sh\n23 3 * * * root /opt/homeserver/rkn-block.sh\n' > "$cron"
    log "Блок-лист РКН применён"
}

swap_menu() {
    clear
    while true; do
        echo "${c_txt}=== Swap (подкачка) ===${c_off}"
        echo "Статус:"
        free -h | grep -i swap
        swapon --show || echo "(нет активного swap)"
        echo ""
        echo "  1. Включить swap (выбрать размер)"
        echo "  2. Отключить и удалить swap"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                local g; g=$(ask "Размер swap, ГБ" "2")
                [[ "$g" =~ ^[0-9]+$ ]] || { warn "нужно число"; continue; }
                if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapfile; then
                    swapoff /swapfile && sed -i '\|^/swapfile |d' /etc/fstab && rm -f /swapfile
                fi
                fallocate -l "${g}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((g*1024)) status=none
                chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
                grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
                echo 'vm.swappiness=10' > /etc/sysctl.d/99-homeserver-swap.conf
                sysctl -q -p /etc/sysctl.d/99-homeserver-swap.conf
                log "Swap ${g}ГБ активен" ;;
            2)
                if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapfile; then
                    swapoff /swapfile && sed -i '\|^/swapfile |d' /etc/fstab && rm -f /swapfile
                    log "Swap отключён и удалён"
                else
                    warn "Swap не активен"
                fi ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

sudo_logging_menu() {
    clear
    while true; do
        echo "${c_txt}=== Логирование sudo ===${c_off}"
        if [[ -f /etc/sudoers.d/99-homeserver-logging ]]; then
            echo "Статус: ВКЛЮЧЕНО"
            echo "Лог: /var/log/sudo.log"
            if [[ -f /var/log/sudo.log ]]; then
                echo "Последние записи:"
                tail -n 10 /var/log/sudo.log
            fi
        else
            echo "Статус: ВЫКЛЮЧЕНО"
        fi
        echo ""
        echo "  1. Включить логирование"
        echo "  2. Отключить логирование"
        echo "  3. Открыть лог в редакторе"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                cat > /etc/sudoers.d/99-homeserver-logging <<'EOF'
Defaults logfile=/var/log/sudo.log
Defaults loglinelen=0
EOF
                visudo -cf /etc/sudoers.d/99-homeserver-logging >/dev/null && log "Логирование включено" ;;
            2)
                rm -f /etc/sudoers.d/99-homeserver-logging
                log "Логирование отключено" ;;
            3)
                require_cmd nano nano
                [[ -f /var/log/sudo.log ]] && nano /var/log/sudo.log || warn "лог не найден" ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

fail2ban_menu() {
    clear
    require_cmd fail2ban-client fail2ban
    while true; do
        echo "${c_txt}=== Fail2ban ===${c_off}"
        echo "Порты и защита:"
        printf "  %-15s %-20s %s\n" "Порт" "Сервис" "Fail2ban"
        printf "  %-15s %-20s %s\n" "---" "---" "---"
        local ssh_port=$(grep "^Port " /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || echo "22")
        printf "  %-15s %-20s %s\n" "${ssh_port}/tcp" "SSH" "$(fail2ban-client status sshd 2>/dev/null | grep -q 'Currently' && echo '✔ активен' || echo 'выкл')"
        printf "  %-15s %-20s %s\n" "80,443/tcp" "nginx" "$(fail2ban-client status nginx-http-auth 2>/dev/null | grep -q 'Currently' && echo '✔ активен' || echo 'выкл')"
        echo ""
        [[ -f "$ENV_FILE" ]] && load_env
        local bantime="${F2B_BANTIME:-7200}" maxretry="${F2B_MAXRETRY:-10}" findtime="${F2B_FINDTIME:-900}"
        echo "  1. bantime (время бана): ${bantime}с = $((bantime/3600))ч"
        echo "  2. maxretry (попыток): $maxretry"
        echo "  3. findtime (окно попыток): ${findtime}с = $((findtime/60))мин"
        echo "  4. Применить и перезапустить"
        echo "  0. Назад"
        read -rp "Номер: " c || true
        case "$c" in
            1) bantime=$(ask "bantime, секунд (7200 = 2 часа)" "$bantime") ;;
            2) maxretry=$(ask "maxretry (10)" "$maxretry") ;;
            3) findtime=$(ask "findtime, секунд (900 = 15 мин)" "$findtime") ;;
            4)
                [[ -f "$ENV_FILE" ]] && {
                    update_env F2B_BANTIME "$bantime"
                    update_env F2B_MAXRETRY "$maxretry"
                    update_env F2B_FINDTIME "$findtime"
                }
                cat > /etc/fail2ban/jail.d/99-homeserver.local <<EOF
[DEFAULT]
bantime   = $bantime
findtime  = $findtime
maxretry  = $maxretry

[sshd]
enabled  = true
port     = $ssh_port
logpath  = /var/log/auth.log
EOF
                systemctl enable --now fail2ban >/dev/null 2>&1
                systemctl restart fail2ban
                log "Fail2ban перезапущен" ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

unattended_upgrades_setup() {
    clear
    echo "${c_txt}=== Автообновления (unattended-upgrades) ===${c_off}"
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
        echo "Статус: УСТАНОВЛЕНО"
        cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || echo "(нет конфига)"
        ask_yn "Отключить?" && {
            apt-get remove -y unattended-upgrades
            log "Удалено"
        }
    else
        echo "Статус: НЕ УСТАНОВЛЕНО"
        ask_yn "Установить автообновления security?" && {
            apt-get install -y unattended-upgrades
            printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
            log "Включено"
        }
    fi
}

root_mail_setup() {
    clear
    echo "${c_txt}=== Почта root (SMTP) ===${c_off}"
    if command -v msmtp >/dev/null && grep -qs "account default" /etc/msmtprc 2>/dev/null; then
        echo "Настроено:"
        grep -E '^(host|port|from):' /etc/msmtprc | sed 's/^/  /'
        ask_yn "Перенастроить?" || return
    fi
    require_cmd msmtp msmtp
    echo "Внешний SMTP для оповещений cron/unattended-upgrades"
    local host port user pass rcpt
    host=$(ask "SMTP-хост" "smtp.yandex.ru")
    port=$(ask "Порт (465/587)" "465")
    user=$(ask "Логин (email)")
    read -rsp "Пароль приложения: " pass; echo
    rcpt=$(ask "Ящик получателя" "$user")
    local starttls="off"; [[ "$port" == "587" ]] && starttls="on"
    cat > /etc/msmtprc <<EOF
defaults
auth on
tls on
tls_starttls $starttls
logfile /var/log/msmtp.log

account default
host $host
port $port
from $user
user $user
password $pass
EOF
    chmod 600 /etc/msmtprc
    printf 'root: %s\n' "$rcpt" > /etc/aliases
    log "Почта настроена: $host:$port -> $rcpt"
}

shell_history_setup() {
    clear
    echo "${c_txt}=== История shell ===${c_off}"
    cat > /etc/profile.d/99-homeserver-history.sh <<'EOF'
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
    log "История настроена: 100k записей, метки времени"
}

diag_menu() {
    clear
    echo "${c_txt}=== Диагностика VPS ===${c_off}"
    echo "  1) vps-audit (аудит защищённости)"
    echo "  2) ipregion (регион IP)"
    echo "  3) LemonBench (бенчмарк)"
    echo "  0) Назад"
    local n; n=$(ask "1-3" "")
    case "$n" in
        1) bash <(curl -fsSL https://raw.githubusercontent.com/hidden-refuge/vps-audit/main/vps-audit.sh) ;;
        2) bash <(curl -fsSL https://raw.githubusercontent.com/uxh/sh/main/ipregion.sh) ;;
        3) bash <(curl -fsSL https://raw.githubusercontent.com/LemonBench/LemonBench/main/LemonBench.sh) fast ;;
    esac
}

server_menu() {
    [[ $EUID -eq 0 ]] || { warn "нужен root"; return 1; }
    while true; do
        clear
        cat <<SUM
$(_t SRV01)
  ${c_num}1.${c_off} ${c_txt}$(_t SRV01)${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t SRV04)${c_off}
  ${c_num}3.${c_off} ${c_txt}$(_t SRV05)${c_off}
  ${c_num}4.${c_off} ${c_txt}$(_t SRV06)${c_off}
  ${c_num}5.${c_off} ${c_txt}$(_t SRV07)${c_off}
  ${c_num}6.${c_off} ${c_txt}$(_t SRV12)${c_off}
  ${c_num}7.${c_off} ${c_txt}$(_t SRV02)${c_off}
  ${c_num}8.${c_off} ${c_txt}$(_t SRV10)${c_off}
  ${c_num}9.${c_off} ${c_txt}$(_t SRV11)${c_off}
  ${c_num}10.${c_off} ${c_txt}$(_t SRV14)${c_off}
  ${c_num}11.${c_off} ${c_txt}$(_t SRV15)${c_off}
  ${c_num}12.${c_off} ${c_txt}$(_t SRV13)${c_off}
  ${c_num}13.${c_off} ${c_txt}$(_t SRV03)${c_off}
  ${c_num}14.${c_off} ${c_txt}$(_t SRV16)${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}

SUM
        read -rp "Номер: " c || true
        case "$c" in
            1) setup_timezone ;;
            2) configure_password_policy ;;
            3) create_user ;;
            4) ssh_settings_menu ;;
            5) ufw_settings_menu ;;
            6) fail2ban_menu ;;
            7) setup_network_bbr_ipv6_dns ;;
            8) swap_menu ;;
            9) sudo_logging_menu ;;
            10) root_mail_setup ;;
            11) shell_history_setup ;;
            12) unattended_upgrades_setup ;;
            13) setup_scheduled_reboot ;;
            14) diag_menu ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
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
            4) install_netdata ;;
            5) install_gitea ;;
            6) jitsi_menu ;;
            7) install_couchdb ;;
            8) install_radicale ;;
            9) install_sftpgo ;;
            10) install_syncthing ;;
            11) install_matrix ;;
            12) install_luanti ;;
            13) install_searxng ;;
            14) install_excalidraw ;;
            15) install_etherpad ;;
            16) install_mumble ;;
            17) install_classquiz ;;
            18) install_limesurvey ;;
            19) setup_backups ;;
            20) show_status ;;
            21) updates_menu ;;
            22) lang_menu ;;
            0) exit 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

# Загрузка модулей
shopt -s nullglob
mods=("$SCRIPT_DIR"/modules/*.sh)
if [[ ${#mods[@]} -eq 0 ]]; then
    die "модули не найдены: $SCRIPT_DIR/modules/*.sh"
fi
for m in "${mods[@]}"; do source "$m"; done
shopt -u nullglob

main "$@"
