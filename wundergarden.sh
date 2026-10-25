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
        M19) echo "Бэкапы" ;;
        M20) echo "Статус" ;;
        M21) echo "Обновления" ;;
        M22) echo "Язык" ;;
        MQ)   echo "  ${c_num}0.${c_off} ${c_txt}Выход${c_off}" ;;
        MFTR) echo "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" ;;
        SRV01) echo "Часовой пояс" ;;
        SRV02) echo "Политика паролей" ;;
        SRV03) echo "Создание пользователя" ;;
        SRV04) echo "Настройки SSH" ;;
        SRV05) echo "Настройки UFW" ;;
        SRV06) echo "Fail2ban" ;;
        SRV07) echo "BBR, IPv6, DNS" ;;
        SRV08) echo "Swap" ;;
        SRV09) echo "Логирование sudo" ;;
        SRV10) echo "Почта root" ;;
        SRV11) echo "История shell" ;;
        SRV12) echo "Автообновления" ;;
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

# ========== ФУНКЦИИ ==========

setup_timezone() {
    clear
    echo "${c_mag}=== Часовой пояс ===${c_off}"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')
    echo "${c_txt}Текущий: $current_tz${c_off}"
    local new_tz; new_tz=$(ask "Новый часовой пояс" "$current_tz")
    timedatectl set-timezone "$new_tz" && log "Установлено: $new_tz"
    read -rp "Enter — продолжить " _ || true
}

configure_password_policy() {
    clear
    echo "${c_mag}=== Политика паролей ===${c_off}"
    require_cmd pam_pwquality libpam-pwquality
    
    local status="неактивна"
    if grep -q "pam_pwquality.so" /etc/pam.d/common-password 2>/dev/null; then
        status="активна"
    fi
    echo "${c_txt}Статус: $status${c_off}"
    echo ""
    echo "${c_txt}1. Включить политику${c_off}"
    echo "${c_txt}2. Отключить политику${c_off}"
    echo "${c_txt}3. Применить к существующим пользователям${c_off}"
    echo "${c_txt}0. Назад${c_off}"
    read -rp "Номер: " c || true
    case "$c" in
        1)
            local pam_file="/etc/pam.d/common-password"
            sed -i '/pam_pwquality.so/d' "$pam_file"
            echo 'password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1' >> "$pam_file"
            log "Политика включена"
            read -rp "Enter — продолжить " _ || true ;;
        2)
            sed -i '/pam_pwquality.so/d' /etc/pam.d/common-password
            log "Политика отключена"
            read -rp "Enter — продолжить " _ || true ;;
        3)
            echo "${c_txt}Смена паролей для пользователей (политика применится при следующем входе):${c_off}"
            local users
            users=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
            for user in $users; do
                echo "${c_txt}Пользователь: $user${c_off}"
                if ask_yn "Сменить пароль?"; then
                    passwd "$user"
                fi
            done
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
    else
        adduser --disabled-password --gecos "" "$username"
        echo "${c_txt}Установите пароль для $username:${c_off}"
        passwd "$username"
        usermod -aG sudo "$username"
        log "Пользователь $username создан"
    fi
    read -rp "Enter — продолжить " _ || true
}

get_ssh_port() {
    grep "^Port " /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || \
    grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22"
}

