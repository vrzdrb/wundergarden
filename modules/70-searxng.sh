#!/usr/bin/env bash
# modules/70-searxng.sh — сервис: searxng
# Загружается wundergarden.sh; использует общие хелперы основного скрипта.

install_searxng() {
    ensure_prepared
    log "=== SearXNG ==="
    SUB_SEARCH="$(ask "Поддомен для поиска" "${SUB_SEARCH:-search.$DOMAIN}")"; update_env SUB_SEARCH "$SUB_SEARCH"
    dns_hint "$SUB_SEARCH"
    local sname
    sname="$(ask "Имя инстанса (шапка страницы)" "HomeSearch")"

    # --- значения по умолчанию ---
    local locale="ru" slang="auto" safe=1 autocomplete="" \
          tracker="true" scihub="false" converter="true" \
          engines_mode="default" engines_list="" \
          theme="simple" style="auto" access="private" \
          formats="[html]" method="GET" imgproxy="true" \
          auth_user="" auth_pw=""

    while true; do
        local eng_desc="по умолчанию (все)" slang_label="$slang" ac="выкл" acc_desc="пароль (basicauth)"
        [[ "$engines_mode" == "custom" ]] && eng_desc="выборочно: $(echo "$engines_list" | grep -c .) движков"
        [[ "$slang" == "auto" ]] && slang_label="глобальный (auto)"
        [[ -n "$autocomplete" ]] && ac="$autocomplete"
        [[ "$access" == "public" ]] && acc_desc="публичный + limiter"
        [[ "$access" == "open" ]] && acc_desc="открытый (без защиты!)"
        cat <<SUM

 --- Настройки SearXNG ---
  1. Язык интерфейса: $locale
  2. Область поиска: $slang_label
  3. SafeSearch: $(safe_descr "$safe")
  4. Автокомплит: $ac
  5. Удаление трекеров из ссылок: $(onoff "$tracker")
  6. Редирект DOI -> sci-hub: $(onoff "$scihub")
  7. Конвертер единиц: $(onoff "$converter")
  8. Движки: $eng_desc
  9. Тема: $theme / $style
 10. Доступ: $acc_desc (JSON API отключён)
 11. Метод запросов: $method

SUM
        read -rp "$(_t PROMPT_SETTINGS)" c || true
        case "$c" in
            1) locale="$(ask "Язык интерфейса (код: ru/en/de/fr/...)" "$locale")" ;;
            2)
                echo "Область поиска:"
                echo "  auto  — глобальный поиск без привязки к региону"
                echo "  ru    — русскоязычные результаты"
                echo "  ru-RU — русскоязычные, приоритет России"
                echo "  en-US / en-GB / de-DE / fr-FR / ... — приоритет конкретного региона"
                slang="$(ask "Значение" "$slang")" ;;
            3) safe="$(ask "SafeSearch: 0=выкл, 1=умеренный, 2=строгий" "$safe")" ;;
            4)
                if [[ -n "$autocomplete" ]]; then autocomplete=""; log "Автокомплит выключен (нажатия клавиш не утекают наружу)."
                else autocomplete="$(ask "Провайдер подсказок: duckduckgo / brave / swisscows" "duckduckgo")"; fi ;;
            5) [[ "$tracker" == "true" ]] && tracker="false" || tracker="true" ;;
            6)
                echo "DOI — идентификатор научной статьи (10.xxxx/yyyy); официальная ссылка обычно"
                echo "ведёт на платный доступ. sci-hub отдаёт PDF бесплатно — легально спорно,"
                echo "ответственность за использование на вас."
                if [[ "$scihub" == "true" ]]; then scihub="false"; else
                    ask_yn "Включить редирект DOI -> sci-hub?" && scihub="true" || scihub="false"
                fi ;;
            7) [[ "$converter" == "true" ]] && converter="false" || converter="true" ;;
            8)
                cat <<'ENG'
 Движки (вводите номера через запятую; def — набор по умолчанию):
   1 google          2 bing           3 duckduckgo      4 brave
   5 startpage       6 mojeek         7 yandex          8 wikipedia
   9 wikidata       10 google images  11 bing images    12 youtube
  13 vimeo          14 google news    15 bing news      16 arxiv
  17 pubmed         18 github         19 stackoverflow  20 reddit
