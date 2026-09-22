#!/usr/bin/env python3
"""
Этап «эксперимент → артефакт → страница»: из сырых результатов стенда
(подмодуль benchmark) получает рисунки, таблицы и страницы сайта.

Замеры в браузерах идут вне CI (нужны реальные устройства), а анализ лёгкий
(~30 с), поэтому он исполняется при каждой сборке: опубликованный рисунок
всегда соответствует зафиксированному коммиту benchmark, а не файлу, который
кто-то когда-то положил вручную.

Ноутбук исполняется в копии (_work/), чтобы не пачкать рабочее дерево
подмодуля. Сгенерированное попадает в docs/results/ (в .gitignore).
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from importlib import metadata
from pathlib import Path

import nbformat
import pandas as pd
import yaml
from nbconvert import MarkdownExporter
from nbconvert.preprocessors import ExecutePreprocessor

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmark"
WORK = ROOT / "_work"
OUT = ROOT / "docs" / "results"
NOTEBOOK = "nir3_analysis.ipynb"
CAPTIONS = ROOT / "content" / "captions.yml"
PACKAGES = ("numpy", "pandas", "scipy", "statsmodels", "matplotlib", "nbconvert", "mkdocs", "mkdocs-material")


def git(*args: str, cwd: Path = BENCH) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_workdir() -> Path:
    """Копия analysis/ рядом со ссылкой на results/: пути nirlib остаются прежними."""
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir()
    shutil.copytree(BENCH / "analysis", WORK / "analysis",
                    ignore=shutil.ignore_patterns("figures", "tables", "data", ".venv", "__pycache__"))
    (WORK / "results").symlink_to(BENCH / "results")
    # детерминированные SVG: без даты (SOURCE_DATE_EPOCH) и со стабильными id путей
    (WORK / "matplotlibrc").write_text("svg.hashsalt: nir3\n")
    return WORK / "analysis"


def execute_notebook(analysis: Path, commit_epoch: str) -> tuple[nbformat.NotebookNode, float]:
    os.environ["SOURCE_DATE_EPOCH"] = commit_epoch
    os.environ["MATPLOTLIBRC"] = str(WORK / "matplotlibrc")
    nb = nbformat.read(analysis / NOTEBOOK, as_version=4)
    started = time.monotonic()
    ExecutePreprocessor(timeout=1200, kernel_name="python3").preprocess(nb, {"metadata": {"path": str(analysis)}})
    elapsed = time.monotonic() - started
    nbformat.write(nb, WORK / "executed.ipynb")
    return nb, elapsed


def fmt_number(v) -> str:
    """Числа как в отчёте: 3 значащие цифры, крупные — целыми, десятичная запятая."""
    if not isinstance(v, float):
        return "" if v is None else str(v)
    if pd.isna(v):
        return "—"
    s = f"{v:,.0f}".replace(",", "\u202f") if abs(v) >= 100 else f"{v:#.3g}"
    return s.replace(".", ",")


def csv_to_markdown(path: Path) -> str:
    df = pd.read_csv(path)
    df.columns = ["" if str(c).startswith("Unnamed") else str(c).replace("\n", " ") for c in df.columns]
    cells = df.map(fmt_number).astype(str).map(lambda s: s.replace("|", "\\|").replace("\n", " "))
    lines = ["| " + " | ".join(df.columns) + " |", "|" + "---|" * len(df.columns)]
    lines += ["| " + " | ".join(row) + " |" for row in cells.itertuples(index=False)]
    return "\n".join(lines)


def check_captions(captions: dict, figures: list[str], tables: list[str]) -> None:
    missing = [f"рисунок {n}" for n in figures if n not in captions["figures"]]
    missing += [f"таблица {n}" for n in tables if n not in captions["tables"]]
    stale = [n for n in captions["figures"] if n not in figures] + [n for n in captions["tables"] if n not in tables]
    if missing or stale:
        sys.exit(f"captions.yml не соответствует артефактам: нет подписи — {missing}; нет артефакта — {stale}")


def write_report(nb: nbformat.NotebookNode) -> None:
    """Ноутбук целиком, без кода: текст анализа, таблицы и рисунки в исходном порядке."""
    exporter = MarkdownExporter(exclude_input=True, exclude_input_prompt=True, exclude_output_prompt=True)
    body, resources = exporter.from_notebook_node(nb, resources={"output_files_dir": "report_files"})
    for name, data in resources["outputs"].items():
        (OUT / name).parent.mkdir(parents=True, exist_ok=True)
        (OUT / name).write_bytes(data)
    # служебный вывод последней ячейки («рисунков: N | таблиц: M») на странице не нужен
    body = "\n".join(line for line in body.splitlines() if not line.startswith("    рисунков:"))
    header = ("# Отчёт анализа\n\n!!! info \"Страница сгенерирована\"\n"
              "    Ноутбук `analysis/nir3_analysis.ipynb` исполнен при сборке сайта на данных коммита "
              "benchmark, указанного в разделе [«Происхождение данных»](provenance.md). "
              "Код ячеек скрыт.\n\n")
    # H1 ноутбука заменяется заголовком страницы; разделы в ноутбуке уже H2
    body = body.split("\n", 1)[1] if body.startswith("# ") else body
    (OUT / "report.md").write_text(header + body)


def write_figures(captions: dict, figures: list[str], analysis: Path) -> None:
    dst = OUT / "figures"
    dst.mkdir(parents=True, exist_ok=True)
    parts = ["# Рисунки\n", "Векторные SVG, построенные при сборке. Под каждым рисунком — "
             "ссылки на SVG и PNG (200 dpi) и контрольная сумма файла.\n"]
    for name in figures:
        cap = captions["figures"][name]
        for ext in ("svg", "png"):
            shutil.copy2(analysis / "figures" / f"{name}.{ext}", dst / f"{name}.{ext}")
        parts.append(
            f"## {cap['title']} {{#{name.replace('_', '-')}}}\n\n"
            f"<figure markdown=\"span\">\n  ![{cap['title']}](figures/{name}.svg){{ loading=lazy }}\n"
            f"  <figcaption>{cap['text']}</figcaption>\n</figure>\n\n"
            f"[SVG](figures/{name}.svg) · [PNG](figures/{name}.png) · "
            f"<small>sha256 `{sha256(dst / f'{name}.svg')[:16]}`</small>\n")
    (OUT / "figures.md").write_text("\n".join(parts))


def write_tables(captions: dict, tables: list[str], analysis: Path, repro: dict[str, bool]) -> None:
    dst = OUT / "tables"
    dst.mkdir(parents=True, exist_ok=True)
    parts = ["# Таблицы\n", "Числа округлены до трёх значащих цифр; полная точность — в CSV. "
             "Отметка «воспроизведена» значит, что таблица, полученная при этой сборке, "
             "побайтно совпала с закоммиченной в benchmark.\n"]
    for name in tables:
        cap = captions["tables"][name]
        src = analysis / "tables" / f"{name}.csv"
        shutil.copy2(src, dst / f"{name}.csv")
        mark = "воспроизведена" if repro[name] else "**отличается от закоммиченной**"
        parts.append(f"## {cap['title']} {{#{name.replace('_', '-')}}}\n\n{cap['text']}\n\n{csv_to_markdown(src)}\n\n"
                     f"[CSV](tables/{name}.csv) · {mark}\n")
    (OUT / "tables.md").write_text("\n".join(parts))


def write_provenance(meta: dict) -> None:
    (OUT / "provenance.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    b, s = meta["benchmark"], meta["site"]
    repo_url = b["remote"].removesuffix(".git")
    rows = [
        ("Коммит benchmark (код стенда и данные)", f"[`{b['commit']}`]({repo_url}/tree/{b['commit']})"),
        ("Дата коммита benchmark", b["commit_date"]),
        ("Хеш дерева results/ (идентификатор датасета)", f"`{b['results_tree']}`"),
        ("Серий / файлов результатов", f"{b['series']} / {b['result_files']}"),
        ("Хеш ноутбука анализа (sha256)", f"`{b['notebook_sha256'][:16]}…`"),
        ("Коммит сайта", f"`{s['commit']}`"),
        ("Сборка", f"{s['built_at']}" + (f" · [запуск CI]({s['ci_run']})" if s["ci_run"] else " · локально")),
        ("Исполнение ноутбука", f"{meta['analysis']['seconds']:.1f} с".replace(".", ",") + f", Python {meta['analysis']['python']}"),
        ("Воспроизводимость таблиц", f"{meta['analysis']['tables_reproduced']} из {meta['analysis']['tables_total']} "
                                     "побайтно совпали с закоммиченными"),
    ]
    pkgs = ", ".join(f"{k} {v}" for k, v in meta["analysis"]["packages"].items())
    text = ["# Происхождение данных\n",
            "Каждый опубликованный рисунок и таблица получены из конкретной версии кода и данных. "
            "По этим идентификаторам результат можно воспроизвести: "
            "`git checkout <коммит>` в benchmark и `make content` в репозитории сайта.\n",
            "| Параметр | Значение |", "|---|---|", *[f"| {k} | {v} |" for k, v in rows],
            f"\nПакеты анализа: {pkgs}.\n",
            "Машиночитаемая версия с хешами каждого артефакта — [provenance.json](provenance.json).\n"]
    (OUT / "provenance.md").write_text("\n".join(text))


def main() -> None:
    if not (BENCH / "analysis" / NOTEBOOK).exists():
        sys.exit("нет benchmark/analysis — выполните git submodule update --init")
    captions = yaml.safe_load(CAPTIONS.read_text())
    commit = git("rev-parse", "HEAD")
    epoch = git("log", "-1", "--format=%ct")

    analysis = prepare_workdir()
    print(f"исполнение {NOTEBOOK} на benchmark@{commit[:7]}…", flush=True)
    nb, seconds = execute_notebook(analysis, epoch)
    print(f"  готово за {seconds:.1f} с", flush=True)

    figures = sorted(p.stem for p in (analysis / "figures").glob("*.svg"))
    tables = sorted(p.stem for p in (analysis / "tables").glob("*.csv"))
    check_captions(captions, figures, tables)
    committed = BENCH / "analysis" / "tables"
    repro = {n: (committed / f"{n}.csv").exists() and sha256(committed / f"{n}.csv") == sha256(analysis / "tables" / f"{n}.csv")
             for n in tables}
    for n, ok in repro.items():
        if not ok and os.environ.get("GITHUB_ACTIONS"):
            print(f"::warning title=Таблица не воспроизвелась::{n}.csv отличается от закоммиченной в benchmark")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    write_report(nb)
    write_figures(captions, figures, analysis)
    write_tables(captions, tables, analysis, repro)

    server, repo, run = (os.environ.get(k) for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID"))
    try:
        site_commit = git("rev-parse", "HEAD", cwd=ROOT)
    except subprocess.CalledProcessError:
        site_commit = "нет коммитов"
    meta = {
        "benchmark": {
            "commit": commit, "commit_date": git("log", "-1", "--format=%cI"),
            "remote": git("config", "--get", "remote.origin.url"),
            "results_tree": git("rev-parse", "HEAD:results"),
            "series": len(list((BENCH / "results").glob("*/*/*/*/manifest.json"))),
            "result_files": len(git("ls-files", "results").splitlines()),
            "notebook_sha256": sha256(BENCH / "analysis" / NOTEBOOK),
        },
        "site": {"commit": os.environ.get("GITHUB_SHA", site_commit),
                 "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
                 "ci_run": f"{server}/{repo}/actions/runs/{run}" if run else None},
        "analysis": {"seconds": seconds, "python": platform.python_version(),
                     "packages": {p: metadata.version(p) for p in PACKAGES},
                     "tables_total": len(tables), "tables_reproduced": sum(repro.values())},
        "artifacts": {f"figures/{n}.svg": sha256(OUT / "figures" / f"{n}.svg") for n in figures}
                     | {f"tables/{n}.csv": sha256(OUT / "tables" / f"{n}.csv") for n in tables},
    }
    write_provenance(meta)
    print(f"страницы: {OUT.relative_to(ROOT)} · рисунков {len(figures)}, таблиц {len(tables)} "
          f"(воспроизведено {sum(repro.values())}/{len(tables)})")


if __name__ == "__main__":
    main()