ssh_settings_menu() {
    clear
    while true; do
        local port=$(get_ssh_port)
        local root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || echo "prohibit-password")
        local pass_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config.d/99-homeserver.conf 2>/dev/null | awk '{print $2}' || echo "yes")
        
        echo "${c_mag}=== Настройки SSH ===${c_off}"
        echo "${c_txt}Порт: $port${c_off}"
        echo "${c_txt}Вход root: $root_login${c_off}"
        echo "${c_txt}Вход по паролю: $pass_auth${c_off}"
        echo ""
        echo "${c_txt}1. Изменить SSH-порт${c_off}"
        echo "${c_txt}2. Добавить SSH-ключ${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                require_cmd ufw ufw
                local new_port; new_port=$(ask "Новый SSH-порт" "$port")
                [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]] || { warn "некорректный порт"; continue; }
                
                ufw allow "$new_port/tcp" comment 'SSH' >/dev/null 2>&1 && log "UFW: порт $new_port/tcp открыт" || warn "Ошибка обновления UFW"
                ufw reload >/dev/null 2>&1
                
                local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
                mkdir -p /etc/ssh/sshd_config.d
                grep -q "^Port " "$cfg" 2>/dev/null && sed -i "s|^Port .*|Port $new_port|" "$cfg" || echo "Port $new_port" >> "$cfg"
                
                if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
                    log "SSH перезапущен, порт: $new_port"
                else
                    warn "Ошибка перезапуска SSH"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            2)
                local username; username=$(ask "Имя пользователя" "")
                [[ -z "$username" ]] && continue
                id "$username" >/dev/null 2>&1 || { warn "пользователь не найден"; continue; }
                local IP; IP="$(curl -fsS --max-time 5 ifconfig.me 2>/dev/null || echo '<IP>')"
                echo "${c_mag}=======================================================================================${c_off}"
                echo "${c_mag}Создайте ключ на своём компьютере:${c_off}"
                echo "${c_txt}ssh-keygen -t ed25519${c_off}"
                echo ""
                echo "${c_mag}Загрузите ключ на сервер (Linux):${c_off}"
                echo "${c_txt}ssh-copy-id -i ~/.ssh/id_ed25519.pub $username@$IP${c_off}"
                echo ""
                echo "${c_mag}Команда для Windows:${c_off}"
                echo "${c_txt}type %USERPROFILE%\\.ssh\\id_ed25519.pub | ssh $username@$IP \"cat >> ~/.ssh/authorized_keys\"${c_off}"
                echo ""
                echo "${c_mag}Проверьте вход ключом:${c_off}"
                echo "${c_txt}ssh -i ~/.ssh/id_ed25519 $username@$IP${c_off}"
                echo ""
                echo "${c_mag}ТОЛЬКО ЕСЛИ ВХОД УСПЕШЕН, нажмите Enter для отключения пароля${c_off}"
                echo "${c_mag}=======================================================================================${c_off}"
                read -r
                
                local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
                mkdir -p /etc/ssh/sshd_config.d
                grep -q "^PasswordAuthentication" "$cfg" 2>/dev/null && sed -i 's|^PasswordAuthentication.*|PasswordAuthentication no|' "$cfg" || echo "PasswordAuthentication no" >> "$cfg"
                
                if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
                    mv /etc/ssh/sshd_config.d/50-cloud-init.conf "/etc/ssh/sshd_config.d/50-cloud-init.conf.disabled.$(date +%s)"
                    log "50-cloud-init.conf отключён"
                fi
                
                if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
                    log "Вход по паролю отключён"
                else
                    warn "Ошибка перезапуска SSH"
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
    local port=$(get_ssh_port)
    echo "${c_mag}=== Изменить SSH-порт ===${c_off}"
    echo "${c_txt}Текущий порт: $port${c_off}"
    local new_port; new_port=$(ask "Новый SSH-порт" "$port")
    [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]] || { warn "некорректный порт"; return; }
    
    ufw allow "$new_port/tcp" comment 'SSH' >/dev/null 2>&1 && log "UFW: порт $new_port/tcp открыт" || warn "Ошибка UFW"
    ufw reload >/dev/null 2>&1
    
    local cfg=/etc/ssh/sshd_config.d/99-homeserver.conf
    mkdir -p /etc/ssh/sshd_config.d
    grep -q "^Port " "$cfg" 2>/dev/null && sed -i "s|^Port .*|Port $new_port|" "$cfg" || echo "Port $new_port" >> "$cfg"
    
    if systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; then
        log "SSH перезапущен, порт: $new_port"
    else
        warn "Ошибка перезапуска SSH"
    fi
    read -rp "Enter — продолжить " _ || true
}

