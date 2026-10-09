#!/usr/bin/env python3
"""Генерує іконку застосунку з design/app_icon/app_icon.pdf.

    python3 tool/make_app_icon.py

Потрібні pdftocairo (poppler-utils) і Pillow. Результат — у tool/app_icon/
(його копіює в платформні файли tool/patch_platforms.dart):
  android/res/mipmap-*/ic_launcher.png             звичайна (Android < 8)
  android/res/mipmap-*/ic_launcher_foreground.png  передній план адаптивної
  android/res/mipmap-anydpi-v26/ic_launcher.xml    адаптивна (Android 8+)
  android/res/values/ic_launcher_background.xml    колір тла
  android/res/drawable-*/ic_notification.png       біла іконка сповіщень
  android/res/raw/keep.xml                         щоб її не вирізав shrinker
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'design', 'app_icon', 'app_icon.pdf')
OUT = os.path.join(ROOT, 'tool', 'app_icon')
BG = (251, 233, 196, 255)  # теплий кремовий
BG_HEX = '#FBE9C4'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def load_art():
    with tempfile.TemporaryDirectory() as d:
        base = os.path.join(d, 'art')
        subprocess.run(['pdftocairo', '-png', '-transp', '-r', '800', '-singlefile', SRC, base],
                       check=True)
        im = Image.open(base + '.png').convert('RGBA')
    bbox = im.getchannel('A').point(lambda v: 255 if v > 10 else 0).getbbox()
    return im.crop(bbox)


def compose(art, size, frac, bg=BG, rounded=0.0):
    c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if bg:
        d = ImageDraw.Draw(c)
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * rounded), fill=bg)
    h = round(size * frac)
    w = round(art.width * h / art.height)
    c.alpha_composite(art.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return c


def save(img, *parts):
    p = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)


def write(text, *parts):
    p = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


def main():
    art = load_art()
    big_legacy = compose(art, 1024, 0.84, rounded=0.2)
    # адаптивна: полотно 108dp, видно круг ~72dp — фігура 56 % висоти полотна (з запасом)
    big_fg = compose(art, 1024, 0.56, bg=None)
    # сповіщення: білий силует на прозорому (Android малює лише альфу)
    alpha = compose(art, 1024, 0.92, bg=None).getchannel('A')
    white = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    white.putalpha(alpha)
    for name, k in DENSITIES.items():
        save(big_legacy.resize((round(48 * k),) * 2, Image.LANCZOS),
             'android', 'res', f'mipmap-{name}', 'ic_launcher.png')
        save(big_fg.resize((round(108 * k),) * 2, Image.LANCZOS),
             'android', 'res', f'mipmap-{name}', 'ic_launcher_foreground.png')
        save(white.resize((round(24 * k),) * 2, Image.LANCZOS),
             'android', 'res', f'drawable-{name}', 'ic_notification.png')
    write('<?xml version="1.0" encoding="utf-8"?>\n'
          '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <background android:drawable="@color/ic_launcher_background"/>\n'
          '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
          '</adaptive-icon>\n', 'android', 'res', 'mipmap-anydpi-v26', 'ic_launcher.xml')
    write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
          f'    <color name="ic_launcher_background">{BG_HEX}</color>\n</resources>\n',
          'android', 'res', 'values', 'ic_launcher_background.xml')
    write('<?xml version="1.0" encoding="utf-8"?>\n'
          '<resources xmlns:tools="http://schemas.android.com/tools"\n'
          '    tools:keep="@drawable/ic_notification" />\n',
          'android', 'res', 'raw', 'keep.xml')
    big_legacy.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'preview.png'))
    print('готово:', OUT)


if __name__ == '__main__':
    main()
