#!/usr/bin/env bash
# Проверка опубликованного сайта снаружи: отвечает ли он и та ли это версия.
#
#   healthcheck.sh <url> <ожидаемый sha коммита>
#
# Контрольная строка — <meta name="nir-build" content="<sha>"> в HTML: по ней
# видно, что отдаётся именно свежая сборка, а не старая версия из кэша.
# Несколько попыток нужны из-за кэша CDN у GitHub Pages.
set -uo pipefail

URL="${1:?url}"; URL="${URL%/}/"
SHA=${2:?sha}
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for i in 1 2 3 4 5; do
  echo "Проверка $URL (попытка $i)"
  code=$(curl -sS -L --max-time 15 -o "$TMP" -w '%{http_code}' "$URL" || true)
  if [ "$code" = 200 ] && grep -qF "content=\"$SHA\"" "$TMP"; then
    echo "OK: HTTP 200 и метка сборки $SHA на месте"
    exit 0
  fi
  echo "  пока не то: HTTP $code"
  sleep 10
done

echo "ОШИБКА: сайт не отдаёт версию $SHA" >&2
exit 1