ufw_settings_menu() {
    clear
    require_cmd ufw ufw
    while true; do
        local status=$(ufw status | head -1 | awk '{print $2}')
        local port=$(get_ssh_port)
        echo "${c_mag}=== Настройки UFW ===${c_off}"
        echo "${c_txt}Статус: $status${c_off}"
        echo "${c_txt}SSH-порт: $port${c_off}"
        echo ""
        echo "${c_txt}1. Изменить SSH-порт${c_off}"
        echo "${c_txt}2. Блокировка ботов${c_off}"
        echo "${c_txt}3. Блокировка РКН${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1) change_ssh_port_direct ;;
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
        echo "${c_mag}=== Блокировка ботов ===${c_off}"
        echo "${c_txt}Статус: активен ($(ipset list abuse4 2>/dev/null | grep -c '^[0-9]' || echo 0) сетей)${c_off}"
        if ask_yn "Отключить?"; then
            iptables -D INPUT -m set --match-set abuse4 src -j DROP 2>/dev/null
            iptables -D DOCKER-USER -m set --match-set abuse4 src -j DROP 2>/dev/null
            ipset destroy abuse4 2>/dev/null; rm -f "$script" "$cron"; log "Удалён"
        fi
        read -rp "Enter — продолжить " _ || true
        return
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
    if "$script"; then
        printf '@reboot root /opt/homeserver/abuse-block.sh\n17 4 * * * root /opt/homeserver/abuse-block.sh\n' > "$cron"
        log "Применён"
    else
        rm -f "$script"
        warn "Ошибка применения"
    fi
    read -rp "Enter — продолжить " _ || true
}

block_rkn() {
    clear
    require_cmd ipset ipset
    local script=/opt/homeserver/rkn-block.sh cron=/etc/cron.d/homeserver-rkn
    if [[ -f "$script" ]]; then
        echo "${c_mag}=== Блокировка РКН ===${c_off}"
        echo "${c_txt}Статус: активен${c_off}"
        if ask_yn "Отключить?"; then
            rm -f "$script" "$cron"; log "Удалён"
        fi
        read -rp "Enter — продолжить " _ || true
        return
    fi
    echo "${c_mag}=== Блокировка РКН ===${c_off}"
    cat > "$script" <<'RKNEOF'
#!/usr/bin/env bash
set -e
URL="https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv"
TMP="$(mktemp)"
curl -fsSL --max-time 300 "$URL" -o "$TMP"
ipset create rkn4_tmp hash:net
cut -d';' -f1 "$TMP" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^/add rkn4_tmp /' | ipset restore
ipset create rkn4 hash:net 2>/dev/null || true
ipset swap rkn4_tmp rkn4
ipset destroy rkn4_tmp
rm -f "$TMP"
iptables -C INPUT -m set --match-set rkn4 src -j DROP 2>/dev/null || iptables -I INPUT 1 -m set --match-set rkn4 src -j DROP
RKNEOF
    chmod +x "$script"
    if "$script"; then
        printf '@reboot root /opt/homeserver/rkn-block.sh\n23 3 * * * root /opt/homeserver/rkn-block.sh\n' > "$cron"
        log "Применён"
    else
        rm -f "$script"
        warn "Ошибка применения"
    fi
    read -rp "Enter — продолжить " _ || true
}

