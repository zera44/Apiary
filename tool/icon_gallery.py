#!/usr/bin/env python3
"""Галерея іконок для перегляду в браузері: python3 tool/icon_gallery.py

Читає assets/icons/icons.json, показує кожну іконку в трьох розмірах на
світлому й темному тлі (і кольором застосунку) та підсвічує проблеми:
файл є в реєстрі, але не знайдений; файл є на диску, але його немає в
реєстрі. Результат: build/icon_gallery.html (папка build/ у git не потрапляє).
Щоб зберегти знімок у README, відкрийте файл і зробіть скріншот.
"""
import html
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icons"


def load_svg(path: pathlib.Path, color: str, size: int) -> str:
    svg = path.read_text(encoding="utf-8")
    svg = svg.replace("currentColor", color)
    return re.sub(r"<svg\b", f'<svg width="{size}" height="{size}"', svg, count=1)


def main() -> int:
    manifest = json.loads((ICONS / "icons.json").read_text(encoding="utf-8"))
    cats = manifest.get("categories", {})
    entries = manifest["icons"]
    registered = {e["file"] for e in entries}
    on_disk = {
        p.relative_to(ICONS).as_posix()
        for p in ICONS.rglob("*.svg")
        if not p.name.startswith("_")
    }
    problems = []
    for f in sorted(on_disk - registered):
        problems.append(f"є файл, але немає в icons.json: {f}")
    for e in entries:
        if not (ICONS / e["file"]).exists():
            problems.append(f"немає файлу для «{e['id']}»: {e['file']}")

    out = [
        "<!doctype html><meta charset='utf-8'><title>Іконки «Моя пасіка»</title>",
        "<style>body{font:14px system-ui,sans-serif;margin:24px;background:#f4efe6;color:#2a1a12}"
        "h2{margin:28px 0 8px}.g{display:flex;flex-wrap:wrap;gap:12px}"
        ".c{background:#fff;border-radius:12px;padding:10px;width:190px;box-shadow:0 1px 3px #0002}"
        ".r{display:flex;align-items:center;gap:8px;margin:6px 0}"
        ".b{border-radius:8px;padding:6px;display:inline-flex}"
        ".id{font-weight:600}.f{color:#8a7a6a;font-size:12px}.p{background:#fdd;padding:8px;border-radius:8px}"
        "</style><h1>Іконки «Моя пасіка»</h1>",
    ]
    if problems:
        out.append("<div class='p'><b>Проблеми:</b><br>" + "<br>".join(map(html.escape, problems)) + "</div>")
    for cat, title in cats.items():
        out.append(f"<h2>{html.escape(title)}</h2><div class='g'>")
        for e in [e for e in entries if e["category"] == cat]:
            p = ICONS / e["file"]
            if not p.exists():
                continue
            out.append(
                f"<div class='c'><div class='id'>{html.escape(e['id'])}</div>"
                f"<div>{html.escape(e['label'])}</div><div class='f'>{html.escape(e['file'])}</div>"
                "<div class='r'>"
                f"<span class='b' style='background:#f2b705'>{load_svg(p, '#2a1a12', 24)}</span>"
                f"<span class='b' style='background:#f2b705'>{load_svg(p, '#2a1a12', 48)}</span>"
                f"<span class='b' style='background:#2a1a12'>{load_svg(p, '#f5e9d3', 48)}</span></div>"
                f"<div class='b' style='background:#f2b705'>{load_svg(p, '#2a1a12', 96)}</div></div>"
            )
        out.append("</div>")
    dest = ROOT / "build" / "icon_gallery.html"
    dest.parent.mkdir(exist_ok=True)
    dest.write_text("\n".join(out), encoding="utf-8")
    print(f"Готово: {dest}")
    for p in problems:
        print("ПРОБЛЕМА:", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
