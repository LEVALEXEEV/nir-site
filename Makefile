# Локальная работа с сайтом.
.PHONY: install serve build

install:                     # окружение и зависимости
	virtualenv -p python3.13 .venv && .venv/bin/pip install -r requirements.txt

serve:                       # предпросмотр на http://127.0.0.1:8000/
	.venv/bin/mkdocs serve

build:                       # сборка сайта в site/
	.venv/bin/mkdocs build --strict
