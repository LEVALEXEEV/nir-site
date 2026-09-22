# nir-site — результаты НИР «three.js vs react-three-fiber»

Статический сайт (MkDocs + Material) с рисунками и таблицами исследования.
Рисунки и таблицы не хранятся здесь: при каждой сборке ноутбук анализа
исполняется на данных из подмодуля [`benchmark`](https://github.com/LEVALEXEEV/benchmark)
на зафиксированном коммите.

* GitHub Pages: https://levalexeev.github.io/nir-site/
* Helios ИТМО: https://se.ifmo.ru/~s505996/nir/ (ветки — `…/nir/preview/<ветка>/`)

## Локально

```bash
git clone --recurse-submodules https://github.com/LEVALEXEEV/nir-site.git && cd nir-site
virtualenv -p python3.13 .venv && source .venv/bin/activate
pip install -r requirements.txt
make serve                 # content + mkdocs serve → http://127.0.0.1:8000/
make site                  # сборка как в CI: --strict + check_site.py
```

| Путь | Что |
|---|---|
| `scripts/build_content.py` | ноутбук → `docs/results/` (отчёт, рисунки, таблицы, provenance) |
| `content/captions.yml` | подписи ко всем рисункам и таблицам |
| `scripts/check_site.py` | запрет ссылок от корня домена и внешних ресурсов |
| `scripts/helios/` | деплой на Helios: `deploy.sh` (клиент), `remote.sh` (сервер), `known_hosts` |
| `scripts/healthcheck.sh` | проверка опубликованного URL |
| `.github/workflows/site.yml` | сборка → Pages + Helios, healthcheck, автооткат |
| `.github/workflows/helios-ops.yml` | ручной откат / список релизов, удаление превью |

Обновить данные: `git -C benchmark pull && git add benchmark && git commit`.

## Лицензии

Код — [MIT](LICENSE). Тексты, рисунки, таблицы — [CC BY 4.0](LICENSE-CONTENT).
