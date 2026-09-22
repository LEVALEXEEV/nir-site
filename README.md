# nir-site — сайт с результатами НИР «three.js vs react-three-fiber»

Статический сайт на MkDocs + Material. Готовые рисунки, таблицы и отчёт
анализа лежат в `docs/` — при сборке ничего не вычисляется.

* GitHub Pages: https://levalexeev.github.io/nir-site/
* Helios ИТМО: https://se.ifmo.ru/~s505996/nir/
* Превью веток: https://se.ifmo.ru/~s505996/nir-preview/&lt;ветка&gt;/

## Локально

```bash
make install     # виртуальное окружение и зависимости
make serve       # предпросмотр на http://127.0.0.1:8000/
make build       # сборка в site/
```

## Что где лежит

| Путь | Что |
|---|---|
| `docs/` | страницы сайта, рисунки, таблицы, ноутбук, KaTeX |
| `mkdocs.yml` | настройки сайта: разделы, тема, формулы |
| `scripts/deploy.sh` | выкладка на Helios по rsync с переключением симлинка |
| `scripts/rollback.sh` | откат на предыдущий релиз (и список релизов) |
| `scripts/healthcheck.sh` | проверка опубликованного сайта снаружи |
| `scripts/vendor_katex.sh` | скачивание KaTeX в `docs/assets/katex` |
| `.github/workflows/site.yml` | сборка и публикация на Pages и Helios |
| `.github/workflows/rollback.yml` | ручной откат Helios |

## Деплой вручную

```bash
mkdocs build --strict
HELIOS_KEY=~/.ssh/helios_deploy scripts/deploy.sh site main
scripts/healthcheck.sh https://se.ifmo.ru/~s505996/nir/ $(git rev-parse HEAD)
HELIOS_KEY=~/.ssh/helios_deploy scripts/rollback.sh main list
```

## Лицензии

Код — [MIT](LICENSE). Тексты, рисунки, таблицы — [CC BY 4.0](LICENSE-CONTENT).
