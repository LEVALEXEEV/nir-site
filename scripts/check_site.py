#!/usr/bin/env python3
"""
Проверка собранного сайта до выкладки — то, чего не ловит `mkdocs build --strict`:

* ссылки от корня домена (`href="/..."`): на GitHub Pages сайт живёт в
  /nir-site/, на Helios — в /~s505996/nir/, и такая ссылка ведёт мимо сайта;
* внешние скрипты, стили и шрифты: сайт обязан работать без CDN;
* наличие индекса поиска и локального KaTeX.

Ссылки в <a> на внешние сайты разрешены — это навигация, а не ресурс страницы.
"""
from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path

RESOURCE_ATTRS = {("script", "src"), ("link", "href"), ("img", "src"), ("source", "src"), ("iframe", "src")}


class Refs(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.refs: list[tuple[str, str, str]] = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if value and name in ("href", "src"):
                self.refs.append((tag, name, value))


def main(site: Path) -> int:
    errors: list[str] = []
    for page in sorted(site.rglob("*.html")):
        rel = page.relative_to(site)
        parser = Refs()
        parser.feed(page.read_text(encoding="utf-8"))
        for tag, attr, url in parser.refs:
            # 404.html по устройству MkDocs ссылается абсолютными путями из site_url — это верно
            if url.startswith("/") and not url.startswith("//") and rel.name != "404.html":
                errors.append(f"{rel}: ссылка от корня домена <{tag} {attr}=\"{url}\">")
            if (tag, attr) in RESOURCE_ATTRS and re.match(r"(https?:)?//", url):
                # canonical и прочие <link rel> на сам сайт ресурсами не являются
                if tag == "link" and not re.search(r"stylesheet|preload|icon|modulepreload", str(page.read_text()).split(url)[0][-120:]):
                    continue
                errors.append(f"{rel}: внешний ресурс <{tag} {attr}=\"{url}\">")
    for css in site.rglob("*.css"):
        for url in re.findall(r"url\(\s*['\"]?((?:https?:)?//[^)'\"]+)", css.read_text(encoding="utf-8")):
            errors.append(f"{css.relative_to(site)}: внешний ресурс в CSS {url}")
    for required in ("search/search_index.json", "assets/katex/katex.min.js", "assets/katex/fonts/KaTeX_Main-Regular.woff2"):
        if not (site / required).exists():
            errors.append(f"нет файла {required}")
    for e in errors:
        print(f"::error::{e}" if "GITHUB_ACTIONS" in __import__("os").environ else e)
    print(f"check_site: {len(list(site.rglob('*.html')))} страниц, ошибок {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "site")))
