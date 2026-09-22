#!/usr/bin/env bash
# Проверка опубликованного сайта «снаружи», как его видит посетитель.
#   healthcheck.sh <url> <expected_sha>
# Падает (exit 1), если хоть одна проверка не прошла за все попытки.
# Повторы нужны из-за кэшей: CDN GitHub Pages отдаёт новую версию не мгновенно.
# Если главная не отвечает как надо, попытка прерывается сразу: se.ifmo.ru
# перестаёт отвечать IP, с которого идёт серия ошибочных запросов, а десятки
# запросов с таймаутом по 20 с выводили job за её лимит (и автооткат не выполнялся).
set -uo pipefail

URL=${1:?url}; SHA=${2:?sha}
URL="${URL%/}/"
ATTEMPTS=${HC_ATTEMPTS:-5}; DELAY=${HC_DELAY:-10}; DEADLINE=$(( $(date +%s) + ${HC_DEADLINE:-150} ))
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch <path> → код ответа; тело в $TMP/body
  # при ошибке соединения curl сам печатает 000 — «|| echo 000» дал бы 000000
  curl -sS -L --connect-timeout 5 --max-time 10 -H 'Cache-Control: no-cache' -o "$TMP/body" -w '%{http_code}' "$URL$1?hc=$RANDOM" 2>"$TMP/err" || true
}

check() {
  local fails=0 code
  expect() {  # expect <path> <описание> [строка в теле]
    code=$(fetch "$1")
    if [ "$code" != 200 ]; then echo "  ✗ $2: HTTP $code ($URL$1)"; fails=$((fails + 1)); return; fi
    if [ -n "${3:-}" ] && ! grep -qF -- "$3" "$TMP/body"; then
      echo "  ✗ $2: HTTP 200, но нет «$3»"; fails=$((fails + 1)); return
    fi
    echo "  ✓ $2"
  }
  # контрольная строка — метка именно этой сборки, а не любой прошлой
  # SHA может быть коротким (откат по id релиза) — сравнивается префикс
  expect "" "главная, метка сборки" "<meta name=\"nir-build\" content=\"$SHA"
  [ "$fails" = 0 ] || return 1   # не та версия или сайт недоступен — остальное проверять незачем
  expect "results/figures/" "страница рисунков" "Рис. 1."
  expect "results/tables/" "страница таблиц" "Таблица 13."
  expect "method/" "страница с формулами" 'class="arithmatex"'
  expect "search/search_index.json" "индекс поиска" "three.js"
  expect "assets/katex/katex.min.js" "KaTeX с сайта, не с CDN"
  expect "assets/katex/fonts/KaTeX_Main-Regular.woff2" "шрифт KaTeX"
  # главный бандл JS должен приходить сжатым (на Helios — через .gz-копии, см. deploy.sh)
  bundle=$(fetch "" >/dev/null; grep -o 'assets/javascripts/bundle\.[0-9a-f]*\.min\.js' "$TMP/body" | head -1)
  if curl -s -o /dev/null -D - -H 'Accept-Encoding: gzip' --max-time 10 "$URL$bundle" | grep -qi '^content-encoding: gzip'; then
    echo "  ✓ JS отдаётся сжатым (gzip)"
  else echo "  ✗ $bundle отдаётся без сжатия"; fails=$((fails + 1)); fi
  expect "results/provenance.json" "метаданные происхождения" '"results_tree"'
  # 404 должна быть страницей сайта (со стилями по site_url), а не заглушкой веб-сервера
  code=$(fetch "no-such-page-$RANDOM/")
  if [ "$code" = 404 ] && grep -qF 'name="nir-build"' "$TMP/body"; then echo "  ✓ несуществующая страница → 404 сайта"
  else echo "  ✗ несуществующая страница → HTTP $code или 404 не от сайта"; fails=$((fails + 1)); fi
  return "$fails"
}

for i in $(seq 1 "$ATTEMPTS"); do
  echo "healthcheck $URL (попытка $i/$ATTEMPTS)"
  if check; then echo "healthcheck: OK"; exit 0; fi
  if [ "$i" -lt "$ATTEMPTS" ] && [ $(( $(date +%s) + DELAY )) -lt "$DEADLINE" ]; then sleep "$DELAY"; else break; fi
done
echo "healthcheck: FAIL — опубликованная версия не соответствует $SHA" >&2
exit 1
