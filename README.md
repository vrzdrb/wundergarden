# Wundergarden

Модульный установщик домашнего/VPS-сервера: nginx + acme.sh + Docker-контейнеры: Obsidian LiveSync (CouchDB), Radicale (CalDAV), SFTPGo, Syncthing,
Matrix (continuwuity + coturn), Luanti, SearXNG, Excalidraw, Etherpad, Mumble, ClassQuiz,
LimeSurvey, Netdata, Gitea, Jitsi Meet.

## Быстрый старт

```bash
curl -fsSL https://github.com/vrzdrb/wundergarden/archive/refs/heads/main.tar.gz | tar -xz
cd wundergarden-main
sudo bash wundergarden.sh
```

## Требования

- Debian 12+ / Ubuntu 22.04+
- проброс портов на роутере для домашнего сервера
- DNS A-записи поддоменов на ваш IP

## Порядок развёртывания

1. Пункт 1 «Настройка сервера» (по желанию: SSH-ключи → swap → BBR → UFW → fail2ban → почта).
2. Пункт 2 «Docker» (docker, .env, compose).
3. Пункт 3 «nginx и сертификаты» — сначала сертификаты wildcard, затем запуск.
4. Пункты 4–15, 20–22 — сервисы в любом порядке (Jitsi: если TURN = «наш coturn», сначала п.8).
