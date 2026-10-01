#!/usr/bin/env python3
"""«Що нового» з історії git — автоматично, без ручного списку.

Кожен коміт, що змінює щось помітне для пасічника, має в описі рядки:

    Нове: «Зберегти й далі» — після огляду одразу наступний вулик
    Нове(3): ...            — вага 1..5 (за замовчуванням 1): що більша,
                              то вище в переліку; на екрані одразу видно
                              лише 20% найважливіших, решта — у «Ще»
    Виправлено: ...         — виправлена помилка (завжди у «Ще»)

Коміти без таких рядків (тести, CI, рефакторинг) у «Що нового» не потрапляють.
Версія запису — перший реліз (тег vX.Y.Z), що вже містить цей коміт; ще не
випущене — поточна версія з pubspec.yaml (піде в наступний реліз).

  python3 tool/whats_new.py            → assets/whats_new.json (для застосунку)
  python3 tool/whats_new.py --md       → текст для опису релізу (поточна версія)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINE = re.compile(r'^\s*(Нове|Виправлено)(?:\((\d)\))?\s*:\s*(.+?)\s*$')
VERSION = re.compile(r'^version:\s*([0-9][^+\s]*)', re.M)


def git(*args: str) -> str:
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding='utf-8').stdout


def _vkey(v: str) -> tuple:
    return tuple(int(x) if x.isdigit() else 0 for x in v.split('.'))


def released_in(sha: str, current: str) -> str:
    tags = [t[1:] for t in git('tag', '--contains', sha, '--list', 'v*').split()]
    return min(tags, key=_vkey) if tags else current


def collect() -> list[dict]:
    log = git('log', '--reverse', '--format=%H%x1f%B%x1e', 'HEAD')
    entries: list[dict] = []
    current = VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8')).group(1)
    vcache: dict = {}
    for n, rec in enumerate(r for r in log.split('\x1e') if r.strip()):
        sha, _, body = rec.strip().partition('\x1f')
        for i, line in enumerate(body.splitlines()):
            m = LINE.match(line)
            if not m:
                continue
            kind, weight, text = m.groups()
            entries.append({
                'n': n + 1,
                'i': i,
                'v': vcache.setdefault(sha, released_in(sha, current)),
                't': 'feat' if kind == 'Нове' else 'fix',
                'w': max(1, min(5, int(weight or 1))),
                'text': text,
            })
    # той самий текст пізніше — лишаємо найновіший запис
    seen: dict = {}
    for e in entries:
        seen[(e['t'], e['text'])] = e
    return sorted(seen.values(), key=lambda e: (e['n'], e['i']))


def markdown(entries: list[dict]) -> str:
    current = VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8')).group(1)
    mine = [e for e in entries if e['v'] == current]
    feats = sorted((e for e in mine if e['t'] == 'feat'), key=lambda e: (-e['w'], -e['n'], e['i']))
    fixes = [e for e in mine if e['t'] == 'fix']
    out = [f'## Що нового · {current}', '']
    out += [f'- {e["text"]}' for e in feats] or ['- (без змін для пасічника)']
    if fixes:
        out += ['', '### Виправлено', ''] + [f'- {e["text"]}' for e in fixes]
    return '\n'.join(out) + '\n'


def main() -> None:
    entries = collect()
    if '--md' in sys.argv:
        sys.stdout.write(markdown(entries))
        return
    out = ROOT / 'assets' / 'whats_new.json'
    out.write_text(json.dumps({'entries': entries}, ensure_ascii=False, indent=1) + '\n',
                   encoding='utf-8')
    print(f'{out.relative_to(ROOT)}: {len(entries)} entries')


if __name__ == '__main__':
    main()
