#!/usr/bin/env bash
# Выкладка собранного сайта на Helios: rsync в новый каталог релиза,
# затем переключение симлинка на него. Пока симлинк не переключён,
# посетители видят прежнюю версию, а недокачанный релиз никому не виден.
#
#   deploy.sh <каталог_сайта> <ветка>
#
# Ключ: HELIOS_KEY (в CI — из секрета). Ветка main публикуется в корень сайта,
# остальные ветки — в отдельный подкаталог preview.
set -euo pipefail

HOST=helios.cs.ifmo.ru
PORT=2222
USER_=s505996
SITE=${1:?каталог сайта}
BRANCH=${2:?ветка}

SSH=(ssh -p "$PORT" -o BatchMode=yes -o UserKnownHostsFile="$(dirname "$0")/known_hosts")
[ -n "${HELIOS_KEY:-}" ] && SSH+=(-i "$HELIOS_KEY")

# main → ~/public_html/nir, ветка feature/x → ~/public_html/nir-preview/feature-x
if [ "$BRANCH" = main ]; then
  DIR=nir
else
  DIR="nir-preview/$(echo "$BRANCH" | tr '/A-Z' '-a-z')"
fi
RELEASE=$(date -u +%Y%m%d-%H%M%S)

echo "Выкладка ветки $BRANCH → ~/public_html/$DIR (релиз $RELEASE)"

# 1. Каталог релиза создаётся заранее: rsync сам вложенные каталоги не создаёт
"${SSH[@]}" "$USER_@$HOST" "mkdir -p ~/nir-deploy/$DIR/releases/$RELEASE"

# 2. Файлы едут в releases/<дата>, который ещё нигде не опубликован
rsync -rlz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r -e "${SSH[*]}" \
  "$SITE/" "$USER_@$HOST:nir-deploy/$DIR/releases/$RELEASE/"

# 3. Публикация: симлинк public_html/... переключается на новый релиз.
#    ln -sfn + mv — одна атомарная операция, промежуточного состояния нет.
#    Старые релизы хранятся (нужны для отката), остаются последние 5.
"${SSH[@]}" "$USER_@$HOST" "
  set -e
  cd ~/nir-deploy/$DIR
  ln -sfn releases/$RELEASE current.tmp && mv -fh current.tmp current
  mkdir -p ~/public_html/$(dirname "$DIR")
  ln -sfn ~/nir-deploy/$DIR/current ~/public_html/$DIR
  ls -1 releases | sort -r | tail -n +6 | xargs -I{} rm -rf releases/{}
  echo 'опубликован релиз $RELEASE'
"
