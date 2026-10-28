#!/usr/bin/env bash

# Цветовые переменные (на случай, если не загружены из основного скрипта)
c_txt=${c_txt:-$'\033[96m'}
c_off=${c_off:-$'\033[0m'}

install_docker() {
    if docker compose version >/dev/null 2>&1; then
        log "Docker уже установлен: $(docker --version)"
        return 0
    fi
    log "Устанавливаю Docker (download.docker.com)..."
    local os_id os_like
    os_id="$(. /etc/os-release && echo "$ID")"
    os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    local distro="debian"
    if [[ "$os_id" == "ubuntu" || " $os_like " == *" ubuntu "* || " $os_like " == *" debian "* && "$os_id" != "debian" ]]; then
        distro="$os_id"
        [[ "$distro" != "ubuntu" && "$distro" != "debian" ]] && distro="ubuntu"
    fi
    [[ "$distro" != "debian" && "$distro" != "ubuntu" ]] && die "поддерживаются Debian/Ubuntu (обнаружен: $os_id)"
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$distro $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker >/dev/null
    docker compose version >/dev/null 2>&1 || die "docker compose plugin не появился"
    log "Docker установлен: $(docker --version), compose: $(docker compose version --short)"

    apt-get install -y -qq unattended-upgrades \
        && cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
        log "unattended-upgrades включён: security-обновления хоста ставятся автоматически."
    else
        warn "unattended-upgrades не установился — включите вручную (apt install unattended-upgrades)."
    fi

    if [[ ! -f /etc/docker/daemon.json ]]; then
        cat > /etc/docker/daemon.json <<'EOF'
{
  "live-restore": true,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": { "nofile": { "Name": "nofile", "Hard": 64000, "Soft": 64000 } }
}
EOF
        systemctl reload docker >/dev/null 2>&1 || true
        log "daemon.json: live-restore, no-new-privileges, ротация логов, ulimits nofile=64000."
        warn "daemon-дефолт no-new-privileges применяется к НОВЫМ контейнерам — старые пересоздадутся при up -d."
    else
        log "daemon.json уже существует — оставляю как есть (сверьте live-restore/no-new-privileges вручную)."
    fi
}

