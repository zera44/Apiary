"""Рядки для навчання: фото чека -> поворот (OSD, перевірка збігом) -> рядки tesseract ->
нечітке зіставлення з receipts/NNN/lines.txt (глобально, з порядком по вертикалі) -> кропи.
python3 extract.py <out_dir> <ids через кому або all>"""
import cv2, numpy as np, glob, os, sys, re, csv, io, subprocess, difflib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from warp import receipt
WARP = os.environ.get('WARP') == '1'
from concurrent.futures import ThreadPoolExecutor
R = '/home/claude/ocr-training/receipts'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
ids = sorted(os.listdir(R)) if sys.argv[2] == 'all' else sys.argv[2].split(',')
TD = os.environ.get('TD', 'tdb')

def norm(s): return re.sub(r'[^0-9A-ZА-ЯІЇЄҐ]', '', s.upper().replace('X', 'Х'))

def ocr_lines(img):
    ok, buf = cv2.imencode('.png', img)
    r = subprocess.run(['tesseract', 'stdin', 'stdout', '-l', 'ukr', '--psm', '4', '--tessdata-dir', TD, 'tsv'],
                       input=buf.tobytes(), capture_output=True)
    rows = list(csv.DictReader(io.StringIO(r.stdout.decode('utf8', 'ignore')), delimiter='\t', quoting=csv.QUOTE_NONE))
    lines = {}; words = []
    for w in rows:
        if w.get('level') != '5' or not (w.get('text') or '').strip(): continue
        k = (w['block_num'], w['par_num'], w['line_num'])
        words.append((int(w['left']), int(w['top']), int(w['left']) + int(w['width']), int(w['top']) + int(w['height']), k))
        l, t, ww, h = int(w['left']), int(w['top']), int(w['width']), int(w['height'])
        d = lines.setdefault(k, [l, t, l + ww, t + h, []])
        d[0] = min(d[0], l); d[1] = min(d[1], t); d[2] = max(d[2], l + ww); d[3] = max(d[3], t + h); d[4].append(w['text'])
    out = []
    for k, (x0, y0, x1, y1, ws) in lines.items():
        # слова з інших блоків на тій самій висоті (ціна праворуч) - теж у рядок
        h = y1 - y0; ch = True
        while ch:
            ch = False
            for a, b, c, d, kk in words:
                if kk == k or (a >= x0 and c <= x1): continue
                ov = min(y1, d) - max(y0, b)
                if ov >= 0.6 * min(h, d - b) and (a - x1 < 4 * h and x0 - c < 4 * h):
                    nx0, nx1 = min(x0, a), max(x1, c)
                    if (nx0, nx1) != (x0, x1): x0, x1, ch = nx0, nx1, True
        out.append((x0, y0, x1, y1, ' '.join(ws)))
    return out

def match(lines, gt):
    cand = []
    for li, (x0, y0, x1, y1, hyp) in enumerate(lines):
        nh = norm(hyp)
        if len(nh) < 3 or (y1 - y0) < 12: continue
        for gi, g in enumerate(gt):
            ng = norm(g)
            if not ng: continue
            sm = difflib.SequenceMatcher(None, nh, ng, autojunk=False); sc = sm.ratio()
            bl = [b for b in sm.get_matching_blocks() if b.size]
            # початок і кінець еталону мають бути на кропі (не обрізаний край фото)
            if not bl or bl[0].b > 2 or len(ng) - (bl[-1].b + bl[-1].size) > 2: continue
            # довжини мають бути схожі (рядок не шматок іншого)
            if sc >= 0.55 and 0.6 <= len(nh) / len(ng) <= 1.6: cand.append((sc, li, gi))
    cand.sort(reverse=True); ul, ug, m = set(), set(), []
    for sc, li, gi in cand:
        if li in ul or gi in ug: continue
        ul.add(li); ug.add(gi); m.append((lines[li][1], gi, li, sc))
    # порядок: індекс еталону має зростати разом з y - найдовша зростаюча підпослідовність
    m.sort(); n = len(m); best = [1] * n; prev = [-1] * n
    for i in range(n):
        for j in range(i):
            if m[j][1] < m[i][1] and best[j] + 1 > best[i]: best[i], prev[i] = best[j] + 1, j
    if not n: return []
    i = max(range(n), key=lambda k: best[k]); keep = []
    while i >= 0: keep.append(m[i]); i = prev[i]
    keep.sort()
    # проміжки між впевненими рядками: якщо рядків на фото стільки ж, скільки в еталоні - парами по порядку
    hs = sorted(lines[x[2]][3] - lines[x[2]][1] for x in keep); mh = hs[len(hs) // 2] if hs else 40
    ok = [li for li, l in enumerate(lines) if len(norm(l[4])) >= 3 and 12 <= l[3] - l[1] <= 2.2 * mh]
    extra = []
    for (ya, ga, la, _), (yb, gb, lb, _) in zip(keep, keep[1:]):
        gg = list(range(ga + 1, gb))
        if not gg: continue
        ll = sorted((li for li in ok if ya < lines[li][1] < yb and li not in (la, lb)), key=lambda li: lines[li][1])
        if len(ll) != len(gg): continue
        pairs = []
        for li, gi in zip(ll, gg):
            sc = difflib.SequenceMatcher(None, norm(lines[li][4]), norm(gt[gi]), autojunk=False).ratio()
            if sc < 0.3: break
            pairs.append((lines[li][1], gi, li, sc))
        else:
            extra += pairs
    return sorted(keep + extra)

def rot(img, a):
    return {0: img, 90: cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE), 180: cv2.rotate(img, cv2.ROTATE_180),
            270: cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)}[a]

def job(f):
    rid = f.split('/')[-2]; name = rid + '_' + os.path.basename(f)[:-4]
    gt = [l.strip() for l in open(f'{R}/{rid}/lines.txt', encoding='utf8') if l.strip()]
    img = receipt(cv2.imread(f)) if WARP else cv2.imread(f, 0)
    if max(img.shape) < 1800:
        s = 1800 / max(img.shape); img = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
    best = None
    for a in (0, 90, 270, 180):
        im = rot(img, a); ls = ocr_lines(im); m = match(ls, gt)
        score = sum(x[3] for x in m)
        if best is None or score > best[0]: best = (score, a, im, m, ls)
        if len(m) >= max(2, 0.5 * len(gt)): break   # досить добре - інші повороти не пробуємо
    score, a, im, m, lines = best
    res = []
    for y, gi, li, sc in m:
        x0, y0, x1, y1, hyp = lines[li] if li < len(lines) else (0, 0, 0, 0, '')
        if not hyp: continue
        p = 6; crop = im[max(0, y0 - p):y1 + p, max(0, x0 - p):x1 + p]
        n = f'{out}/{name}_{gi:02d}'
        cv2.imwrite(n + '.png', crop)
        open(n + '.gt.txt', 'w', encoding='utf8').write(gt[gi])
        res.append(f'{name}\t{a}\t{sc:.2f}\t{hyp}\t=>\t{gt[gi]}')
    return name, a, len(gt), res

files = []
for rid in ids:
    if not os.path.exists(f'{R}/{rid}/lines.txt'): continue
    if not any(l.strip() for l in open(f'{R}/{rid}/lines.txt', encoding='utf8')): continue
    files += sorted(glob.glob(f'{R}/{rid}/*.jpg'))
log = open(f'{out}/match.log', 'w', encoding='utf8')
with ThreadPoolExecutor(2) as ex:
    for name, a, ng, res in ex.map(job, files):
        print(name, 'rot', a, f'{len(res)}/{ng}', flush=True)
        log.write('\n'.join(res) + '\n')
