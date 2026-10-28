#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

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
skip() { printf '%s\n' "$*"; }

c_mag=$'\033[1;38;5;213m'
c_num=$'\033[1;38;5;213m'
c_txt=$'\033[96m'
c_dim=$'\033[2m'
c_off=$'\033[0m'

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
        return 0
    fi
    cat <<'BAN'
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
            M02) echo "Docker" ;;
            M03) echo "nginx and certificates" ;;
            M04) echo "Netdata" ;;
            M05) echo "Gitea" ;;
            M06) echo "Jitsi Meet" ;;
            M07) echo "CouchDB" ;;
            M08) echo "Radicale" ;;
            M09) echo "SFTPGo" ;;
            M10) echo "Syncthing" ;;
            M11) echo "Matrix" ;;
            M12) echo "Luanti" ;;
            M13) echo "SearXNG" ;;
            M14) echo "Excalidraw" ;;
            M15) echo "Etherpad" ;;
            M16) echo "Mumble" ;;
            M17) echo "ClassQuiz" ;;
            M18) echo "LimeSurvey" ;;
            M19) echo "Language" ;;
            MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Exit${c_off}" ;;
            MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
            SRV00) echo "System update" ;;
            SRV01) echo "Timezone" ;;
            SRV02) echo "Password policy" ;;
            SRV03) echo "Create user" ;;
            SRV04) echo "SSH settings" ;;
            SRV05) echo "UFW settings" ;;
            SRV06) echo "Fail2ban" ;;
            SRV07) echo "BBR, IPv6, DNS settings" ;;
            SRV08) echo "Swap" ;;
            SRV09) echo "Sudo logging" ;;
            SRV10) echo "Root mail" ;;
            SRV11) echo "Shell history" ;;
            SRV12) echo "Unattended upgrades" ;;
            SRV13) echo "Scheduled reboot" ;;
            SRV14) echo "VPS diagnostics" ;;
        esac
        return
    fi
    case "$1" in
        MHDR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        M01) echo "Настройка сервера" ;;
        M02) echo "Docker" ;;
        M03) echo "nginx и сертификаты" ;;
        M04) echo "Netdata" ;;
        M05) echo "Gitea" ;;
        M06) echo "Jitsi Meet" ;;
        M07) echo "CouchDB" ;;
        M08) echo "Radicale" ;;
        M09) echo "SFTPGo" ;;
        M10) echo "Syncthing" ;;
        M11) echo "Matrix" ;;
        M12) echo "Luanti" ;;
        M13) echo "SearXNG" ;;
        M14) echo "Excalidraw" ;;
        M15) echo "Etherpad" ;;
        M16) echo "Mumble" ;;
        M17) echo "ClassQuiz" ;;
        M18) echo "LimeSurvey" ;;
        M19) echo "Язык" ;;
        MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Выход${c_off}" ;;
        MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        SRV00) echo "Обновление системы" ;;
        SRV01) echo "Часовой пояс" ;;
        SRV02) echo "Политика паролей" ;;
        SRV03) echo "Создание пользователя" ;;
        SRV04) echo "Настройки SSH" ;;
        SRV05) echo "Настройки UFW" ;;
        SRV06) echo "Fail2ban" ;;
        SRV07) echo "Настройки BBR, IPv6, DNS" ;;
        SRV08) echo "Swap" ;;
        SRV09) echo "Логирование sudo" ;;
        SRV10) echo "Почта root" ;;
        SRV11) echo "История shell" ;;
        SRV12) echo "Unattended upgrades" ;;
        SRV13) echo "Перезагрузка по расписанию" ;;
        SRV14) echo "Диагностика VPS" ;;
    esac
}

lang_menu() {
    clear
    echo "${c_txt}Язык интерфейса:${c_off}"
    echo "${c_txt} 1. Русский${c_off}"
    echo "${c_txt} 2. English${c_off}"
    local c; read -rp "1/2: " c || true
    case "$c" in 2) LANG_UI="en" ;; *) LANG_UI="ru" ;; esac
    [[ -f "$ENV_FILE" ]] && update_env LANG_UI "$LANG_UI"
    log "Язык изменён"
}

onoff() { [[ "$1" == "true" ]] && echo "вкл" || echo "выкл"; }
load_env() { set -a; source "$ENV_FILE"; set +a; }
has_forbidden() { printf '%s' "$1" | grep -q "[\"'|/\$\\& ]"; }
update_env() {
    if has_forbidden "$2"; then
        die "update_env: небезопасное значение для $1"
    fi
    if grep -q "^$1=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
    else echo "$1=$2" >> "$ENV_FILE"; fi;
}
trap 'die "сбой на строке $LINENO"' ERR

