#!/usr/bin/env python3
"""Забрати нові фото чеків зі сховища Supabase `receipt-training` у каталог
`<out>/<перші 8 символів device_id>/<файл>.jpg` (гілка ocr-training, каталог inbox/).

Вже забрані файли пропускає (за іменем: воно містить хеш знімка). Нічого не
видаляє зі сховища.

  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 tool/pull_receipt_photos.py <out_dir>
"""
import json, os, sys, urllib.request

BUCKET = 'receipt-training'


def call(base, key, path, data=None):
    req = urllib.request.Request(
        f'{base}/storage/v1/{path}',
        data=None if data is None else json.dumps(data).encode(),
        headers={'Authorization': f'Bearer {key}', 'apikey': key, 'Content-Type': 'application/json'},
        method='GET' if data is None else 'POST')
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def listing(base, key, prefix):
    out, offset = [], 0
    while True:
        page = json.loads(call(base, key, f'object/list/{BUCKET}',
                               {'prefix': prefix, 'limit': 1000, 'offset': offset}))
        out += page
        if len(page) < 1000:
            return out
        offset += 1000


def main(out):
    base = os.environ['SUPABASE_URL'].rstrip('/')
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    new = 0
    for d in listing(base, key, ''):
        if d.get('id') is not None:        # файл у корені - не наш формат
            continue
        dev = d['name']
        for f in listing(base, key, dev):
            if f.get('id') is None or not f['name'].endswith('.jpg'):
                continue
            dst = os.path.join(out, dev[:8], f['name'])
            if os.path.exists(dst):
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'wb') as fh:
                fh.write(call(base, key, f'object/{BUCKET}/{dev}/{f["name"]}'))
            new += 1
    print(f'нових фото: {new}')


if __name__ == '__main__':
    main(sys.argv[1])
