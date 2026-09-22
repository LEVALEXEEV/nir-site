#!/usr/bin/env bash
# Выкладка собранного сайта на Helios по SSH/rsync.
#
#   deploy.sh upload <site_dir> <branch> <sha>   загрузить релиз и опубликовать
#   deploy.sh rollback <branch> [release_id]    вернуть предыдущий (или указанный) релиз
#   deploy.sh list <branch>                     релизы и журнал
#   deploy.sh remove <branch>                   удалить превью ветки
#   deploy.sh target <branch>                   имя цели и публичный URL (для CI)
#
# Ключ: HELIOS_KEY (путь к приватному deploy-ключу) или ssh-agent.
# Хост проверяется по known_hosts (в CI — из секрета), без слепого доверия.
set -euo pipefail

HOST=${HELIOS_HOST:-helios.cs.ifmo.ru}
PORT=${HELIOS_PORT:-2222}
USER_=${HELIOS_USER:-s505996}
BASE_URL=${HELIOS_BASE_URL:-https://se.ifmo.ru/~s505996/nir/}
MAIN_BRANCH=${MAIN_BRANCH:-main}
HERE="$(cd "$(dirname "$0")" && pwd)"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20
          -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
[ -n "${HELIOS_KEY:-}" ] && SSH_OPTS+=(-i "$HELIOS_KEY" -o IdentitiesOnly=yes)
[ -n "${HELIOS_KNOWN_HOSTS:-}" ] && SSH_OPTS+=(-o UserKnownHostsFile="$HELIOS_KNOWN_HOSTS")

# ветка → цель и URL: основная ветка в корень, остальные — в preview/<slug>/
target_of() {
  if [ "$1" = "$MAIN_BRANCH" ]; then echo main; return; fi
  local slug
  slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40)
  [ -n "$slug" ] || { echo "пустое имя ветки" >&2; exit 1; }
  echo "preview-$slug"
}
url_of() { [ "$1" = main ] && echo "$BASE_URL" || echo "${BASE_URL}preview/${1#preview-}/"; }

remote() { ssh "${SSH_OPTS[@]}" "$USER_@$HOST" sh -s -- "$@" < "$HERE/remote.sh"; }

cmd=${1:?команда}; shift
case "$cmd" in
  target)
    t=$(target_of "$1"); echo "target=$t"; echo "url=$(url_of "$t")" ;;

  upload)
    site=${1:?каталог сайта} branch=${2:?ветка} sha=${3:?коммит}
    [ -f "$site/index.html" ] || { echo "в $site нет index.html" >&2; exit 1; }
    t=$(target_of "$branch")
    id="$(date -u +%Y%m%dT%H%M%SZ)-${sha:0:7}"
    started=$(date +%s)
    # Apache Helios понимает .htaccess; путь к 404.html — от корня домена и свой
    # у каждой цели (корень или preview/<slug>/), поэтому пишется здесь, а не в docs/
    printf 'ErrorDocument 404 %s404.html\n' "$(url_of "$t" | sed -E 's#^https?://[^/]+##')" > "$site/.htaccess"
    prev=$(remote prepare "$t")
    echo "helios: цель $t, релиз $id, текущий ${prev:-нет}"
    # новый релиз — отдельный каталог; неизменённые файлы — жёсткие ссылки на
    # текущий релиз (--link-dest), так что передаётся только разница
    link=(); [ -n "$prev" ] && link=(--link-dest="../$prev")
    rsync -rlz --delete --partial --timeout=120 ${link[@]+"${link[@]}"} \
      --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
      -e "ssh ${SSH_OPTS[*]}" "$site/" "$USER_@$HOST:nir-deploy/releases/$t/.incoming-$id/"
    remote activate "$t" "$id" "$sha"
    echo "helios: загружено и опубликовано за $(( $(date +%s) - started )) с → $(url_of "$t")"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      { echo "release=$id"; echo "previous=$prev"; echo "url=$(url_of "$t")"; } >> "$GITHUB_OUTPUT"
    fi
    ;;

  rollback) remote rollback "$(target_of "${1:?ветка}")" ${2:+"$2"} ;;
  list)     remote list "$(target_of "${1:?ветка}")" ;;
  remove)   remote remove "$(target_of "${1:?ветка}")" ;;
  *) echo "команда: upload | rollback | list | remove | target" >&2; exit 2 ;;
esac
