#!/bin/sh
# Серверная часть деплоя на Helios (FreeBSD, /bin/sh). Не устанавливается на
# сервер, а передаётся по ssh при каждом вызове: `ssh helios sh -s -- cmd … < remote.sh`,
# поэтому логика версионируется вместе с сайтом.
#
# Раскладка (DEPLOY_ROOT=~/nir-deploy):
#   releases/<target>/<id>/        полные копии сайта; <target> = main | preview-<slug>
#   releases/<target>/.incoming-*  недокачанный релиз (обрыв rsync) — не публикуется
#   releases/<target>/history.log  журнал: время, действие, id, коммит
#   live/main                      → ../releases/main/<id>      (~/public_html/nir → сюда)
#   live/preview/<slug>            → ../../releases/preview-<slug>/<id>
# Каждый релиз main содержит ссылку preview → live/preview, поэтому превью
# доступны как …/nir/preview/<slug>/. Публикация = атомарная замена симлинка
# (rename), так что посетитель видит либо старую версию, либо новую целиком.
set -eu

ROOT="$HOME/nir-deploy"
PUBLIC_LINK="$HOME/public_html/nir"
KEEP=5

die() { echo "remote: $*" >&2; exit 1; }

live_link() {  # путь симлинка, через который публикуется цель
  case "$1" in
    main) echo "$ROOT/live/main" ;;
    preview-*) echo "$ROOT/live/preview/${1#preview-}" ;;
    *) die "неизвестная цель $1" ;;
  esac
}

current_id() { l=$(live_link "$1"); [ -L "$l" ] && basename "$(readlink "$l")" || true; }

switch() {  # switch <target> <id>: атомарно направить live-ссылку на релиз
  target=$1 id=$2 link=$(live_link "$1")
  rel="$ROOT/releases/$target/$id"
  [ -d "$rel" ] || die "нет релиза $target/$id"
  mkdir -p "$(dirname "$link")"
  ln -sfn "$rel" "$link.tmp.$$"
  mv -fh "$link.tmp.$$" "$link"   # rename(2): атомарно, без окна «сайта нет»
}

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$ROOT/releases/$1/history.log"; }

cmd=${1:-}; shift || true
case "$cmd" in
  prepare)  # prepare <target>: каталоги, убрать обрывки прошлых деплоев, вывести id текущего релиза
    target=$1
    mkdir -p "$ROOT/releases/$target" "$ROOT/live/preview"
    chmod 755 "$HOME" "$ROOT" "$ROOT/releases" "$ROOT/releases/$target" "$ROOT/live" "$ROOT/live/preview"
    for d in "$ROOT/releases/$target"/.incoming-*; do
      [ -e "$d" ] || continue
      echo "remote: удаляю недокачанный релиз $(basename "$d")" >&2
      rm -rf "$d"
    done
    if [ "$target" = main ] && [ -e "$PUBLIC_LINK" ] && [ ! -L "$PUBLIC_LINK" ]; then
      die "$PUBLIC_LINK — не симлинк; не трогаю чужие файлы"
    fi
    current_id "$target"
    ;;

  activate)  # activate <target> <id> <sha>: принять загруженный релиз и опубликовать его
    target=$1 id=$2 sha=$3
    dir="$ROOT/releases/$target"
    [ -d "$dir/.incoming-$id" ] || die "нет загруженного $target/.incoming-$id"
    [ -f "$dir/.incoming-$id/index.html" ] || die "в релизе нет index.html — загрузка неполная"
    [ "$target" = main ] && ln -sfn "$ROOT/live/preview" "$dir/.incoming-$id/preview"
    mv "$dir/.incoming-$id" "$dir/$id"
    prev=$(current_id "$target")
    switch "$target" "$id"
    [ "$target" = main ] && [ ! -L "$PUBLIC_LINK" ] && ln -s "$ROOT/live/main" "$PUBLIC_LINK"
    log "$target" "deploy $id $sha prev=${prev:-none}"
    # чистка: хранятся KEEP последних релизов; текущий и предыдущий не удаляются никогда
    ls -1 "$dir" | grep -v '^history.log$' | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
      [ "$old" = "$id" ] || [ "$old" = "$prev" ] || { rm -rf "${dir:?}/$old"; echo "remote: удалён старый релиз $old" >&2; }
    done
    echo "remote: $target → $id (было ${prev:-ничего})"
    ;;

  rollback)  # rollback <target> [id]: вернуть указанный релиз или предыдущий по журналу
    target=$1 want=${2:-}
    cur=$(current_id "$target")
    if [ -z "$want" ]; then
      # предыдущий = последний релиз из журнала, отличный от текущего и ещё существующий
      want=$(awk '$2=="deploy"||$2=="rollback"{print $3}' "$ROOT/releases/$target/history.log" \
             | grep -vx "$cur" | tail -r | while read -r id; do
                 [ -d "$ROOT/releases/$target/$id" ] && { echo "$id"; break; }; done)
      [ -n "$want" ] || die "нет релиза для отката"
    fi
    switch "$target" "$want"
    log "$target" "rollback $want from=$cur"
    echo "remote: $target откатан $cur → $want"
    ;;

  list)  # list <target>: релизы и журнал
    target=$1 cur=$(current_id "$target")
    for r in $(ls -1 "$ROOT/releases/$target" | grep -v '^history.log$' | sort -r); do
      [ "$r" = "$cur" ] && echo "* $r (текущий)" || echo "  $r"
    done
    echo "--- журнал"; tail -n 10 "$ROOT/releases/$target/history.log" 2>/dev/null || true
    ;;

  remove)  # remove <target>: удалить превью ветки целиком (ветка удалена)
    target=$1
    case "$target" in preview-*) ;; *) die "удалять можно только превью" ;; esac
    rm -f "$(live_link "$target")"
    rm -rf "${ROOT:?}/releases/$target"
    echo "remote: превью $target удалено"
    ;;

  *) die "команда: prepare | activate | rollback | list | remove" ;;
esac