ENG
                local sel n
                sel="$(ask "Ваш выбор" "def")"
                if [[ "$sel" == "def" || -z "$sel" ]]; then
                    engines_mode="default"; engines_list=""
                else
                    local -a all=(google bing duckduckgo brave startpage mojeek yandex wikipedia wikidata "google images" "bing images" youtube vimeo "google news" "bing news" arxiv pubmed github stackoverflow reddit)
                    engines_mode="custom"; engines_list=""
                    for n in ${sel//,/ }; do
                        [[ "$n" =~ ^[0-9]+$ ]] || { warn "пропускаю '$n'"; continue; }
                        (( n >= 1 && n <= ${#all[@]} )) || { warn "нет движка №$n"; continue; }
                        engines_list+="${all[$((n-1))]}"$'\n'
                    done
                    [[ -z "$engines_list" ]] && { engines_mode="default"; warn "пустой выбор — оставляю набор по умолчанию"; }
                fi ;;
            9)
                theme="$(ask "Тема: simple / oscar" "$theme")"
                [[ "$theme" == "simple" ]] && style="$(ask "Стиль simple: auto / dark / light" "$style")" ;;
            10)
                echo "Варианты доступа:"
                echo " 1) приватный — basicauth-пароль (рекомендуется)"
                echo " 2) публичный — для всех + антибот-limiter"
                echo " 3) открытый — без защиты (быстро найдут боты)"
                access="$(ask "1/2/3" "1")"
                case "$access" in
                    1) access="private"
                       auth_user="$(ask "Логин" "search")"
                       auth_pw="$(ask "Пароль (Enter — сгенерировать)" "${SEARCH_PW:-$(gen_pass)}")"
                       update_env SEARCH_PW "$auth_pw" ;;
                    2) access="public"; update_env SEARCH_PW "" ;;
                    *) access="open"; warn "открытый инстанс без защиты — на свой риск."; update_env SEARCH_PW "" ;;
                esac ;;
            11)
                echo "GET — ссылки на выдачу можно пересылать и букмаркить, но запросы остаются"
                echo "      в истории браузера и в логах сервера."
                echo "POST — запросы не светятся в истории и реферерах, но ссылку на выдачу"
                echo "       не сохранить и не переслать."
                method="$(ask "GET/POST" "$method")" ;;
            L|l|Д|д) logs_menu searxng ;;
            "") break ;;
            *) warn "нет такого пункта" ;;
        esac
    done

    [[ "$access" == "private" ]] && mk_htpasswd search "$auth_user" "$auth_pw"
    local limiter="false"; [[ "$access" == "public" ]] && limiter="true"

    # --- сборка YAML ---
    local uds="use_default_settings: true" e
    if [[ "$engines_mode" == "custom" ]]; then
        uds="use_default_settings:"$'\n'"  engines:"$'\n'"    keep_only:"
        while IFS= read -r e; do [[ -n "$e" ]] && uds+=$'\n'"      - $e"; done <<< "$engines_list"
    fi

    local plugins_yaml="" doi_yaml=""
    [[ "$scihub" == "true" ]] && {
        plugins_yaml+="  searx.plugins.oa_doi_rewrite.SXNGPlugin:"$'\n'"    active: true"$'\n'
        doi_yaml="doi_resolvers:"$'\n'"  sci-hub: https://sci-hub.se/"$'\n'
    }
    [[ "$tracker" == "false" ]] && plugins_yaml+="  searx.plugins.tracker_url_remover.SXNGPlugin:"$'\n'"    active: false"$'\n'
    [[ "$converter" == "false" ]] && plugins_yaml+="  searx.plugins.unit_converter.SXNGPlugin:"$'\n'"    active: false"$'\n'
    [[ -n "$plugins_yaml" ]] && plugins_yaml="plugins:"$'\n'"$plugins_yaml"

    mkdir -p "$DATA_DIR/searxng"
    cat > "$DATA_DIR/searxng/settings.yml" <<EOF
$uds
general:
  instance_name: "$sname"
search:
  safe_search: $safe
  language: "$slang"
  autocomplete: "$autocomplete"
  method: "$method"
  formats: [html]
server:
  secret_key: "$SEARXNG_SECRET"
  base_url: "https://$SUB_SEARCH/"
  limiter: $limiter
  image_proxy: $imgproxy
ui:
  static_use_hash: true
  default_locale: "$locale"
  default_theme: $theme
  theme_args:
    simple_style: $style
$doi_yaml$plugins_yaml
outgoing:
  request_timeout: 10.0
EOF

    docker compose up -d searxng
    local search_auth=""
    [[ "$access" == "private" ]] && search_auth=$(auth_conf search "Search")
    add_site 40-search "server {
    listen 8443 ssl;
    server_name $SUB_SEARCH;
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
${search_auth}    location / {
        proxy_pass http://searxng:8080;
        include /etc/nginx/proxy_common.conf;
    }
}"
    log "Готово: https://$SUB_SEARCH"
}
