#!/usr/bin/env bash
# Кладёт KaTeX в docs/assets/katex: формулы должны рендериться без внешних CDN
# (Helios и часть сетей могут не пускать к jsdelivr/unpkg). Проверяет целостность
# архива по хешу из реестра npm — версия и хеш зафиксированы здесь.
set -euo pipefail
VERSION=0.18.7
INTEGRITY="sha512-h+UCwkZ+4Jz8WQ7MLGfj7UVFrRCizGb912fwF4luGdYsC5paYG1vx+jy+KRcC/XkpjGva/P7nAWuxNnPzRvzHw=="
DEST="$(cd "$(dirname "$0")/.." && pwd)/docs/assets/katex"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

curl -fsSL "https://registry.npmjs.org/katex/-/katex-$VERSION.tgz" -o "$TMP/katex.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$TMP/katex.tgz" | openssl base64 -A)"
[ "$actual" = "$INTEGRITY" ] || { echo "KaTeX: хеш архива не совпал" >&2; exit 1; }

tar -xzf "$TMP/katex.tgz" -C "$TMP"
rm -rf "$DEST" && mkdir -p "$DEST/contrib"
cp "$TMP/package/dist/katex.min.js" "$TMP/package/dist/katex.min.css" "$TMP/package/LICENSE" "$DEST/"
cp "$TMP/package/dist/contrib/auto-render.min.js" "$DEST/contrib/"
# только woff2: его понимают все поддерживаемые браузеры, ttf/woff лишь раздувают сайт
mkdir -p "$DEST/fonts" && cp "$TMP/package/dist/fonts/"*.woff2 "$DEST/fonts/"
echo "KaTeX $VERSION → $DEST ($(du -sh "$DEST" | cut -f1))"