swap_menu() {
    clear
    while true; do
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
                local g; g=$(ask "Размер swap, ГБ" "2")
                [[ "$g" =~ ^[0-9]+$ ]] || { warn "нужно число"; continue; }
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
                fi
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

sudo_logging_menu() {
    clear
    while true; do
        echo "${c_mag}=== Логирование sudo ===${c_off}"
        if [[ -f /etc/sudoers.d/99-homeserver-logging ]]; then
            echo "${c_txt}Статус: ВКЛЮЧЕНО${c_off}"
            if [[ -f /var/log/sudo.log ]]; then
                echo "${c_txt}Последние записи:${c_off}"
                tail -n 5 /var/log/sudo.log
            else
                echo "${c_txt}Лог пока пуст${c_off}"
                if ask_yn "Сделать тестовую запись?"; then
                    sudo -u root echo "Тестовая запись" >/dev/null 2>&1
                    log "Тестовая запись сделана"
                fi
            fi
        else
            echo "${c_txt}Статус: ВЫКЛЮЧЕНО${c_off}"
        fi
        echo ""
        echo "${c_txt}1. Включить${c_off}"
        echo "${c_txt}2. Отключить${c_off}"
        echo "${c_txt}3. Открыть лог${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1)
                cat > /etc/sudoers.d/99-homeserver-logging <<'EOF'
Defaults logfile=/var/log/sudo.log
EOF
                visudo -cf /etc/sudoers.d/99-homeserver-logging >/dev/null && log "Включено"
                read -rp "Enter — продолжить " _ || true ;;
            2)
                rm -f /etc/sudoers.d/99-homeserver-logging
                log "Отключено"
                read -rp "Enter — продолжить " _ || true ;;
            3)
                require_cmd nano nano
                [[ -f /var/log/sudo.log ]] && nano /var/log/sudo.log || { warn "лог не найден"; read -rp "Enter — продолжить " _ || true; } ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

fail2ban_menu() {
    clear
    require_cmd fail2ban-client fail2ban
    while true; do
        [[ -f "$ENV_FILE" ]] && load_env
        local bantime="${F2B_BANTIME:-7200}" maxretry="${F2B_MAXRETRY:-10}" findtime="${F2B_FINDTIME:-900}"
        local f2b_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
        
        echo "${c_mag}=== Fail2ban ===${c_off}"
        echo "${c_txt}Статус: $f2b_status${c_off}"
        echo "${c_txt}bantime: ${bantime}с${c_off}"
        echo "${c_txt}maxretry: $maxretry${c_off}"
        echo "${c_txt}findtime: ${findtime}с${c_off}"
        echo ""
        echo "${c_txt}1. Изменить bantime${c_off}"
        echo "${c_txt}2. Изменить maxretry${c_off}"
        echo "${c_txt}3. Изменить findtime${c_off}"
        echo "${c_txt}4. Применить и перезапустить${c_off}"
        echo "${c_txt}0. Назад${c_off}"
        read -rp "Номер: " c || true
        case "$c" in
            1) bantime=$(ask "bantime, секунд" "$bantime"); update_env F2B_BANTIME "$bantime" ;;
            2) maxretry=$(ask "maxretry" "$maxretry"); update_env F2B_MAXRETRY "$maxretry" ;;
            3) findtime=$(ask "findtime, секунд" "$findtime"); update_env F2B_FINDTIME "$findtime" ;;
            4)
                local ssh_port=$(get_ssh_port)
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
                systemctl restart fail2ban && log "Fail2ban перезапущен"
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

setup_network_bbr_ipv6_dns() {
    clear
    while true; do
        echo "${c_mag}=== BBR, IPv6, DNS ===${c_off}"
        echo "${c_txt}BBR: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')${c_off}"
        echo "${c_txt}IPv6: $([ -f /etc/sysctl.d/99-homeserver-ipv6.conf ] && echo 'отключён' || echo 'включён')${c_off}"
        echo "${c_txt}DNS-over-TLS: $([ -f /etc/systemd/resolved.conf.d/99-homeserver.conf ] && echo 'включён' || echo 'выкл')${c_off}"
        echo ""
        echo "${c_txt}1. BBR${c_off}"
        echo "${c_txt}2. IPv6${c_off}"
        echo "${c_txt}3. DNS-over-TLS${c_off}"
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
                local f=/etc/systemd/resolved.conf.d/99-homeserver.conf
                if [[ -f "$f" ]]; then
                    ask_yn "DoT включён — отключить?" && { rm -f "$f"; systemctl restart systemd-resolved; log "DoT отключён"; }
                else
                    require_cmd resolvectl systemd
                    mkdir -p /etc/systemd/resolved.conf.d
                    rm -f /etc/resolv.conf
                    cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 9.9.9.9
nameserver 8.8.8.8
EOF
                    chmod 644 /etc/resolv.conf
                    printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net 8.8.8.8#dns.google\nDNSOverTLS=opportunistic\nDomains=~.\n' > "$f"
                    systemctl restart systemd-resolved
                    log "DoT включён"
                fi
                read -rp "Enter — продолжить " _ || true ;;
            0) return 0 ;;
            *) warn "нет такого пункта" ;;
        esac
    done
}

