#!/usr/bin/env bash
# Откат Helios на другой релиз: переключает симлинк current, ничего не копируя.
#
#   rollback.sh <ветка> [релиз]   без релиза — предыдущий по списку
#   rollback.sh <ветка> list      показать доступные релизы
set -euo pipefail

HOST=helios.cs.ifmo.ru
PORT=2222
USER_=s505996
BRANCH=${1:?ветка}
WANT=${2:-}

SSH=(ssh -p "$PORT" -o BatchMode=yes -o UserKnownHostsFile="$(dirname "$0")/known_hosts")
[ -n "${HELIOS_KEY:-}" ] && SSH+=(-i "$HELIOS_KEY")

if [ "$BRANCH" = main ]; then
  DIR=nir
else
  DIR="nir-preview/$(echo "$BRANCH" | tr '/A-Z' '-a-z')"
fi

"${SSH[@]}" "$USER_@$HOST" "
  set -e
  cd ~/nir-deploy/$DIR
  current=\$(basename \$(readlink current))
  if [ '$WANT' = list ]; then
    echo 'релизы (текущий помечен *):'
    ls -1 releases | sort -r | sed \"s|^\$current\$|* &|\"
    exit 0
  fi
  # без аргумента — предыдущий релиз в списке, отсортированном по дате
  want='$WANT'
  [ -n \"\$want\" ] || want=\$(ls -1 releases | sort -r | grep -A1 -x \"\$current\" | tail -1)
  # страховка: неполный каталог откатом не публикуем
  [ -f \"releases/\$want/index.html\" ] || { echo \"нет полного релиза \$want\" >&2; exit 1; }
  ln -sfn releases/\$want current.tmp && mv -fh current.tmp current
  echo \"откат: \$current → \$want\"
"
