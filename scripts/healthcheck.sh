#!/usr/bin/env bash
# Проверка опубликованного сайта «снаружи», как его видит посетитель.
#   healthcheck.sh <url> <expected_sha>
# Падает (exit 1), если хоть одна проверка не прошла за все попытки.
# Повторы нужны из-за кэшей: CDN GitHub Pages отдаёт новую версию не мгновенно.
set -uo pipefail

URL=${1:?url}; SHA=${2:?sha}
URL="${URL%/}/"
ATTEMPTS=${HC_ATTEMPTS:-6}; DELAY=${HC_DELAY:-10}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch <path> → код ответа; тело в $TMP/body
  curl -sS -L --max-time 20 -H 'Cache-Control: no-cache' -o "$TMP/body" -w '%{http_code}' "$URL$1?hc=$RANDOM" 2>"$TMP/err" || echo 000
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
  expect "" "главная, метка сборки" "<meta name=\"nir-build\" content=\"$SHA\">"
  expect "results/figures/" "страница рисунков" "Рис. 1."
  expect "results/tables/" "страница таблиц" "Таблица 13."
  expect "method/" "страница с формулами" 'class="arithmatex"'
  expect "search/search_index.json" "индекс поиска" "three.js"
  expect "assets/katex/katex.min.js" "KaTeX с сайта, не с CDN"
  expect "assets/katex/fonts/KaTeX_Main-Regular.woff2" "шрифт KaTeX"
  expect "results/provenance.json" "метаданные происхождения" '"results_tree"'
  code=$(fetch "no-such-page-$RANDOM/")
  [ "$code" = 404 ] && echo "  ✓ несуществующая страница → 404" || { echo "  ✗ несуществующая страница → HTTP $code"; fails=$((fails + 1)); }
  return "$fails"
}

for i in $(seq 1 "$ATTEMPTS"); do
  echo "healthcheck $URL (попытка $i/$ATTEMPTS)"
  if check; then echo "healthcheck: OK"; exit 0; fi
  [ "$i" -lt "$ATTEMPTS" ] && sleep "$DELAY"
done
echo "healthcheck: FAIL — опубликованная версия не соответствует $SHA" >&2
exit 1