unattended_upgrades_setup() {
    clear
    echo "${c_mag}=== Автообновления ===${c_off}"
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
        echo "${c_txt}Статус: УСТАНОВЛЕНО${c_off}"
        if ask_yn "Отключить?"; then
            apt-get remove -y unattended-upgrades
            log "Удалено"
        fi
    else
        echo "${c_txt}Статус: НЕ УСТАНОВЛЕНО${c_off}"
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
        echo "${c_txt}Статус: НАСТРОЕНО${c_off}"
        grep -E '^(host|port|from):' /etc/msmtprc | sed 's/^/  /'
        if ! ask_yn "Перенастроить?"; then
            return
        fi
    else
        echo "${c_txt}Статус: НЕ НАСТРОЕНО${c_off}"
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
    clear
    echo "${c_mag}=== История shell ===${c_off}"
    if [[ -f /etc/profile.d/99-homeserver-history.sh ]]; then
        echo "${c_txt}Статус: НАСТРОЕНО${c_off}"
        echo "${c_txt}HISTSIZE: $(grep HISTSIZE /etc/profile.d/99-homeserver-history.sh | cut -d= -f2)${c_off}"
    else
        echo "${c_txt}Статус: НЕ НАСТРОЕНО${c_off}"
    fi
    if ask_yn "Настроить?"; then
        cat > /etc/profile.d/99-homeserver-history.sh <<'EOF'
export HISTTIMEFORMAT="%F %T  "
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
        log "Настроено"
    fi
    read -rp "Enter — продолжить " _ || true
}

setup_scheduled_reboot() {
    clear
    require_cmd crontab cron
    echo "${c_mag}=== Перезагрузка по расписанию ===${c_off}"
    local cron=/etc/cron.d/homeserver-reboot
    if [[ -f "$cron" ]]; then
        local schedule=$(cat "$cron" | grep -v '^#' | grep -v '^$')
        echo "${c_txt}Текущее: $schedule${c_off}"
    else
        echo "${c_txt}Текущее: не настроено${c_off}"
    fi
    echo ""
    echo "${c_txt}1. Выключить${c_off}"
    echo "${c_txt}2. Настроить${c_off}"
    echo "${c_txt}0. Назад${c_off}"
    read -rp "Номер: " c || true
    case "$c" in
        1) rm -f "$cron"; log "Выключено"; read -rp "Enter — продолжить " _ || true ;;
        2)
            local interval hour minute dow dom
            echo "${c_txt}Интервал:${c_off}"
            echo "${c_txt}  1. Ежедневно${c_off}"
            echo "${c_txt}  2. Еженедельно${c_off}"
            echo "${c_txt}  3. Ежемесячно${c_off}"
            interval=$(ask "1-3" "2")
            hour=$(ask "Час" "5")
            minute=$(ask "Минуты" "0")
            case "$interval" in
                1) printf "$minute $hour * * * root /sbin/reboot\n" > "$cron"; log "Ежедневно в $hour:$minute" ;;
                2)
                    echo "${c_txt}День недели (1=пн, 7=вс):${c_off}"
                    dow=$(ask "День" "1")
                    printf "$minute $hour * * $dow root /sbin/reboot\n" > "$cron"
                    log "Еженедельно, день $dow в $hour:$minute" ;;
                3)
                    dom=$(ask "День месяца" "1")
                    printf "$minute $hour $dom * * root /sbin/reboot\n" > "$cron"
                    log "Ежемесячно, $dom-го в $hour:$minute" ;;
            esac
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
    echo "${c_txt}0) Назад${c_off}"
    local n; n=$(ask "1-3" "")
    case "$n" in
        1) bash <(curl -fsSL https://raw.githubusercontent.com/hidden-refuge/vps-audit/main/vps-audit.sh) ;;
        2) bash <(curl -fsSL https://raw.githubusercontent.com/uxh/sh/main/ipregion.sh) ;;
        3) bash <(curl -fsSL https://raw.githubusercontent.com/LemonBench/LemonBench/main/LemonBench.sh) fast ;;
        0) return 0 ;;
    esac
    read -rp "Enter — продолжить " _ || true
}