print_menu() {
    clear
    banner
    local docker_status="не установлен"
    docker compose version >/dev/null 2>&1 && docker_status="установлен"
    cat <<MENU
${c_mag}$(_t MHDR)${c_off}
  ${c_num}1.${c_off} ${c_txt}$(_t M01)${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t M02): $docker_status${c_off}
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

preflight() {
    if [[ $EUID -ne 0 ]]; then
        die "запустите от root: sudo bash $0"
    fi
    [[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || die "нужен bash >= 4"
    command -v systemctl >/dev/null 2>&1 || die "нужен systemd"
    [[ -r /etc/os-release ]] || die "не найден /etc/os-release"
    local os_id os_like
    os_id="$(. /etc/os-release && echo "$ID")"
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    case " $os_id $os_like " in
        *" debian "*|*" ubuntu "*) ;;
        *) die "поддерживаются Debian/Ubuntu" ;;
    esac
    require_cmd curl curl
    require_cmd openssl openssl
}
preflight

cd "$CONFIG_ROOT" 2>/dev/null || { mkdir -p "$CONFIG_ROOT"; cd "$CONFIG_ROOT"; }

# ---------- general helpers ----------
get_default_external_iface() {
    ip route show default 2>/dev/null | awk 'NR==1 {print $5; exit}' || true
}

is_reserved_ipv4_cidr() {
    case "$1" in
        0.0.0.0/8|10.0.0.0/8|100.64.0.0/10|127.0.0.0/8|169.254.0.0/16|172.16.0.0/12|192.0.0.0/24|192.168.0.0/16|198.18.0.0/15|224.0.0.0/4|240.0.0.0/4)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ipset_has_reserved_ranges() {
    local set_name="$1"
    ipset save "$set_name" 2>/dev/null | grep -Eq '(^|[[:space:]])(0\.0\.0\.0/8|10\.0\.0\.0/8|127\.0\.0\.0/8|169\.254\.0\.0/16|172\.16\.0\.0/12|192\.168\.0\.0/16|198\.18\.0\.0/15)([[:space:]]|$)'
}

ensure_iptables_drop_rule() {
    local set_name="$1"
    local chain="${2:-INPUT}"
    local iface="${3:-}"
    local rule=( -m set --match-set "$set_name" src -j DROP )

    if [[ -n "$iface" ]]; then
        rule=( -i "$iface" "${rule[@]}" )
    fi

    if ! iptables -C "$chain" "${rule[@]}" 2>/dev/null; then
        iptables -I "$chain" 1 "${rule[@]}" 2>/dev/null || true
    fi
}

install_cron_entry() {
    local schedule="$1"
    local command="$2"
    if ! crontab -l 2>/dev/null | grep -qF "$command"; then
        (crontab -l 2>/dev/null; echo "${schedule} ${command}") | crontab -
    fi
}

import_ipset_from_file() {
    local set_name="$1"
    local file="$2"

    ipset create "${set_name}_tmp" hash:net 2>/dev/null || true

    while IFS= read -r cidr; do
        [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
        [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || continue
        is_reserved_ipv4_cidr "$cidr" && continue
        ipset add "${set_name}_tmp" "$cidr" 2>/dev/null || true
    done < "$file"

    if ipset_has_reserved_ranges "${set_name}_tmp"; then
        warn "$set_name содержит частные/резервные CIDR — импорт отменён"
        ipset destroy "${set_name}_tmp" 2>/dev/null || true
        return 1
    fi

    ipset create "$set_name" hash:net 2>/dev/null || true
    ipset swap "${set_name}_tmp" "$set_name" 2>/dev/null || true
    ipset destroy "${set_name}_tmp" 2>/dev/null || true
    return 0
}

# ---------- server section ----------

system_update() {
    clear
    echo "${c_mag}=== Обновление системы ===${c_off}"
    echo "${c_txt}Обновление списка пакетов...${c_off}"
    apt update -y && log "apt update выполнен"
    echo "${c_txt}Обновление пакетов...${c_off}"
    apt upgrade -y && log "apt upgrade выполнен"
    echo "${c_txt}Установка базовых утилит и сервисов безопасности...${c_off}"
    apt install -y mc htop cron ipset ufw fail2ban chkrootkit rkhunter && log "Установлены: mc, htop, cron, ipset, ufw, fail2ban, chkrootkit, rkhunter"
    echo "${c_txt}Удаление ненужных пакетов...${c_off}"
    apt autoremove -y && log "apt autoremove выполнен"
    echo "${c_txt}Очистка кэша...${c_off}"
    apt autoclean -y && log "apt autoclean выполнен"
    log "Обновление системы завершено"
    read -rp "Enter — продолжить " _ || true
}

setup_timezone() {
    clear
    echo "${c_mag}=== Часовой пояс ===${c_off}"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')
    echo "${c_txt}Текущий: $current_tz${c_off}"
    echo ""
    echo "${c_txt}Популярные часовые пояса:${c_off}"
    echo "${c_txt}  Europe/Moscow       — Москва${c_off}"
    echo "${c_txt}  Europe/Kyiv         — Киев${c_off}"
    echo "${c_txt}  Europe/Minsk        — Минск${c_off}"
    echo "${c_txt}  Asia/Yekaterinburg  — Екатеринбург${c_off}"
    echo "${c_txt}  Asia/Novosibirsk    — Новосибирск${c_off}"
    echo "${c_txt}  Asia/Vladivostok    — Владивосток${c_off}"
    echo "${c_txt}  Asia/Almaty         — Алматы${c_off}"
    echo "${c_txt}  Asia/Tashkent       — Ташкент${c_off}"
    echo "${c_txt}  Europe/Berlin       — Берлин${c_off}"
    echo "${c_txt}  UTC                 — Всемирное координированное время${c_off}"
    echo ""
    local new_tz; new_tz=$(ask "Новый часовой пояс" "$current_tz")
    timedatectl set-timezone "$new_tz" && log "Установлено: $new_tz"
    read -rp "Enter — продолжить " _ || true
}

configure_password_policy() {
    clear
    echo "${c_mag}=== Политика паролей ===${c_off}"
    require_cmd pam-auth-update libpam-pwquality

    local status="выключена"
    if grep -q "pam_pwquality.so" /etc/pam.d/common-password 2>/dev/null; then
        status="включена"
    fi
    echo "${c_txt}Статус: $status${c_off}"
    echo ""
    echo "${c_txt}1. Настроить${c_off}"
    echo "${c_txt}0. Назад${c_off}"
    read -rp "Номер: " c || true
    case "$c" in
        1)
            apt-get install -y libpam-pwquality
            local pam_file="/etc/pam.d/common-password"
            sed -i '/pam_pwquality.so/d' "$pam_file"
            echo 'password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 enforce_for_root' >> "$pam_file"
            cat > /etc/security/pwquality.conf <<'EOF'
# Минимальная длина пароля
minlen = 12
# Требовать хотя бы одну заглавную букву
ucredit = -1
# Требовать хотя бы одну строчную букву
lcredit = -1
# Требовать хотя бы одну цифру
dcredit = -1
# Требовать хотя бы один специальный символ
ocredit = -1
EOF
            pam-auth-update --force
            log "Политика паролей настроена и активирована"
            log "Требования: мин. 12 символов, заглавная, строчная, цифра, спецсимвол"
            read -rp "Enter — продолжить " _ || true ;;
        0) return 0 ;;
    esac
}

create_user() {
    clear
    echo "${c_mag}=== Создание пользователя ===${c_off}"
    local username; username=$(ask "Имя пользователя" "")
    [[ -z "$username" ]] && return 0
    if id "$username" >/dev/null 2>&1; then
        warn "пользователь $username уже существует"
        read -rp "Нажмите Enter для продолжения " _ || true
    else
        useradd -m -s /bin/bash "$username"
        echo "${c_txt}Задайте пароль для пользователя $username:${c_off}"
        if passwd "$username"; then
            usermod -aG sudo "$username"
            log "Пользователь $username создан и добавлен в группу sudo"
        else
            warn "Ошибка установки пароля"
            read -rp "Нажмите Enter для продолжения " _ || true
        fi
    fi
    read -rp "Enter — продолжить " _ || true
}

get_ssh_port() {
    grep "^Port " /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || \
    grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22"
}

ensure_sshd_fragment() {
    mkdir -p /etc/ssh/sshd_config.d
    touch /etc/ssh/sshd_config.d/99-homeserver.conf
}

set_sshd_option() {
    local key="$1"
    local value="$2"
    local cfg="/etc/ssh/sshd_config.d/99-homeserver.conf"
    ensure_sshd_fragment

    if grep -Eq "^${key}[[:space:]]+" "$cfg" 2>/dev/null; then
        sed -i -E "s|^${key}[[:space:]].*|${key} ${value}|" "$cfg"
    else
        printf '%s %s\n' "$key" "$value" >> "$cfg"
    fi
}

reload_sshd_safe() {
    if sshd -t 2>/dev/null; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        return 0
    fi
    warn "Ошибка в конфигурации SSH"
    return 1
}

ssh_settings_menu() {
    local SSHD_CONFIG="/etc/ssh/sshd_config"
    local SSH_CONFIG="/etc/ssh/ssh_config"

    if [[ ! -f /etc/ssh/sshd_config.backup_wundergarden ]]; then
        cp "$SSHD_CONFIG" /etc/ssh/sshd_config.backup_wundergarden
        log "Создан бэкап: /etc/ssh/sshd_config.backup_wundergarden"
    fi

    for f in /etc/ssh/sshd_config.d/*-billpanel.conf /etc/ssh/sshd_config.d/50-cloud-init.conf; do
        [[ -f "$f" ]] && rm -f "$f" && log "Удалён конфликтующий файл: $f"
    done

    if [[ -f "$SSHD_CONFIG" ]]; then
        sed -i 's/^PermitRootLogin/#PermitRootLogin/' "$SSHD_CONFIG"
        sed -i 's/^PasswordAuthentication/#PasswordAuthentication/' "$SSHD_CONFIG"
        if grep -q '^X11Forwarding' "$SSHD_CONFIG"; then
            sed -i 's/^X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
        else
            echo "X11Forwarding no" >> "$SSHD_CONFIG"
        fi
        if grep -q '^GSSAPIAuthentication' "$SSHD_CONFIG"; then
            sed -i 's/^GSSAPIAuthentication.*/GSSAPIAuthentication no/' "$SSHD_CONFIG"
        else
            echo "GSSAPIAuthentication no" >> "$SSHD_CONFIG"
        fi
    fi

    if [[ -f "$SSH_CONFIG" ]]; then
        if grep -q '^GSSAPIAuthentication' "$SSH_CONFIG"; then
            sed -i 's/^GSSAPIAuthentication.*/GSSAPIAuthentication no/' "$SSH_CONFIG"
        else
            echo "GSSAPIAuthentication no" >> "$SSH_CONFIG"
        fi
    fi

    if [[ -f "$SSHD_CONFIG" ]] && ! grep -q '^Include /etc/ssh/sshd_config.d' "$SSHD_CONFIG"; then
        local temp_file; temp_file=$(mktemp)
        awk '
            /^#/ { print; next }
            !printed { print "Include /etc/ssh/sshd_config.d/*.conf"; print ""; printed=1 }
            { print }
        ' "$SSHD_CONFIG" > "$temp_file"
        mv "$temp_file" "$SSHD_CONFIG"
        log "Добавлена директива Include в sshd_config"
    fi

    while true; do
        clear
        local port root_login pass_auth
        port=$(get_ssh_port)
        root_login=$(grep '^PermitRootLogin' /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || echo "prohibit-password")
        pass_auth=$(grep '^PasswordAuthentication' /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || echo "yes")

        echo "${c_mag}=== Настройки SSH ===${c_off}"
        echo "${c_txt}Порт: $port${c_off}"
        echo "${c_txt}Вход root: $root_login${c_off}"
        echo "${c_txt}Вход по паролю: $pass_auth${c_off}"
        echo ""
        echo "${c_txt}1. Изменить SSH-порт${c_off}"
        echo "${c_txt}2. Добавить SSH-ключ${c_off}"
        echo "${c_txt}3. Вход по паролю: $pass_auth${c_off}"
        echo "${c_txt}4. Вход root: $root_login${c_off}"
        echo "${c_txt}5. Проверить и исправить права на ключи${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true

        case "$c" in
            1)
                require_cmd ufw ufw
                local new_port; new_port=$(ask "Новый SSH-порт" "$port")
                [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]] || { warn "некорректный порт"; continue; }

                ufw allow "$new_port/tcp" comment 'SSH' >/dev/null 2>&1 && log "UFW: порт $new_port/tcp открыт" || warn "Ошибка UFW"
                ufw reload >/dev/null 2>&1 && log "UFW перезапущен" || warn "Ошибка перезапуска UFW"
                set_sshd_option "Port" "$new_port"
                if reload_sshd_safe; then log "SSH перезапущен, порт: $new_port"; else warn "Ошибка перезапуска SSH"; fi
                read -rp "Enter — продолжить " _ || true ;;

            2)
                local username; username=$(ask "Имя пользователя" "")
                [[ -n "$username" ]] || continue
                id "$username" >/dev/null 2>&1 || { warn "пользователь не найден"; continue; }
                local user_home; user_home=$(getent passwd "$username" | cut -d: -f6)
                mkdir -p "$user_home/.ssh"
                chmod 700 "$user_home/.ssh"
                touch "$user_home/.ssh/authorized_keys"
                chmod 600 "$user_home/.ssh/authorized_keys"
                chown -R "$username:$username" "$user_home/.ssh"
                log "Создана директория $user_home/.ssh с правильными правами"

                local cfg="/etc/ssh/sshd_config.d/99-homeserver.conf"
                ensure_sshd_fragment
                if ! grep -q '^PubkeyAuthentication' "$cfg" 2>/dev/null; then
                    echo "PubkeyAuthentication yes" >> "$cfg"
                fi
                if reload_sshd_safe; then log "SSH перезапущен, аутентификация по ключу включена"; else warn "Ошибка перезапуска SSH"; fi

                local ip; ip="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || echo '<IP>')"
                local ssh_port; ssh_port=$(get_ssh_port)
                echo "${c_mag}=======================================================================================${c_off}"
                echo "${c_mag}Создайте ключ на своём компьютере:${c_off}"
                echo "${c_txt}ssh-keygen -t ed25519${c_off}"
                echo ""
                echo "${c_mag}Загрузите ключ на сервер (Linux):${c_off}"
                echo "${c_txt}ssh-copy-id -i ~/.ssh/имяключа.pub -p $ssh_port $username@$ip${c_off}"
                echo ""
                echo "${c_mag}Команда для Windows (PowerShell):${c_off}"
                echo "${c_txt}type \$env:USERPROFILE\\.ssh\\имяключа.pub | ssh -p $ssh_port $username@$ip \"cat >> ~/.ssh/authorized_keys\"${c_off}"
                echo ""
                echo "${c_mag}Проверьте вход ключом:${c_off}"
                echo "${c_txt}ssh -i ~/.ssh/имяключа -p $ssh_port $username@$ip${c_off}"
                echo ""
                echo "${c_mag}ВАЖНО: После успешного входа ключом вернитесь в меню и выберите${c_off}"
                echo "${c_mag}пункт 3 'Вход по паролю' для отключения входа по паролю.${c_off}"
                echo "${c_mag}=======================================================================================${c_off}"
                read -rp "Enter — продолжить " _ || true ;;

            3)
                local cfg="/etc/ssh/sshd_config.d/99-homeserver.conf"
                ensure_sshd_fragment
                local new_pass_auth; new_pass_auth="$( [[ "$pass_auth" == "yes" ]] && echo no || echo yes )"
                set_sshd_option "PasswordAuthentication" "$new_pass_auth"
                if reload_sshd_safe; then log "Вход по паролю $( [[ "$new_pass_auth" == "no" ]] && echo 'отключён' || echo 'включён' ), SSH перезапущен"; else warn "Ошибка перезапуска SSH"; fi
                read -rp "Enter — продолжить " _ || true ;;

            4)
                local cfg="/etc/ssh/sshd_config.d/99-homeserver.conf"
                ensure_sshd_fragment
                echo "${c_txt}1. yes — разрешён${c_off}"
                echo "${c_txt}2. no — запрещён${c_off}"
                echo "${c_txt}3. prohibit-password — только по ключу${c_off}"
                local choice; choice=$(ask "Выберите" "3")
                case "$choice" in
                    1) new_val="yes" ;;
                    2) new_val="no" ;;
                    *) new_val="prohibit-password" ;;
                esac
                set_sshd_option "PermitRootLogin" "$new_val"
                if reload_sshd_safe; then log "PermitRootLogin установлен в $new_val, SSH перезапущен"; else warn "Ошибка перезапуска SSH"; fi
                read -rp "Enter — продолжить " _ || true ;;

            5)
                echo "${c_mag}=== Проверка и исправление прав на SSH-ключи ===${c_off}"
                echo ""
                local users; users=$(awk -F: '$3 >= 1000 && $3 < 65000 {print $1":"$6}' /etc/passwd)
                if [[ -z "$users" ]]; then
                    warn "Не найдено пользователей с UID >= 1000"
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi

                local fixed_count=0
                while IFS=: read -r username user_home; do
                    echo "${c_txt}Проверка пользователя: $username${c_off}"
                    if [[ ! -d "$user_home/.ssh" ]]; then
                        echo "  ${c_txt}⚠ Директория .ssh отсутствует${c_off}"
                        continue
                    fi

                    local ssh_perms; ssh_perms=$(stat -c "%a" "$user_home/.ssh" 2>/dev/null)
                    if [[ "$ssh_perms" != "700" ]]; then
                        echo "  ${c_txt}⚠ Неправильные права на .ssh: $ssh_perms (должно быть 700)${c_off}"
                        chmod 700 "$user_home/.ssh"
                        echo "  ${c_txt}✓ Исправлено на 700${c_off}"
                        ((fixed_count++))
                    else
                        echo "  ${c_txt}✓ Права на .ssh корректны (700)${c_off}"
                    fi

                    local ssh_owner; ssh_owner=$(stat -c "%U:%G" "$user_home/.ssh" 2>/dev/null)
                    if [[ "$ssh_owner" != "$username:$username" ]]; then
                        echo "  ${c_txt}⚠ Неправильный владелец .ssh: $ssh_owner (должно быть $username:$username)${c_off}"
                        chown -R "$username:$username" "$user_home/.ssh"
                        echo "  ${c_txt}✓ Владелец исправлен${c_off}"
                        ((fixed_count++))
                    else
                        echo "  ${c_txt}✓ Владелец .ssh корректен${c_off}"
                    fi

                    if [[ -f "$user_home/.ssh/authorized_keys" ]]; then
                        local key_perms; key_perms=$(stat -c "%a" "$user_home/.ssh/authorized_keys" 2>/dev/null)
                        if [[ "$key_perms" != "600" ]]; then
                            echo "  ${c_txt}⚠ Неправильные права на authorized_keys: $key_perms (должно быть 600)${c_off}"
                            chmod 600 "$user_home/.ssh/authorized_keys"
                            echo "  ${c_txt}✓ Исправлено на 600${c_off}"
                            ((fixed_count++))
                        else
                            echo "  ${c_txt}✓ Права на authorized_keys корректны (600)${c_off}"
                        fi

                        local key_owner; key_owner=$(stat -c "%U:%G" "$user_home/.ssh/authorized_keys" 2>/dev/null)
                        if [[ "$key_owner" != "$username:$username" ]]; then
                            echo "  ${c_txt}⚠ Неправильный владелец authorized_keys: $key_owner${c_off}"
                            chown "$username:$username" "$user_home/.ssh/authorized_keys"
                            echo "  ${c_txt}✓ Владелец исправлен${c_off}"
                            ((fixed_count++))
                        else
                            echo "  ${c_txt}✓ Владелец authorized_keys корректен${c_off}"
                        fi

                        local key_count; key_count=$(wc -l < "$user_home/.ssh/authorized_keys" 2>/dev/null | tr -d ' ')
                        echo "  ${c_txt}ℹ Количество ключей: $key_count${c_off}"
                    else
                        echo "  ${c_txt}⚠ Файл authorized_keys отсутствует${c_off}"
                    fi

                    echo ""
                done <<< "$users"

                if [[ $fixed_count -gt 0 ]]; then
                    log "Исправлено проблем: $fixed_count"
                    log "Перезапустите SSH для применения изменений"
                else
                    log "Все права на SSH-ключи корректны"
                fi
                read -rp "Enter — продолжить " _ || true ;;

            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

