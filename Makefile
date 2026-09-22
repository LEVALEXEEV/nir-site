# Точка входа и для CI, и для локальной работы: workflow вызывает те же цели.
PY      ?= .venv/bin/python
MKDOCS  ?= .venv/bin/mkdocs
SITE_DIR ?= site

.PHONY: venv content site serve check clean

venv:
	virtualenv -p python3.13 .venv && .venv/bin/pip install -r requirements.txt

content:            ## исполнить ноутбук анализа и сгенерировать страницы docs/results
	$(PY) scripts/build_content.py

site: content       ## сборка в режиме --strict (предупреждения = ошибка)
	$(MKDOCS) build --strict --site-dir $(SITE_DIR)
	$(PY) scripts/check_site.py $(SITE_DIR)

serve: content
	$(MKDOCS) serve

check:              ## проверить уже собранный сайт
	$(PY) scripts/check_site.py $(SITE_DIR)

clean:
	rm -rf site site-* _work docs/results