server_menu() {
    [[ $EUID -eq 0 ]] || { warn "нужен root"; return 1; }
    while true; do
        clear
        local tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo '?')
        local pass_policy="неактивна"; grep -q "pam_pwquality.so" /etc/pam.d/common-password 2>/dev/null && pass_policy="активна"
        local ssh_port=$(get_ssh_port)
        local ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo '?')
        local f2b_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
        local swap_status=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 || echo "нет")
        local sudo_log="выкл"; [[ -f /etc/sudoers.d/99-homeserver-logging ]] && sudo_log="вкл"
        local root_mail="не настроено"; command -v msmtp >/dev/null && grep -qs "account default" /etc/msmtprc 2>/dev/null && root_mail="настроено"
        local shell_hist="не настроено"; [[ -f /etc/profile.d/99-homeserver-history.sh ]] && shell_hist="настроено"
        local unattended="выкл"; dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && unattended="вкл"
        local reboot="не настроено"; [[ -f /etc/cron.d/homeserver-reboot ]] && reboot="настроено"
        
        cat <<SUM
${c_mag}$(_t SRV01)${c_off}
  ${c_num}1.${c_off} ${c_txt}$(_t SRV01): $tz${c_off}
  ${c_num}2.${c_off} ${c_txt}$(_t SRV02): $pass_policy${c_off}
  ${c_num}3.${c_off} ${c_txt}$(_t SRV03)${c_off}
  ${c_num}4.${c_off} ${c_txt}$(_t SRV04): порт $ssh_port${c_off}
  ${c_num}5.${c_off} ${c_txt}$(_t SRV05): $ufw_status${c_off}
  ${c_num}6.${c_off} ${c_txt}$(_t SRV06): $f2b_status${c_off}
  ${c_num}7.${c_off} ${c_txt}$(_t SRV07)${c_off}
  ${c_num}8.${c_off} ${c_txt}$(_t SRV08): $swap_status${c_off}
  ${c_num}9.${c_off} ${c_txt}$(_t SRV09): $sudo_log${c_off}
  ${c_num}10.${c_off} ${c_txt}$(_t SRV10): $root_mail${c_off}
  ${c_num}11.${c_off} ${c_txt}$(_t SRV11): $shell_hist${c_off}
  ${c_num}12.${c_off} ${c_txt}$(_t SRV12): $unattended${c_off}
  ${c_num}13.${c_off} ${c_txt}$(_t SRV13): $reboot${c_off}
  ${c_num}14.${c_off} ${c_txt}$(_t SRV14)${c_off}
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

shopt -s nullglob
mods=("$SCRIPT_DIR"/modules/*.sh)
if [[ ${#mods[@]} -eq 0 ]]; then
    die "модули не найдены"
fi
for m in "${mods[@]}"; do source "$m"; done
shopt -u nullglob

main "$@"