change_ssh_port_direct() {
    clear
    require_cmd ufw ufw
    local port; port=$(get_ssh_port)
    echo "${c_mag}=== Изменить SSH-порт ===${c_off}"
    echo "${c_txt}Текущий порт: $port${c_off}"
    local new_port; new_port=$(ask "Новый SSH-порт" "$port")
    [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]] || { warn "некорректный порт"; return; }

    ufw allow "$new_port/tcp" comment 'SSH' >/dev/null 2>&1 && log "UFW: порт $new_port/tcp открыт" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1 && log "UFW перезапущен" || warn "Ошибка перезапуска UFW"
    set_sshd_option "Port" "$new_port"
    if reload_sshd_safe; then log "SSH перезапущен, порт: $new_port"; else warn "Ошибка перезапуска SSH"; fi
    read -rp "Enter — продолжить " _ || true
}

ufw_settings_menu() {
    require_cmd ufw ufw
    while true; do
        clear
        local status; status=$(ufw status | head -1 | awk '{print $2}')
        local port; port=$(get_ssh_port)
        local abuse_status="выкл"; [[ -f /opt/homeserver/abuse-block.sh ]] && abuse_status="вкл"
        local rkn_status="выкл"; [[ -f "$CONFIG_ROOT/rkn-block.sh" ]] && rkn_status="вкл"

        echo "${c_mag}=== Настройки UFW ===${c_off}"
        echo "${c_txt}Статус: $status${c_off}"
        echo "${c_txt}SSH-порт: $port${c_off}"
        echo "${c_txt}Блокировка ботов: $abuse_status${c_off}"
        echo "${c_txt}Блокировка РКН: $rkn_status${c_off}"
        echo ""
        echo "${c_txt}1. Включить/отключить UFW${c_off}"
        echo "${c_txt}2. Изменить SSH-порт${c_off}"
        echo "${c_txt}3. Блокировка ботов${c_off}"
        echo "${c_txt}4. Блокировка РКН${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true

        case "$c" in
            1)
                if ufw status | grep -q "Status: active"; then
                    ufw disable && log "UFW отключён"
                else
                    ufw --force enable && log "UFW включён"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            2) change_ssh_port_direct ;;
            3) abuse_block_setup || true ;;
            4) block_rkn || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

