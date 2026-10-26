# Wundergarden

Модульный установщик домашнего/VPS-сервера: nginx + acme.sh + Docker-контейнеры: Obsidian LiveSync (CouchDB), Radicale (CalDAV), SFTPGo, Syncthing,
Matrix (continuwuity + coturn), Luanti, SearXNG, Excalidraw, Etherpad, Mumble, ClassQuiz,
LimeSurvey, Netdata, Gitea, Jitsi Meet.

## Запуск (root / sudo)

```bash
curl -fsSL https://github.com/vrzdrb/wundergarden/archive/refs/heads/main.tar.gz | tar -xz
cd wundergarden-main
chmod +x wundergarden.sh
sudo ./wundergarden.sh
```

## Требования

- Debian 12+ / Ubuntu 22.04+
- проброс портов на роутере для домашнего сервера
- DNS A-записи поддоменов на ваш IP

## Порядок развёртывания

1. Пункт 1 «Настройка сервера»
2. Пункт 2 «Docker»
3. Пункт 3 «nginx и сертификаты»
4. Пункты 4–15, 20–22 — сервисы в любом порядке
