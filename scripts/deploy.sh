#!/usr/bin/env bash
# Выкладка собранного сайта на Helios.
#
#   deploy.sh <каталог_сайта> <ветка>
#
# Файлы сначала едут в каталог releases/<дата>.partial, который нигде не
# опубликован. Он переименовывается в releases/<дата> только после полной
# передачи, и лишь затем на него переключается симлинк current. Поэтому обрыв
# связи посреди выкладки не виден посетителям: сайт продолжает отдавать
# прежнюю версию, а недокачанный каталог удаляется при следующей выкладке.
#
# Ключ: переменная HELIOS_KEY (в CI — из секрета репозитория).
set -euo pipefail

HOST=helios.cs.ifmo.ru
PORT=2222
USER_=s505996
SITE=${1:?каталог сайта}
BRANCH=${2:?ветка}

[ -f "$SITE/index.html" ] || { echo "в $SITE нет index.html — сайт не собран" >&2; exit 1; }

SSH=(ssh -p "$PORT" -o BatchMode=yes -o UserKnownHostsFile="$(dirname "$0")/known_hosts")
[ -n "${HELIOS_KEY:-}" ] && SSH+=(-i "$HELIOS_KEY")

# main публикуется в корень сайта, остальные ветки — в отдельный подкаталог:
# ~/public_html/nir  и  ~/public_html/nir-preview/<ветка>
if [ "$BRANCH" = main ]; then
  DIR=nir
else
  DIR="nir-preview/$(echo "$BRANCH" | tr '/A-Z' '-a-z')"
fi
RELEASE=$(date -u +%Y%m%d-%H%M%S)

echo "Выкладка ветки $BRANCH → ~/public_html/$DIR (релиз $RELEASE)"

# 1. Каталог для загрузки: rsync сам вложенные каталоги не создаёт
"${SSH[@]}" "$USER_@$HOST" "mkdir -p ~/nir-deploy/$DIR/releases/$RELEASE.partial"

# 2. Передача файлов
rsync -rlz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r -e "${SSH[*]}" \
  "$SITE/" "$USER_@$HOST:nir-deploy/$DIR/releases/$RELEASE.partial/"

# 3. Публикация: релиз готов → переименование → переключение симлинка.
#    ln -sfn + mv -h меняют ссылку одной атомарной операцией.
"${SSH[@]}" "$USER_@$HOST" "
  set -e
  cd ~/nir-deploy/$DIR
  mv releases/$RELEASE.partial releases/$RELEASE
  ln -sfn releases/$RELEASE current.tmp && mv -fh current.tmp current
  mkdir -p ~/public_html/$(dirname "$DIR")
  ln -sfn ~/nir-deploy/$DIR/current ~/public_html/$DIR
  rm -rf releases/*.partial
  ls -1 releases | sort -r | tail -n +6 | xargs -I{} rm -rf releases/{}   # храним 5 версий
  echo 'опубликован релиз $RELEASE'
"