abuse_block_setup() {
    clear
    require_cmd ipset ipset
    local script=/opt/homeserver/abuse-block.sh
    local cron=/etc/cron.d/homeserver-abuse

    if [[ -f "$script" ]]; then
        echo "${c_mag}=== Блокировка ботов ===${c_off}"
        echo "${c_txt}Статус: активен ($(ipset list abuse4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей)${c_off}"
        if ask_yn "Отключить?"; then
            iptables -D INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null || true
            iptables -D DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null || true
            ipset destroy abuse4 2>/dev/null || true
            rm -f "$script" "$cron"
            log "Удалён"
        fi
        read -rp "Enter — продолжить " _ || true
        return 0
    fi

    echo "${c_mag}=== Блокировка ботов ===${c_off}"
    echo "${c_txt}1) dshield.netset — топ-20 атакующих${c_off}"
    echo "${c_txt}2) firehol_level1.netset — жёсткая агрегация${c_off}"
    echo "${c_txt}3) firehol_level2.netset — шире${c_off}"

    local url
    case "$(ask "1-3" "1")" in
        2) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset" ;;
        3) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level2.netset" ;;
        *) url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/dshield.netset" ;;
    esac

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
URL="$url"
TMP="
");
EOF

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
URL="$url"
TMP="
");
EOF

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
URL="$url"
TMP="
");
EOF

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
URL="$url"
TMP="
");
EOF

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
URL="$url"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

get_default_external_iface() {
    ip route show default 2>/dev/null | awk 'NR==1 {print \$5; exit}' || true
}

is_reserved_ipv4_cidr() {
    case "\$1" in
        0.0.0.0/8|10.0.0.0/8|100.64.0.0/10|127.0.0.0/8|169.254.0.0/16|172.16.0.0/12|192.0.0.0/24|192.168.0.0/16|198.18.0.0/15|224.0.0.0/4|240.0.0.0/4)
            return 0 ;;
        *) return 1 ;;
    esac
}

curl -fsSL --max-time 300 "\$URL" -o "\$TMP" || { echo "Ошибка загрузки"; exit 1; }