gen_compose() {
    cat > "$COMPOSE_FILE" <<'COMPOSE_EOF'
name: homeserver

x-log: &log
  driver: json-file
  options:
    max-size: "1m"
    max-file: "2"

x-harden: &harden
  cap_drop: [ALL]
  security_opt: [no-new-privileges:true]
  pids_limit: 400

services:
  nginx:
    image: linuxserver/nginx
    restart: unless-stopped
    cap_add: [NET_BIND_SERVICE]
    logging: *log
    ports:
      - "80:80"
      - "443:443"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/proxy_common.conf:/etc/nginx/proxy_common.conf:ro
      - ./config/nginx/ws_common.conf:/etc/nginx/ws_common.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./config/nginx/stream.d:/etc/nginx/stream.d:ro
      - ./config/nginx/htpasswd:/etc/nginx/htpasswd:ro
      - ./config/nginx/certs:/etc/nginx/certs:ro
      - ./data/nginx-logs:/var/log/nginx
    networks:
      - net-couchdb
      - net-cal
      - net-sftpgo
      - net-sync
      - net-matrix
      - net-search
      - net-draw
      - net-pad
      - net-quiz
      - net-survey
      - net-monitor
      - net-gitea

  couchdb:
    image: couchdb:3.3
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - COUCHDB_USER=${COUCHDB_USER}
      - COUCHDB_PASSWORD=${COUCHDB_PASSWORD}
    volumes:
      - ./data/couchdb:/opt/couchdb/data
      - ./config/couchdb/10-livesync.ini:/opt/couchdb/etc/local.d/10-livesync.ini:ro
    networks: [net-couchdb]
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:5984/_up"]
      interval: 10s
      timeout: 5s
      retries: 12

  radicale:
    image: tomsquest/docker-radicale:latest
    restart: unless-stopped
    <<: *harden
    logging: *log
    volumes:
      - ./data/radicale:/data
      - ./config/radicale/config:/etc/radicale/config:ro
      - ./config/radicale/users:/etc/radicale/users
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5232/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    networks: [net-cal]

  sftpgo:
    image: drakkan/sftpgo:latest-alpine
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - SFTPGO_DEFAULT_ADMIN_USERNAME=${SFTPGO_ADMIN_USER:-admin}
      - SFTPGO_DEFAULT_ADMIN_PASSWORD=${SFTPGO_ADMIN_PASSWORD}
      - SFTPGO_HTTPD__BINDINGS__0__PORT=8080
      - SFTPGO_DATA_PROVIDER__DRIVER=mysql
      - SFTPGO_DATA_PROVIDER__DSN=sftpgo:${SFTPGO_DB_PASSWORD}@tcp(sftpgo-db:3306)/sftpgo?timeout=5s
      - SFTPGO_DATA_PROVIDER__USERS_BASE_DIR=/var/lib/sftpgo
      - SFTPGO_WEBDAVD__BINDINGS__0__PORT=8090
    volumes:
      - ${SFTPGO_DATA}:/var/lib/sftpgo
    ports:
      - "127.0.0.1:8080:8080"
      - ${SFTPGO_SFTP_BIND:-127.0.0.1:2022}:2022
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    networks: [net-sftpgo]
    depends_on:
      - sftpgo-db

  syncthing:
    image: syncthing/syncthing:latest
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ}
      - STGUIAUTH=${SYNCTHING_GUI_AUTH:-}
    volumes:
      - ./data/syncthing:/var/syncthing
      - ${SYNCTHING_SYNC_DIR:-./data/syncthing/sync}:/var/syncthing/Sync
    ports:
      - "22000:22000/tcp"
      - "22000:22000/udp"
      - "21027:21027/udp"
      - ${SYNCTHING_GUI_BIND:-127.0.0.1:8384}:8384
    networks: [net-sync]

  matrix:
    image: ${MATRIX_IMAGE}
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - CONTINUWUITY_CONFIG=/data/continuwuity.toml
    volumes:
      - ./config/matrix/continuwuity.toml:/data/continuwuity.toml:ro
      - ./config/matrix/continuwuity.toml:/data/conduwuit.toml:ro
      - ./config/matrix/continuwuity.toml:/etc/continuwuity/continuwuity.toml:ro
      - ./data/matrix:/var/lib/continuwuity
      - ./data/matrix-backups:/backup:rw
    depends_on:
      - coturn
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8008/_matrix/client/versions >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    networks: [net-matrix]

  coturn:
    image: coturn/coturn:latest
    restart: unless-stopped
    <<: *harden
    logging: *log
    network_mode: host
    volumes:
      - ./data/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro

  luanti:
    image: ${LUANTI_IMAGE}
    restart: unless-stopped
    <<: *harden
    mem_limit: 1g
    logging: *log
    networks: [net-luanti]
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ}
    volumes:
      - ./data/luanti/config:/config/.minetest
      - ${LUANTI_WORLDS:-./data/luanti/worlds}:/config/.minetest/worlds
      - ${LUANTI_MODS:-./data/luanti/mods}:/config/.minetest/mods
      - ${LUANTI_GAMES:-./data/luanti/games}:/config/.minetest/games
    ports:
      - "30000:30000/udp"
    stdin_open: true
    tty: true

  searxng:
    image: searxng/searxng:latest
    restart: unless-stopped
    <<: *harden
    mem_limit: 512m
    logging: *log
    volumes:
      - ./data/searxng:/etc/searxng:rw
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz >/dev/null 2>&1 || wget -qO- http://localhost:8080/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    networks: [net-search]

  excalidraw:
    image: ${EXCALIDRAW_IMAGE:-alswl/excalidraw:latest}
    restart: unless-stopped
    <<: *harden
    cap_add: [NET_BIND_SERVICE]
    logging: *log
    environment:
      - VITE_APP_HTTP_STORAGE_BACKEND_URL=https://${SUB_EXCALIDRAW}/storage
      - VITE_APP_WS_SERVER_URL=https://${SUB_EXCALIDRAW}
    networks: [net-draw]

  excalidraw-room:
    image: ${EXCALIDRAW_ROOM_IMAGE:-alswl/excalidraw-room-go:v0.1.0}
    restart: unless-stopped
    <<: *harden
    logging: *log
    networks: [net-draw]

  excalidraw-storage:
    image: ${EXCALIDRAW_STORAGE_IMAGE:-alswl/excalidraw-storage-backend:latest}
    restart: unless-stopped
    <<: *harden
    logging: *log
    volumes:
      - ${EXCALIDRAW_STORAGE:-./data/excalidraw}:/data
    networks: [net-draw]

  sftpgo-db:
    image: mariadb:11
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - MYSQL_ROOT_PASSWORD=${SFTPGO_DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=sftpgo
      - MYSQL_USER=sftpgo
      - MYSQL_PASSWORD=${SFTPGO_DB_PASSWORD}
    volumes:
      - ./data/sftpgo-db:/var/lib/mysql
    networks: [net-sftpgo]

  etherpad:
    image: ${ETHERPAD_IMAGE:-etherpad/etherpad:latest}
    restart: unless-stopped
    <<: *harden
    logging: *log
    volumes:
      - ./config/etherpad/settings.json:/opt/etherpad-lite/settings.json:ro
      - ./data/etherpad:/opt/etherpad-lite/var
    networks: [net-pad]
    depends_on:
      - etherpad-db

  etherpad-db:
    image: mariadb:11
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - MYSQL_ROOT_PASSWORD=${ETHERPAD_DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=etherpad
      - MYSQL_USER=etherpad
      - MYSQL_PASSWORD=${ETHERPAD_DB_PASSWORD}
    volumes:
      - ./data/etherpad-db:/var/lib/mysql
    networks: [net-pad]

  mumble:
    image: ${MUMBLE_IMAGE:-mumblevoip/mumble-server:latest}
    restart: unless-stopped
    <<: *harden
    logging: *log
    networks: [net-mumble]
    environment:
      - MUMBLE_SUPERUSER_PASSWORD=${MUMBLE_SUPERUSER_PASSWORD}
      - MUMBLE_CONFIG_serverpassword=${MUMBLE_SERVER_PASSWORD:-}
      - MUMBLE_CONFIG_welcometext='"${MUMBLE_WELCOMETEXT:-Welcome}"'
      - MUMBLE_CONFIG_bandwidth=${MUMBLE_BANDWIDTH:-72000}
      - MUMBLE_CONFIG_users=${MUMBLE_USERS:-10}
      - MUMBLE_CONFIG_suggestpushtotalk=${MUMBLE_SUGGEST_PTT:-true}
      - MUMBLE_CONFIG_opusthreshold=0
      - MUMBLE_CONFIG_autobanAttempts=10
      - MUMBLE_CONFIG_sslCert=/cert/fullchain.pem
      - MUMBLE_CONFIG_sslKey=/cert/privkey.pem
    volumes:
      - ./data/mumble:/data
      - ./config/mumble:/cert:ro
    ports:
      - "64738:64738/tcp"
      - "64738:64738/udp"

  classquiz-frontend:
    image: ${CLASSQUIZ_FRONTEND_IMAGE:-ghcr.io/mawoka-myblock/classquiz-frontend:master}
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - REDIS_URL=redis://classquiz-redis:6379/0?decode_responses=True
      - API_URL=http://classquiz-api:80
    networks: [net-quiz]
    depends_on:
      - classquiz-api

  classquiz-api:
    image: ${CLASSQUIZ_IMAGE:-ghcr.io/mawoka-myblock/classquiz-backend:master}
    restart: unless-stopped
    <<: *harden
    mem_limit: 512m
    cap_add: [NET_BIND_SERVICE]
    logging: *log
    environment: &cqenv
      - DB_URL=postgresql://classquiz:${CLASSQUIZ_DB_PASSWORD}@classquiz-db:5432/classquiz
      - REDIS=redis://classquiz-redis:6379/0?decode_responses=True
      - SECRET_KEY=${CLASSQUIZ_SECRET_KEY}
      - MAX_WORKERS=1
      - MEILISEARCH_URL=http://classquiz-meili:7700
      - ROOT_ADDRESS=https://${SUB_CLASSQUIZ}
      - SKIP_EMAIL_VERIFICATION=${CLASSQUIZ_SKIP_EMAIL:-True}
      - MAIL_PORT=587
      - MAIL_ADDRESS=noreply@example.com
      - MAIL_PASSWORD=unused
      - MAIL_USERNAME=noreply@example.com
      - MAIL_SERVER=localhost
      - STORAGE_BACKEND=local
      - STORAGE_PATH=/app/data
    volumes:
      - ${CLASSQUIZ_UPLOADS:-./data/classquiz}:/app/data
    networks: [net-quiz]
    depends_on:
      - classquiz-db
      - classquiz-redis
      - classquiz-meili

  classquiz-worker:
    image: ${CLASSQUIZ_IMAGE:-ghcr.io/mawoka-myblock/classquiz-backend:master}
    restart: unless-stopped
    <<: *harden
    mem_limit: 512m
    logging: *log
    command: arq classquiz.worker.WorkerSettings
    environment: *cqenv
    networks: [net-quiz]
    depends_on:
      - classquiz-db
      - classquiz-redis

  classquiz-db:
    image: postgres:14-alpine
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - POSTGRES_USER=classquiz
      - POSTGRES_PASSWORD=${CLASSQUIZ_DB_PASSWORD}
      - POSTGRES_DB=classquiz
    volumes:
      - ./data/classquiz-db:/var/lib/postgresql/data
    networks: [net-quiz]

  classquiz-redis:
    image: valkey/valkey:alpine
    restart: unless-stopped
    <<: *harden
    logging: *log
    networks: [net-quiz]

  classquiz-meili:
    image: getmeili/meilisearch:v0.28.0
    restart: unless-stopped
    <<: *harden
    logging: *log
    mem_limit: ${CLASSQUIZ_MEILI_MEM:-256m}
    environment:
      - MEILI_NO_ANALYTICS=true
    volumes:
      - ./data/classquiz-meili:/data.ms
    networks: [net-quiz]

  limesurvey:
    image: ${LIMESURVEY_IMAGE:-limesurvey/limesurvey:latest}
    restart: unless-stopped
    <<: *harden
    cap_add: [NET_BIND_SERVICE]
    logging: *log
    environment:
      - DB_TYPE=${LIMESURVEY_DB_TYPE:-mysql}
      - DB_HOST=limesurvey-db
      - DB_PORT=${LIMESURVEY_DB_PORT:-3306}
      - DB_NAME=limesurvey
      - DB_USERNAME=limesurvey
      - DB_PASSWORD=${LIMESURVEY_DB_PASSWORD}
      - ADMIN_USER=${LIMESURVEY_ADMIN_USER:-admin}
      - ADMIN_NAME=${LIMESURVEY_ADMIN_NAME:-Admin}
      - ADMIN_EMAIL=${EMAIL}
      - ADMIN_PASSWORD=${LIMESURVEY_ADMIN_PASSWORD}
      - PUBLIC_URL=https://${SUB_LIMESURVEY}/
    volumes:
      - ${LIMESURVEY_UPLOADS:-./data/limesurvey}:/var/www/html/upload
    networks: [net-survey]
    depends_on:
      - limesurvey-db

  limesurvey-db:
    image: ${LIMESURVEY_DB_IMAGE:-mariadb:11}
    restart: unless-stopped
    <<: *harden
    logging: *log
    environment:
      - MYSQL_ROOT_PASSWORD=${LIMESURVEY_DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=limesurvey
      - MYSQL_USER=limesurvey
      - MYSQL_PASSWORD=${LIMESURVEY_DB_PASSWORD}
    volumes:
      - ./data/limesurvey-db:/var/lib/mysql
    networks: [net-survey]

  gitea:
    image: docker.gitea.com/gitea:1.27.0
    restart: unless-stopped
    logging: *log
    <<: *harden
    mem_limit: 512m
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=gitea-db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${GITEA_DB_PASSWORD}
      - GITEA__server__PROTOCOL=http
      - GITEA__server__HTTP_PORT=3000
      - GITEA__server__DOMAIN=${SUB_GITEA}
      - GITEA__server__ROOT_URL=https://${SUB_GITEA}/
      - GITEA__server__DISABLE_SSH=true
      - GITEA__server__LFS_START_SERVER=false
      - GITEA__service__DISABLE_REGISTRATION=true
      - GITEA__service__REQUIRE_SIGNIN_VIEW=true
      - GITEA__service__DEFAULT_ALLOW_CREATE_ORGANIZATION=false
      - GITEA__service__DEFAULT_ORG_VISIBILITY=private
      - GITEA__security__INSTALL_LOCK=true
      - GITEA__openid__ENABLE_OPENID_SIGNIN=false
      - GITEA__openid__ENABLE_OPENID_SIGNUP=false
    volumes:
      - ./data/gitea:/data
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks: [net-gitea]

  gitea-db:
    image: postgres:16-alpine
    restart: unless-stopped
    logging: *log
    <<: *harden
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=${GITEA_DB_PASSWORD}
      - POSTGRES_DB=gitea
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "localhost", "-U", "gitea", "-d", "gitea"]
      interval: 10s
      timeout: 5s
      retries: 12
    volumes:
      - ./data/gitea-db:/var/lib/postgresql/data
    networks: [net-gitea]

  netdata:
    image: netdata/netdata:stable
    restart: unless-stopped
    logging: *log
    <<: *harden
    mem_limit: 256m
    cap_add: [SYS_PTRACE]
    security_opt: [apparmor=unconfined, no-new-privileges:true]
    environment:
      - DOCKER_HOST=tcp://socket-proxy:2375
      - NETDATA_CLAIM_TOKEN=
    ports:
      - "127.0.0.1:19999:19999"
    volumes:
      - ./data/netdata/etc:/etc/netdata
      - netdata-lib:/var/lib/netdata
      - netdata-cache:/var/cache/netdata
      - /:/host/root:ro,rslave
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /etc/os-release:/host/etc/os-release:ro
    networks: [net-monitor]

  socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    restart: unless-stopped
    logging: *log
    <<: *harden
    environment:
      - CONTAINERS=1
      - INFO=1
      - POST=0
      - ALLOW_START=0
      - ALLOW_STOP=0
      - ALLOW_RESTARTS=0
      - EXEC=0
      - IMAGES=0
      - NETWORKS=0
      - VOLUMES=0
      - BUILD=0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [net-monitor]

networks:
  net-gitea:
  net-monitor:
  net-couchdb:
  net-cal:
  net-sftpgo:
  net-sync:
  net-matrix:
  net-luanti:
  net-search:
  net-draw:
  net-pad:
  net-mumble:
  net-quiz:
  net-survey:

volumes:
  netdata-lib:
  netdata-cache:

COMPOSE_EOF
}

prep_system() {
    log "=== Подготовка системы ==="
    command -v openssl >/dev/null || apt-get install -y -qq openssl
    install_docker

    # Спрашиваем о добавлении пользователей в группу docker
    echo "${c_txt}Каких пользователей добавить в группу docker? (через пробел, Enter — пропустить)${c_off}"
    local docker_users
    read -rp "Пользователи: " docker_users || true
    if [[ -n "$docker_users" ]]; then
        for user in $docker_users; do
            if id "$user" >/dev/null 2>&1; then
                usermod -aG docker "$user" && log "Пользователь $user добавлен в группу docker"
            else
                warn "Пользователь $user не найден"
            fi
        done
    fi

    # Читаем часовой пояс из системы (настроен в подменю "Настройка сервера")
    local tz
    tz="$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Europe/Moscow")"
    log "Часовой пояс из системы: $tz"

    mkdir -p "$CONFIG_ROOT"/{config/couchdb,data/{couchdb,radicale,syncthing,searxng,luanti/config},backups}
    
    # Создаём .env автоматически, если его нет
    if [[ ! -f "$ENV_FILE" ]]; then
        cat > "$ENV_FILE" <<EOF
TZ=$tz
LANG_UI=ru
HSTS_ENABLED=false
STREAM_DOMAINS=
TURN_PASSWORD=$(gen_pass)
PUBLIC_IP=
DOMAIN=
EMAIL=
MATRIX_IMAGE=ghcr.io/continuwuity/continuwuity:latest
LUANTI_IMAGE=linuxserver/minetest:latest
LUANTI_WORLDS=$CONFIG_ROOT/data/luanti/worlds
LUANTI_MODS=$CONFIG_ROOT/data/luanti/mods
LUANTI_GAMES=$CONFIG_ROOT/data/luanti/games
MUMBLE_IMAGE=mumblevoip/mumble-server:latest
MUMBLE_SUGGEST_PTT=true
REGISTRATION_TOKEN=
ETHERPAD_IMAGE=etherpad/etherpad:latest
EXCALIDRAW_IMAGE=alswl/excalidraw:latest
EXCALIDRAW_ROOM_IMAGE=alswl/excalidraw-room-go:v0.1.0
EXCALIDRAW_STORAGE_IMAGE=alswl/excalidraw-storage-backend:latest
CLASSQUIZ_IMAGE=ghcr.io/mawoka-myblock/classquiz-backend:master
CLASSQUIZ_FRONTEND_IMAGE=ghcr.io/mawoka-myblock/classquiz-frontend:master
LIMESURVEY_IMAGE=limesurvey/limesurvey:latest
LIMESURVEY_UPLOADS=$CONFIG_ROOT/data/limesurvey
LIMESURVEY_ADMIN_USER=admin
LIMESURVEY_ADMIN_NAME=Admin
COUCHDB_USER=admin
COUCHDB_PASSWORD=$(gen_pass)
SFTPGO_ADMIN_PASSWORD=$(gen_pass)
SFTPGO_DB_PASSWORD=$(gen_pass)
SFTPGO_DB_ROOT_PASSWORD=$(gen_pass)
SFTPGO_ADMIN_USER=admin
SFTPGO_SFTP_BIND=127.0.0.1:2022
SFTPGO_DATA=/mnt/emmc/cloud
SYNCTHING_GUI_AUTH=admin:$(gen_pass)
SYNCTHING_GUI_BIND=127.0.0.1:8384
SYNCTHING_SYNC_DIR=$CONFIG_ROOT/data/syncthing/sync
SYNCTHING_RESCAN=3600
EXCALIDRAW_STORAGE=$CONFIG_ROOT/data/excalidraw
SUB_EXCALIDRAW=
ETHERPAD_DB_PASSWORD=$(gen_pass)
ETHERPAD_DB_ROOT_PASSWORD=$(gen_pass)
MUMBLE_SUPERUSER_PASSWORD=$(gen_pass)
MUMBLE_SERVER_PASSWORD=
MUMBLE_WELCOMETEXT=Welcome
MUMBLE_BANDWIDTH=72000
MUMBLE_USERS=10
CLASSQUIZ_SECRET_KEY=$(gen_pass)
CLASSQUIZ_DB_PASSWORD=$(gen_pass)
CLASSQUIZ_SKIP_EMAIL=True
CLASSQUIZ_MEILI_MEM=256m
CLASSQUIZ_UPLOADS=$CONFIG_ROOT/data/classquiz
SUB_CLASSQUIZ=
LIMESURVEY_DB_TYPE=mysql
LIMESURVEY_DB_IMAGE=mariadb:11
LIMESURVEY_DB_PORT=3306
LIMESURVEY_DB_PASSWORD=$(gen_pass)
LIMESURVEY_DB_ROOT_PASSWORD=$(gen_pass)
LIMESURVEY_ADMIN_PASSWORD=$(gen_pass)
SUB_LIMESURVEY=
SEARXNG_SECRET=$(gen_pass)
SEARCH_PW=
SUB_GITEA=
GITEA_DB_PASSWORD=$(gen_pass)
EOF
        chmod 600 "$ENV_FILE"
        log "Конфигурация создана"
    else
        log "Конфигурация уже существует"
    fi

    load_env
    mkdir -p "$CONFIG_ROOT"/{config/couchdb,data/{couchdb,radicale,syncthing,searxng,luanti/config},backups}
    mkdir -p "$CONFIG_ROOT"/config/nginx/{conf.d,stream.d,htpasswd,certs}
    mkdir -p "$CONFIG_ROOT/data/nginx-logs"

    cat > "$CONFIG_ROOT/config/nginx/nginx.conf" <<'NGXEOF'
load_module modules/ngx_stream_module.so;
user nginx;
worker_processes auto;
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    server_tokens off;
    client_max_body_size 512m;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    limit_req_zone $binary_remote_addr zone=perip:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;
    keepalive_requests 1000;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    access_log off;
    error_log /var/log/nginx/error.log warn;
    server {
        listen 80 default_server;
        return 301 https://$host$request_uri;
    }
    server {
        listen 8443 ssl default_server;
        ssl_certificate     /etc/nginx/certs/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/privkey.pem;
        return 444;
    }
    include /etc/nginx/conf.d/*.conf;
}

stream {
    error_log /dev/stderr;
    include /etc/nginx/stream.d/*.conf;
}
NGXEOF
    hsts_line_enable

    cat > "$CONFIG_ROOT/config/nginx/proxy_common.conf" <<'NGXEOF'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_read_timeout 3600s;
proxy_hide_header Server;
proxy_hide_header X-Powered-By;
limit_req zone=perip burst=100 nodelay;
limit_conn addr 20;
NGXEOF
    cat > "$CONFIG_ROOT/config/nginx/ws_common.conf" <<'NGXEOF'
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
NGXEOF
    cat > "$CONFIG_ROOT/config/nginx/stream.d/00-map.conf" <<'NGXEOF'
map $ssl_preread_server_name $stream_upstream {
    default web_tls;
}
upstream web_tls { server 127.0.0.1:8443; }
NGXEOF

    gen_compose
    log "Подготовка завершена. Секреты в $ENV_FILE (права 600)."
    warn "Дальше: пункт 3 (nginx и сертификаты: сначала сертификаты, затем запуск)."
    warn "Не забудьте: A-записи поддоменов -> ваш статический IP, проброс 80/443 на роутере."
}

ensure_prepared() { [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]] || { warn "Сначала выполните пункт 2 (подготовка)."; prep_system; }; load_env; }
