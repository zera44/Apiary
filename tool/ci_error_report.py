"""Витягує з логу збірки суть помилки й виводить її як анотацію GitHub
Actions (::error::), щоб її було видно на сторінці запуску без
завантаження повного логу.

    python3 tool/ci_error_report.py build.log
"""
import re
import sys

MARKERS = re.compile(
    r"(error|what went wrong|exception|failed|unresolved|cannot|could not|"
    r"requires|incompatible|not found|undefined)",
    re.I,
)


def main(path):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError as e:
        print(f"::error::Не вдалось прочитати {path}: {e}")
        return
    picked = []
    for i, line in enumerate(lines):
        if MARKERS.search(line):
            picked.extend(range(max(0, i - 2), min(len(lines), i + 6)))
    idx = sorted(set(picked))[:220]
    chunk = [lines[i] for i in idx] or lines[-120:]
    # хвіст логу теж корисний
    tail = lines[-60:]
    text = "\n".join(chunk) + "\n----- кінець логу -----\n" + "\n".join(tail)
    text = text[-60000:]
    enc = text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::error title=build log::{enc}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build.log")