ipset create abuse4_tmp hash:net 2>/dev/null || true
while IFS= read -r cidr; do
    [[ -z "\$cidr" || "\$cidr" =~ ^# ]] && continue
    [[ "\$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || continue
    is_reserved_ipv4_cidr "\$cidr" && continue
    ipset add abuse4_tmp "\$cidr" 2>/dev/null || true
done < "\$TMP"

if ipset save abuse4_tmp 2>/dev/null | grep -Eq '(^|[[:space:]])(0\.0\.0\.0/8|10\.0\.0\.0/8|127\.0\.0\.0/8|169\.254\.0\.0/16|172\.16\.0\.0/12|192\.168\.0\.0/16|198\.18\.0\.0/15)([[:space:]]|$)'; then
    echo "abuse4 содержит частные/резервные CIDR — загрузка отменена"
    ipset destroy abuse4_tmp 2>/dev/null || true
    exit 1
fi

ipset create abuse4 hash:net 2>/dev/null || true
ipset swap abuse4_tmp abuse4 2>/dev/null || true
ipset destroy abuse4_tmp 2>/dev/null || true

iface="\$(get_default_external_iface)"
if [[ -n "\$iface" ]]; then
    iptables -C INPUT -i "\$iface" -m set --match-set abuse4 src -j DROP 2>/dev/null || \
    iptables -I INPUT 1 -i "\$iface" -m set --match-set abuse4 src -j DROP 2>/dev/null || true
else
    iptables -C INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null || \
    iptables -I INPUT 1 -m set --match-set abuse4 src -j DROP 2>/dev/null || true
fi

iptables -C DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null || \
iptables -I DOCKER-USER 1 -m set --match-set abuse4 src -j DROP 2>/dev/null || true
EOF

    chmod +x "$script"

    if "$script"; then
        printf '@reboot root /opt/homeserver/abuse-block.sh\n17 4 * * * root /opt/homeserver/abuse-block.sh\n' > "$cron"
        log "Применён"
        require_cmd ufw ufw
        ufw reload >/dev/null 2>&1 && log "UFW перезапущен"
    else
        rm -f "$script"
        warn "Ошибка применения"
        read -rp "Enter — продолжить " _ || true
        return 1
    fi

    read -rp "Enter — продолжить " _ || true
    return 0
}

block_rkn() {
    clear
    require_cmd ipset ipset
    require_cmd wget wget
    require_cmd crontab cron

    echo "${c_mag}=== Блокировка IP-адресов РКН ===${c_off}"
    echo "${c_txt}Источник: github.com/C24Be/AS_Network_List${c_off}"

    local script="$CONFIG_ROOT/rkn-block.sh"
    cat > "$script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd /opt/homeserver
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

get_default_external_iface() {
    ip route show default 2>/dev/null | awk 'NR==1 {print $5; exit}' || true
}

is_reserved_ipv4_cidr() {
    case "$1" in
        0.0.0.0/8|10.0.0.0/8|100.64.0.0/10|127.0.0.0/8|169.254.0.0/16|172.16.0.0/12|192.0.0.0/24|192.168.0.0/16|198.18.0.0/15|224.0.0.0/4|240.0.0.0/4)
            return 0 ;;
        *) return 1 ;;
    esac
}

wget -q -O "$TMP" https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist.txt || {
    echo "Ошибка загрузки blacklist.txt"
    exit 1
}

ipset create rkn4_tmp hash:net 2>/dev/null || true
count=0
while IFS= read -r subnet; do
    [[ -z "$subnet" || "$subnet" =~ ^# ]] && continue
    [[ "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || continue
    is_reserved_ipv4_cidr "$subnet" && continue
    ipset add rkn4_tmp "$subnet" 2>/dev/null || true
    ((count++)) || true
done < "$TMP"

echo "Загружено подсетей: $count"

if ipset save rkn4_tmp 2>/dev/null | grep -Eq '(^|[[:space:]])(0\.0\.0\.0/8|10\.0\.0\.0/8|127\.0\.0\.0/8|169\.254\.0\.0/16|172\.16\.0\.0/12|192\.168\.0\.0/16|198\.18\.0\.0/15)([[:space:]]|$)'; then
    echo "rkn4 содержит частные/резервные CIDR — загрузка отменена"
    ipset destroy rkn4_tmp 2>/dev/null || true
    exit 1
fi

ipset create rkn4 hash:net 2>/dev/null || true
ipset swap rkn4_tmp rkn4 2>/dev/null || true
ipset destroy rkn4_tmp 2>/dev/null || true

iface="$(get_default_external_iface)"
if [[ -n "$iface" ]]; then
    iptables -C INPUT -i "$iface" -m set --match-set rkn4 src -j DROP 2>/dev/null || \
    iptables -I INPUT 1 -i "$iface" -m set --match-set rkn4 src -j DROP 2>/dev/null || true
else
    iptables -C INPUT -m set --match-set rkn4 src -j DROP 2>/dev/null || \
    iptables -I INPUT 1 -m set --match-set rkn4 src -j DROP 2>/dev/null || true
fi

iptables -C DOCKER-USER -m set --match-set rkn4 src -j DROP 2>/dev/null || \
iptables -I DOCKER-USER 1 -m set --match-set rkn4 src -j DROP 2>/dev/null || true

echo "Готово!"
EOF

    chmod +x "$script"

    echo "${c_txt}Запускаем rkn-block.sh...${c_off}"
    if "$script"; then
        log "Блокировка РКН применена (ipset)"
    else
        warn "Ошибка применения блокировки"
        rm -f "$script"
        read -rp "Enter — прод��лжить " _ || true
        return 1
    fi

    install_cron_entry "0 3 * * *" "$script"
    log "Задание добавлено в crontab для ежедневного выполнения в 3:00"

    require_cmd ufw ufw
    ufw reload >/dev/null 2>&1 && log "UFW перезапущен"

    log "Блокировка РКН через ipset завершена!"
    read -rp "Enter — продолжить " _ || true
    return 0
}

swap_menu() {
    while true; do
        clear
        echo "${c_mag}=== Swap ===${c_off}"
        echo "${c_txt}Статус:${c_off}"
        free -h | grep -i swap
        swapon --show || echo "${c_txt}(нет активного swap)${c_off}"
        echo ""
        echo "${c_txt}1. Включить swap${c_off}"
        echo "${c_txt}2. Отключить и удалить swap${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                local g; g=$(ask "Размер swap, ГБ" "1")
                [[ "$g" =~ ^[0-9]+$ ]] || { warn "нужно число"; read -rp "Нажмите Enter для продолжения " _ || true; continue; }
                if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapfile; then
                    swapoff /swapfile && sed -i '\|^/swapfile |d' /etc/fstab && rm -f /swapfile
                fi
                fallocate -l "${g}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((g*1024)) status=none
                chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
                grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
                log "Swap ${g}ГБ активен"
                read -rp "Enter — продолжить " _ || true ;;
            2)
                if swapon --show=NAME --noheadings 2>/dev/null | grep -q /swapfile; then
                    swapoff /swapfile && sed -i '\|^/swapfile |d' /etc/fstab && rm -f /swapfile
                    log "Swap отключён"
                else
                    warn "Swap не активен"
                    read -rp "Нажмите Enter для продолжения " _ || true
                fi
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Нажмите Enter для продолжения " _ || true ;;
        esac
    done
}

sudo_logging_menu() {
    while true; do
        clear
        echo "${c_mag}=== Логирование sudo ===${c_off}"
        if grep -q "^Defaults.*logfile" /etc/sudoers 2>/dev/null; then
            echo "${c_txt}Статус: включено${c_off}"
            if [[ -f /var/log/sudo.log ]]; then
                echo "${c_txt}Последние записи:${c_off}"
                tail -n 5 /var/log/sudo.log
            else
                echo "${c_txt}Лог пока пуст${c_off}"
                echo "${c_txt}Файл лога будет создан: /var/log/sudo.log${c_off}"
                if ask_yn "Сделать тестовую запись?"; then
                    sudo echo "Тестовая запись sudo - $(date)" >> /var/log/sudo.log
                    log "Тестовая запись сделана в /var/log/sudo.log"
                fi
            fi
        else
            echo "${c_txt}Статус: выключено${c_off}"
        fi
        echo ""
        echo "${c_txt}1. Включить${c_off}"
        echo "${c_txt}2. Отключить${c_off}"
        echo "${c_txt}3. Открыть лог${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                if ! grep -q "^Defaults.*logfile.*sudo.log" /etc/sudoers 2>/dev/null; then
                    echo 'Defaults logfile="/var/log/sudo.log"' >> /etc/sudoers
                    if visudo -cf /etc/sudoers >/dev/null; then
                        touch /var/log/sudo.log
                        chmod 600 /var/log/sudo.log
                        log "Логирование sudo включено"
                        log "Файл лога: /var/log/sudo.log"
                    else
                        warn "Ошибка в конфигурации sudoers, откат изменений"
                        read -rp "Нажмите Enter для продолжения " _ || true
                        sed -i '/^Defaults.*logfile.*sudo.log/d' /etc/sudoers
                    fi
                else
                    log "Логирование sudo включено"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            2)
                if grep -q "^Defaults.*logfile.*sudo.log" /etc/sudoers 2>/dev/null; then
                    sed -i '/^Defaults.*logfile.*sudo.log/d' /etc/sudoers
                    if visudo -cf /etc/sudoers >/dev/null; then
                        log "Логирование sudo отключено"
                    else
                        warn "Ошибка в конфигурации sudoers"
                        read -rp "Нажмите Enter для продолжения " _ || true
                    fi
                else
                    log "Логирование sudo отключено"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            3)
                require_cmd nano nano
                if [[ -f /var/log/sudo.log ]]; then
                    nano /var/log/sudo.log
                else
                    echo "${c_txt}Файл лога не найден: /var/log/sudo.log${c_off}"
                    echo "${c_txt}Логирование sudo не включено или записей ещё не было${c_off}"
                    if ask_yn "Включить логирование sudo?"; then
                        if ! grep -q "^Defaults.*logfile.*sudo.log" /etc/sudoers 2>/dev/null; then
                            echo 'Defaults logfile="/var/log/sudo.log"' >> /etc/sudoers
                            if visudo -cf /etc/sudoers >/dev/null; then
                                touch /var/log/sudo.log
                                chmod 600 /var/log/sudo.log
                                log "Логирование sudo включено"
                                log "Файл лога: /var/log/sudo.log"
                            else
                                warn "Ошибка в конфигурации sudoers"
                                read -rp "Нажмите Enter для продолжения " _ || true
                            fi
                        else
                            log "Логирование sudo уже включено"
                        fi
                    fi
                    read -rp "Enter — продолжить " _ || true
                fi ;;
            0) return 0 ;;
            *) warn "нет такого пункта"; read -rp "Нажмите Enter для продолжения " _ || true ;;
        esac
    done
}

fail2ban_menu() {
    require_cmd fail2ban-client fail2ban
    local jail_file="/etc/fail2ban/jail.local"

    while true; do
        clear
        local f2b_status; f2b_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
        local bantime="3600" maxretry="5" findtime="600" current_ports=""
        if [[ -f "$jail_file" ]]; then
            bantime=$(grep -E "^bantime\s*=" "$jail_file" | head -n 1 | cut -d'=' -f2 | tr -d ' ' || echo "3600")
            maxretry=$(grep -E "^maxretry\s*=" "$jail_file" | head -n 1 | cut -d'=' -f2 | tr -d ' ' || echo "5")
            findtime=$(grep -E "^findtime\s*=" "$jail_file" | head -n 1 | cut -d'=' -f2 | tr -d ' ' || echo "600")
            current_ports=$(grep -E "^port\s*=" "$jail_file" | head -n 1 | cut -d'=' -f2 | tr -d ' ' || echo "")
        fi

        echo "${c_mag}=== Fail2ban ===${c_off}"
        if [[ -f "$jail_file" && "$f2b_status" == "active" ]]; then
            echo "${c_txt}Статус: настроен и активен${c_off}"
        elif [[ -f "$jail_file" ]]; then
            echo "${c_txt}Статус: настроен, но не активен${c_off}"
        else
            echo "${c_txt}Статус: не настроен (выполните пункт 1)${c_off}"
        fi
        echo ""
        echo "${c_txt}Порты, используемые приложениями:${c_off}"

        require_cmd ss iproute2
        local listening_ports; listening_ports=$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep -oE '[0-9]+$' | sort -un)

        if [[ -n "$listening_ports" ]]; then
            printf "  %-15s %s\n" "Порт" "Процесс"
            printf "  %-15s %s\n" "---" "---"
            for port in $listening_ports; do
                local process; process=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'users:\(\("\K[^"]+' | head -1 || echo "unknown")
                printf "  %-15s %s\n" "${port}/tcp" "$process"
            done
        else
            echo "${c_txt}  (нет слушающих портов)${c_off}"
        fi

        echo ""
        echo "${c_txt}Текущие настройки:${c_off}"
        echo "${c_txt}  bantime: ${bantime}с${c_off}"
        echo "${c_txt}  maxretry: $maxretry${c_off}"
        echo "${c_txt}  findtime: ${findtime}с${c_off}"
        if [[ -n "$current_ports" ]]; then
            echo "${c_txt}  защищённые порты: $current_ports${c_off}"
        fi
        echo ""
        echo "${c_txt}1. Установить/переустановить Fail2ban${c_off}"
        echo "${c_txt}2. Изменить порты для защиты${c_off}"
        echo "${c_txt}3. Изменить bantime${c_off}"
        echo "${c_txt}4. Изменить maxretry${c_off}"
        echo "${c_txt}5. Изменить findtime${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true

        case "$c" in
            1)
                local ssh_port; ssh_port=$(get_ssh_port)
                echo "${c_txt}Текущий порт SSH: $ssh_port${c_off}"
                local ports_input; ports_input=$(ask "Введите порты для защиты через запятую (например, $ssh_port,80,443)" "$ssh_port")
                local maxretry_input; maxretry_input=$(ask "Введите максимальное число неудачных попыток (maxretry)" "5")
                local bantime_input; bantime_input=$(ask "Введите время блокировки в секундах (bantime)" "3600")
                cat > "$jail_file" <<-JAIL_EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = $bantime_input
findtime = 600
maxretry = $maxretry_input

[sshd]
enabled = true
port = $ports_input
filter = sshd
logpath = /var/log/auth.log
maxretry = $maxretry_input
JAIL_EOF
                systemctl enable fail2ban
                systemctl restart fail2ban
                log "Fail2ban установлен и настроен на порты: $ports_input"
                read -rp "Enter — продолжить " _ || true ;;
            2)
                if [[ ! -f "$jail_file" ]]; then
                    warn "Fail2ban не установлен. Сначала выполните пункт 1"
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi
                echo "${c_txt}Текущие порты: ${current_ports:-не указаны}${c_off}"
                local new_ports; new_ports=$(ask "Введите новые порты для защиты через запятую (например, 2222,80,443)" "")
                if [[ -z "$new_ports" ]]; then
                    warn "Ввод пустой, изменения отменены"
                    read -rp "Нажмите Enter для продолжения " _ || true
                else
                    if grep -q "^port\s*=" "$jail_file"; then
                        sed -i "s/^port\s*=.*/port = $new_ports/" "$jail_file"
                    else
                        sed -i "/^\[sshd\]/,/^\[/ s/enabled = true/enabled = true\nport = $new_ports/" "$jail_file"
                    fi
                    systemctl restart fail2ban
                    log "Порты обновлены на: $new_ports. Fail2ban перезапущен"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            3)
                if [[ ! -f "$jail_file" ]]; then
                    warn "Fail2ban не установлен. Сначала выполните пункт 1"
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi
                local new_bantime; new_bantime=$(ask "Введите bantime в секундах" "$bantime")
                if grep -q "^bantime\s*=" "$jail_file"; then
                    sed -i "s/^bantime\s*=.*/bantime = $new_bantime/" "$jail_file"
                fi
                systemctl restart fail2ban
                log "bantime обновлён на: $new_bantime"
                read -rp "Enter — продолжить " _ || true ;;
            4)
                if [[ ! -f "$jail_file" ]]; then
                    warn "Fail2ban не установлен. Сначала выполните пункт 1"
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi
                local new_maxretry; new_maxretry=$(ask "Введите maxretry" "$maxretry")
                if grep -q "^maxretry\s*=" "$jail_file"; then
                    sed -i "s/^maxretry\s*=.*/maxretry = $new_maxretry/" "$jail_file"
                fi
                systemctl restart fail2ban
                log "maxretry обновлён на: $new_maxretry"
                read -rp "Enter — продолжить " _ || true ;;
            5)
                if [[ ! -f "$jail_file" ]]; then
                    warn "Fail2ban не установлен. Сначала выполните пункт 1"
                    read -rp "Enter — продолжить " _ || true
                    continue
                fi
                local new_findtime; new_findtime=$(ask "Введите findtime в секундах" "$findtime")
                if grep -q "^findtime\s*=" "$jail_file"; then
                    sed -i "s/^findtime\s*=.*/findtime = $new_findtime/" "$jail_file"
                fi
                systemctl restart fail2ban
                log "findtime обновлён на: $new_findtime"
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

setup_dns_netplan() {
    clear
    echo "${c_mag}=== Настройка DNS (netplan + systemd-resolved) ===${c_off}"

    require_cmd python3 python3
    require_cmd netplan netplan.io
    if ! python3 -c 'import yaml' 2>/dev/null; then
        warn "Нужен python3-yaml"
        apt-get install -y python3-yaml
    fi

    if ! systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        die "systemd-resolved не найден"
    fi

    local NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
    [[ -f "$NETPLAN_FILE" ]] || { warn "Не найден $NETPLAN_FILE"; read -rp "Нажмите Enter для продолжения " _ || true; return 1; }

    local DNS_SERVERS=(1.1.1.1 9.9.9.9 8.8.8.8)
    local SEARCH_DOMAINS=(netgrid.host)
    local RESOLVED_DROPIN_DIR="/etc/systemd/resolved.conf.d"
    local RESOLVED_DROPIN="${RESOLVED_DROPIN_DIR}/10-dns.conf"
    local CLOUD_INIT_NET_DISABLE="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
    local RESOLV_TARGET="/run/systemd/resolve/resolv.conf"
    local BACKUP_DIR="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"
    local BACKUP_DONE=0
    local NETPLAN_CHANGED=0
    local RESOLVED_CHANGED=0

    backup() {
        if [[ $BACKUP_DONE -eq 1 ]]; then return 0; fi
        log "Бэкап в $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        cp -a /etc/netplan "$BACKUP_DIR/netplan"
        [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] && cp -a /etc/resolv.conf "$BACKUP_DIR/resolv.conf"
        [[ -d "$RESOLVED_DROPIN_DIR" ]] && cp -a "$RESOLVED_DROPIN_DIR" "$BACKUP_DIR/resolved.conf.d"
        [[ -f "$CLOUD_INIT_NET_DISABLE" ]] && cp -a "$CLOUD_INIT_NET_DISABLE" "$BACKUP_DIR/99-disable-network-config.cfg"
        BACKUP_DONE=1
    }

    local DROPIN_CONTENT="[Resolve]
DNS=${DNS_SERVERS[*]}
LLMNR=no
MulticastDNS=no"

    if [[ -f "$RESOLVED_DROPIN" && "$(cat "$RESOLVED_DROPIN")" == "$DROPIN_CONTENT" ]]; then
        skip "$RESOLVED_DROPIN без изменений"
    else
        backup
        log "Пишу $RESOLVED_DROPIN"
        mkdir -p "$RESOLVED_DROPIN_DIR"
        printf '%s\n' "$DROPIN_CONTENT" > "$RESOLVED_DROPIN"
        chmod 644 "$RESOLVED_DROPIN"
        RESOLVED_CHANGED=1
    fi

    local TMP_NETPLAN; TMP_NETPLAN=$(mktemp)
    local RESULT
    RESULT=$(python3 - "$NETPLAN_FILE" "$TMP_NETPLAN" "${DNS_SERVERS[*]}" "${SEARCH_DOMAINS[*]}" <<'PY'
import sys, copy, yaml
path, out, dns, search = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4].split()
with open(path) as f:
    data = yaml.safe_load(f)
orig = copy.deepcopy(data)
net = data.setdefault("network", {})
for section in ("ethernets", "bonds", "bridges", "vlans"):
    for name, cfg in (net.get(section) or {}).items():
        if not isinstance(cfg, dict):
            continue
        if "nameservers" in cfg or "addresses" in cfg:
            ns = cfg.get("nameservers")
            if not isinstance(ns, dict):
                ns = {}
            cfg["nameservers"] = ns
            ns["addresses"] = list(dns)
            cur = ns.get("search") or []
            if isinstance(cur, str):
                cur = [cur]
            merged = list(cur) + [d for d in search if d not in cur]
            if merged:
                ns["search"] = merged
if data == orig:
    print("UNCHANGED")
else:
    with open(out, "w") as f:
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print("CHANGED")
PY
)

    if [[ "$RESULT" == "CHANGED" ]]; then
        backup
        log "Обновляю $NETPLAN_FILE"
        local MODE; MODE=$(stat -c '%a' "$NETPLAN_FILE")
        cp "$TMP_NETPLAN" "$NETPLAN_FILE"
        chmod "$MODE" "$NETPLAN_FILE"
        NETPLAN_CHANGED=1
    else
        skip "$NETPLAN_FILE без изменений"
    fi
    chmod 600 /etc/netplan/*.yaml 2>/dev/null || true
    rm -f "$TMP_NETPLAN"

    local CI_CONTENT="network: {config: disabled}"
    if [[ -d /etc/cloud/cloud.cfg.d ]]; then
        if [[ -f "$CLOUD_INIT_NET_DISABLE" && "$(cat "$CLOUD_INIT_NET_DISABLE")" == "$CI_CONTENT" ]]; then
            skip "cloud-init уже не управляет сетью"
        else
            backup
            log "Отключаю управление сетью в cloud-init"
            printf '%s\n' "$CI_CONTENT" > "$CLOUD_INIT_NET_DISABLE"
        fi
    fi

    if [[ -L /etc/resolv.conf && "$(readlink /etc/resolv.conf)" == "$RESOLV_TARGET" ]]; then
        skip "/etc/resolv.conf уже указывает на $RESOLV_TARGET"
    else
        backup
        log "Настраиваю /etc/resolv.conf"
        ln -sfn "$RESOLV_TARGET" /etc/resolv.conf
        RESOLVED_CHANGED=1
    fi

    if [[ $NETPLAN_CHANGED -eq 1 ]]; then
        log "netplan generate"
        if ! netplan generate; then
            cp -a "$BACKUP_DIR/netplan/." /etc/netplan/
            warn "netplan generate не прошёл, netplan-файлы восстановлены из $BACKUP_DIR"
            read -rp "Нажмите Enter для продолжения " _ || true
            return 1
        fi
        log "netplan apply"
        netplan apply
        RESOLVED_CHANGED=1
    fi

    if [[ $RESOLVED_CHANGED -eq 1 ]]; then
        log "Перезапуск systemd-resolved"
        systemctl enable systemd-resolved >/dev/null 2>&1 || true
        systemctl restart systemd-resolved
        sleep 2
    else
        skip "Применение не требуется"
    fi

    echo ""
    echo "${c_txt}===== netplan: nameservers =====${c_off}"
    grep -A8 'nameservers:' "$NETPLAN_FILE" || true
    echo ""
    echo "${c_txt}===== /etc/resolv.conf (без комментариев) =====${c_off}"
    grep -v '^#' /etc/resolv.conf | sed '/^$/d'
    echo ""
    echo "${c_txt}===== resolvectl status =====${c_off}"
    resolvectl status | grep -E 'Global|Link|Protocols|DNS Servers|DNS Domain' || true
    echo ""
    echo "${c_txt}===== Порты 5353/5355 (должно быть пусто) =====${c_off}"
    ss -tulpn | grep -E ':(5353|5355)\b' || echo "OK: LLMNR/mDNS не слушают"
    echo ""
    echo "${c_txt}===== Тест резолва =====${c_off}"
    resolvectl query debian.org || true

    [[ $BACKUP_DONE -eq 1 ]] && log "Бэкап: $BACKUP_DIR" || true
}

setup_network_bbr_ipv6_dns() {
    while true; do
        clear
        echo "${c_mag}=== Настройки BBR, IPv6, DNS ===${c_off}"
        echo "${c_txt}BBR: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')${c_off}"
        echo "${c_txt}IPv6: $([ -f /etc/sysctl.d/99-homeserver-ipv6.conf ] && echo 'отключён' || echo 'включён')${c_off}"
        echo "${c_txt}DNS: $([ -f /etc/systemd/resolved.conf.d/99-homeserver.conf ] && echo 'настроен' || echo 'не настроен')${c_off}"
        if [[ -f /etc/resolv.conf ]]; then
            echo "${c_txt}Текущие nameservers:${c_off}"
            grep "^nameserver" /etc/resolv.conf | sed 's/^/  /'
        fi
        echo ""
        echo "${c_txt}1. BBR${c_off}"
        echo "${c_txt}2. IPv6${c_off}"
        echo "${c_txt}3. Настройки DNS${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true

        case "$c" in
            1)
                if ! modprobe tcp_bbr 2>/dev/null; then warn "модуль tcp_bbr недоступен"; continue; fi
                printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-homeserver-bbr.conf
                sysctl -q -p /etc/sysctl.d/99-homeserver-bbr.conf
                log "BBR включён"
                read -rp "Enter — продолжить " _ || true ;;
            2)
                local f=/etc/sysctl.d/99-homeserver-ipv6.conf
                if [[ -f "$f" ]]; then
                    ask_yn "IPv6 отключён — включить?" && { rm -f "$f"; sysctl -q -p; log "IPv6 включён"; }
                else
                    ask_yn "Отключить IPv6?" || continue
                    printf 'net.ipv6.conf.all.disable_ipv6=1\nnet.ipv6.conf.default.disable_ipv6=1\nnet.ipv6.conf.lo.disable_ipv6=1\n' > "$f"
                    sysctl -q -p "$f" && log "IPv6 отключён"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            3)
                setup_dns_netplan
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

unattended_upgrades_setup() {
    clear
    echo "${c_mag}=== Unattended upgrades ===${c_off}"
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
        echo "${c_txt}Статус: установлено${c_off}"
        if ask_yn "Отключить?"; then
            apt-get remove -y unattended-upgrades
            log "Удалено"
        fi
    else
        echo "${c_txt}Статус: не установлено${c_off}"
        if ask_yn "Установить?"; then
            apt-get install -y unattended-upgrades
            printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
            log "Включено"
        fi
    fi
    read -rp "Enter — продолжить " _ || true
}

root_mail_setup() {
    clear
    echo "${c_mag}=== Почта root ===${c_off}"
    if command -v msmtp >/dev/null && grep -qs "account default" /etc/msmtprc 2>/dev/null; then
        echo "${c_txt}Статус: настроено${c_off}"
        grep -E '^(host|port|from):' /etc/msmtprc | sed 's/^/  /'
        if ! ask_yn "Перенастроить?"; then
            return
        fi
    else
        echo "${c_txt}Статус: не настроено${c_off}"
    fi

    require_cmd msmtp msmtp
    local host port user pass rcpt
    host=$(ask "SMTP-хост" "smtp.yandex.ru")
    port=$(ask "Порт" "465")
    user=$(ask "Логин")
    read -rsp "Пароль: " pass; echo
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
    log "Настроено"
    read -rp "Enter — продолжить " _ || true
}

shell_history_setup() {
    while true; do
        clear
        echo "${c_mag}=== История shell ===${c_off}"
        if [[ -f /etc/profile.d/99-homeserver-history.sh ]]; then
            echo "${c_txt}Статус: включено${c_off}"
            echo "${c_txt}HISTSIZE: $(grep HISTSIZE /etc/profile.d/99-homeserver-history.sh | cut -d= -f2)${c_off}"
        else
            echo "${c_txt}Статус: выключено${c_off}"
        fi
        echo ""
        echo "${c_txt}1. Включить/отключить${c_off}"
        echo "${c_txt}2. Просмотреть историю в редакторе${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                if [[ -f /etc/profile.d/99-homeserver-history.sh ]]; then
                    rm -f /etc/profile.d/99-homeserver-history.sh
                    log "Отключено"
                else
                    cat > /etc/profile.d/99-homeserver-history.sh <<'EOF'
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
                    log "Включено"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            2)
                require_cmd nano nano
                if [[ -f ~/.bash_history ]] && [[ -s ~/.bash_history ]]; then
                    nano ~/.bash_history
                else
                    echo "${c_txt}История пуста${c_off}"
                    if ask_yn "Добавить тестовую строку?"; then
                        echo "test_command_$(date +%s)" >> ~/.bash_history
                        log "Тестовая строка добавлена"
                    fi
                    read -rp "Enter — продолжить " _ || true
                fi ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

setup_scheduled_reboot() {
    clear
    require_cmd crontab cron
    echo "${c_mag}=== Перезагрузка по расписанию ===${c_off}"
    local cron=/etc/cron.d/homeserver-reboot
    if [[ -f "$cron" ]]; then
        local schedule; schedule=$(cat "$cron" | grep -v '^#' | grep -v '^$' | head -1)
        echo "${c_txt}Текущее: $schedule${c_off}"
        echo ""
        echo "${c_txt}1. Выключить${c_off}"
        echo "${c_txt}2. Изменить${c_off}"
        echo "${c_txt}0. Назад${c_off}"
    else
        echo "${c_txt}Текущее: не настроено${c_off}"
        echo ""
        echo "${c_txt}1. Включить${c_off}"
        echo "${c_txt}0. Назад${c_off}"
    fi
    read -rp "Номер: " c || true
    case "$c" in
        1)
            if [[ -f "$cron" ]]; then
                rm -f "$cron"; log "Выключено"
            else
                local interval hour minute dow dom
                echo "${c_txt}Интервал:${c_off}"
                echo "${c_txt}  1. Ежедневно${c_off}"
                echo "${c_txt}  2. Еженедельно${c_off}"
                echo "${c_txt}  3. Ежемесячно${c_off}"
                interval=$(ask "1-3" "2")
                hour=$(ask "Час" "5")
                minute=$(ask "Минуты" "0")
                case "$interval" in
                    1) echo "$minute $hour * * * root /sbin/reboot" > "$cron"; log "Ежедневно в $hour:$minute" ;;
                    2)
                        echo "${c_txt}День недели:${c_off}"
                        echo "${c_txt}  1 — Понедельник${c_off}"
                        echo "${c_txt}  2 — Вторник${c_off}"
                        echo "${c_txt}  3 — Среда${c_off}"
                        echo "${c_txt}  4 — Четверг${c_off}"
                        echo "${c_txt}  5 — Пятница${c_off}"
                        echo "${c_txt}  6 — Суббота${c_off}"
                        echo "${c_txt}  7 — Воскресенье${c_off}"
                        dow=$(ask "День" "1")
                        echo "$minute $hour * * $dow root /sbin/reboot" > "$cron"
                        local day_names=("" "Понедельник" "Вторник" "Среда" "Четверг" "Пятница" "Суббота" "Воскресенье")
                        log "Еженедельно, ${day_names[$dow]} в $hour:$minute" ;;
                    3)
                        dom=$(ask "День месяца" "1")
                        echo "$minute $hour $dom * * root /sbin/reboot" > "$cron"
                        log "Ежемесячно, $dom-го в $hour:$minute" ;;
                esac
            fi
            read -rp "Enter — продолжить " _ || true ;;
        2)
            if [[ -f "$cron" ]]; then
                rm -f "$cron"
                local interval hour minute dow dom
                echo "${c_txt}Интервал:${c_off}"
                echo "${c_txt}  1. Ежедневно${c_off}"
                echo "${c_txt}  2. Еженедельно${c_off}"
                echo "${c_txt}  3. Ежемесячно${c_off}"
                interval=$(ask "1-3" "2")
                hour=$(ask "Час" "5")
                minute=$(ask "Минуты" "0")
                case "$interval" in
                    1) echo "$minute $hour * * * root /sbin/reboot" > "$cron"; log "Ежедневно в $hour:$minute" ;;
                    2)
                        echo "${c_txt}День недели:${c_off}"
                        echo "${c_txt}  1 — Понедельник${c_off}"
                        echo "${c_txt}  2 — Вторник${c_off}"
                        echo "${c_txt}  3 — Среда${c_off}"
                        echo "${c_txt}  4 — Четверг${c_off}"
                        echo "${c_txt}  5 — Пятница${c_off}"
                        echo "${c_txt}  6 — Суббота${c_off}"
                        echo "${c_txt}  7 — Воскресенье${c_off}"
                        dow=$(ask "День" "1")
                        echo "$minute $hour * * $dow root /sbin/reboot" > "$cron"
                        local day_names=("" "Понедельник" "Вторник" "Среда" "Четверг" "Пятница" "Суббота" "Воскресенье")
                        log "Еженедельно, ${day_names[$dow]} в $hour:$minute" ;;
                    3)
                        dom=$(ask "День месяца" "1")
                        echo "$minute $hour $dom * * root /sbin/reboot" > "$cron"
                        log "Ежемесячно, $dom-го в $hour:$minute" ;;
                esac
            fi
            read -rp "Enter — продолжить " _ || true ;;
        0) return 0 ;;
        *) warn "нет такого пункта" ;;
    esac
}

diag_menu() {
    clear
    echo "${c_mag}=== Диагностика VPS ===${c_off}"
    echo "${c_txt}1) vps-audit${c_off}"
    echo "${c_txt}2) ipregion${c_off}"
    echo "${c_txt}3) LemonBench${c_off}"
    echo "${c_txt}4) IP Quality${c_off}"
    echo "${c_txt}5) chkrootkit${c_off}"
    echo "${c_txt}6) rkhunter${c_off}"
    echo "${c_txt}0) Назад${c_off}"
    local n; n=$(ask "1-6" "")
    case "$n" in
        1) curl -O https://raw.githubusercontent.com/vernu/vps-audit/main/vps-audit.sh && chmod +x vps-audit.sh && ./vps-audit.sh ;;
        2) wget -O ipregion.sh https://ipregion.vrnt.xyz && chmod +x ipregion.sh && ./ipregion.sh ;;
        3) bash <(curl -fsSL https://raw.githubusercontent.com/LemonBench/LemonBench/main/LemonBench.sh) fast ;;
        4) bash <(curl -sL https://Check.Place) -EI ;;
        5) require_cmd chkrootkit chkrootkit && chkrootkit ;;
        6) require_cmd rkhunter rkhunter && rkhunter --check --skip-keypress ;;
        0) return 0 ;;
    esac
    read -rp "Enter — продолжить " _ || true
}

docker_menu() {
    clear
    while true; do
        local docker_status="не установлен"
        docker compose version >/dev/null 2>&1 && docker_status="установлен"

        echo "${c_mag}=== Docker ===${c_off}"
        echo "${c_txt}Статус: $docker_status${c_off}"
        if docker compose version >/dev/null 2>&1; then
            echo ""
            echo "${c_txt}Запущенные контейнеры:${c_off}"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "${c_txt}(нет запущенных)${c_off}"
        fi
        echo ""
        echo "${c_txt}1. Установка${c_off}"
        echo "${c_txt}2. Перезапуск контейнера${c_off}"
        echo "${c_txt}3. Пересоздание контейнера${c_off}"
        echo "${c_txt}4. Логи Docker${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1) prep_system; read -rp "Enter — продолжить " _ || true ;;
            2)
                if ! docker compose version >/dev/null 2>&1; then warn "Docker не установлен"; continue; fi
                local container; container=$(ask "Имя контейнера" "")
                [[ -z "$container" ]] && continue
                docker restart "$container" && log "Контейнер $container перезапущен"
                read -rp "Enter — продолжить " _ || true ;;
            3)
                if ! docker compose version >/dev/null 2>&1; then warn "Docker не установлен"; continue; fi
                local container; container=$(ask "Имя контейнера" "")
                [[ -z "$container" ]] && continue
                docker compose up -d --force-recreate "$container" && log "Контейнер $container пересоздан"
                read -rp "Enter — продолжить " _ || true ;;
            4)
                journalctl -u docker --no-pager -n 50
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

server_menu() {
    [[ $EUID -eq 0 ]] || { warn "нужен root"; return 1; }
    while true; do
        clear
        local tz; tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')
        local pass_policy="выключена"; grep -q "pam_pwquality.so" /etc/pam.d/common-password 2>/dev/null && pass_policy="включена"
        local ssh_port; ssh_port=$(get_ssh_port)
        local ufw_status; ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo '?')
        local swap_status; swap_status=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 || echo "нет")
        local sudo_log="выкл"; grep -q "^Defaults.*logfile.*sudo.log" /etc/sudoers 2>/dev/null && sudo_log="вкл"
        local root_mail="не настроено"; command -v msmtp >/dev/null && grep -qs "account default" /etc/msmtprc 2>/dev/null && root_mail="настроено"
        local shell_hist="выключено"; [[ -f /etc/profile.d/99-homeserver-history.sh ]] && shell_hist="включено"
        local unattended="выкл"; dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && unattended="вкл"
        local reboot="не настроено"; [[ -f /etc/cron.d/homeserver-reboot ]] && reboot="настроено"

        cat <<SUM
${c_mag}$(_t SRV00)${c_off}
  ${c_num}1.${c_off} ${c_txt}$(_t SRV00)${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t SRV01): $tz${c_off}
  ${c_num}3.${c_off} ${c_txt}$(_t SRV02): $pass_policy${c_off}
  ${c_num}4.${c_off} ${c_txt}$(_t SRV03)${c_off}
  ${c_num}5.${c_off} ${c_txt}$(_t SRV04): порт $ssh_port${c_off}
  ${c_num}6.${c_off} ${c_txt}$(_t SRV05): $ufw_status${c_off}
  ${c_num}7.${c_off} ${c_txt}$(_t SRV06)${c_off}
  ${c_num}8.${c_off} ${c_txt}$(_t SRV07)${c_off}
  ${c_num}9.${c_off} ${c_txt}$(_t SRV08): $swap_status${c_off}
  ${c_num}10.${c_off} ${c_txt}$(_t SRV09): $sudo_log${c_off}
  ${c_num}11.${c_off} ${c_txt}$(_t SRV10): $root_mail${c_off}
  ${c_num}12.${c_off} ${c_txt}$(_t SRV11): $shell_hist${c_off}
  ${c_num}13.${c_off} ${c_txt}$(_t SRV12): $unattended${c_off}
  ${c_num}14.${c_off} ${c_txt}$(_t SRV13): $reboot${c_off}
  ${c_num}15.${c_off} ${c_txt}$(_t SRV14)${c_off}
  ${c_num}0.${c_off} ${c_txt}Назад${c_off}

SUM
        read -rp "Номер: " c || true
        case "$c" in
            1) system_update ;;
            2) setup_timezone ;;
            3) configure_password_policy ;;
            4) create_user ;;
            5) ssh_settings_menu ;;
            6) ufw_settings_menu ;;
            7) fail2ban_menu ;;
            8) setup_network_bbr_ipv6_dns ;;
            9) swap_menu ;;
            10) sudo_logging_menu ;;
            11) root_mail_setup ;;
            12) shell_history_setup ;;
            13) unattended_upgrades_setup ;;
            14) setup_scheduled_reboot ;;
            15) diag_menu ;;
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
            2) docker_menu ;;
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
            19) lang_menu ;;
            0) exit 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

shopt -s nullglob
mods=("$SCRIPT_DIR"/modules/*.sh)
if [[ ${#mods[@]} -eq 0 ]]; then
    die "модули не найдены"
fi
for m in "${mods[@]}"; do source "$m"; done
shopt -u nullglob

main "$@"
