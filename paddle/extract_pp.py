"""Рядки для навчання PaddleOCR rec: фото -> (вирівняний чек) -> det (PP-OCRv6 small, ONNX) -> об'єднання боксів в рядки ->
rec eslav -> нечітке зіставлення з receipts/NNN/lines.txt (як tesseract-варіант, але rec набагато краще читає) -> кропи.
python3 extract_pp.py <out_dir> <rec.onnx> <ids через кому|all> [skip_ids через кому]"""
import cv2, numpy as np, os, sys, re, glob, difflib, logging
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from warp import receipt
from ppocr_rec import Rec
logging.disable(logging.CRITICAL)
from rapidocr import RapidOCR
R = '/home/claude/ocr-training/receipts'
out, recp, ids = sys.argv[1], sys.argv[2], sys.argv[3]
skip = set(sys.argv[4].split(',')) if len(sys.argv) > 4 else set()
os.makedirs(out, exist_ok=True)
ids = sorted(os.listdir(R)) if ids == 'all' else ids.split(',')
ids = [i for i in ids if i not in skip]
eng = RapidOCR(); rec = Rec(recp)

def norm(s): return re.sub(r'[^0-9A-ZА-ЯІЇЄҐ]', '', s.upper().replace('X', 'Х'))
LATC = str.maketrans('ABCEHKMOPTXaceopxyiI', 'АВСЕНКМОРТХасеорхуіІ')
def nrm2(s): return norm(s.translate(LATC))     # латинські двійники -> кирилиця з обох боків

def det_lines(img):
    r = eng(cv2.cvtColor(img, cv2.COLOR_GRAY2BGR) if img.ndim == 2 else img, use_det=True, use_cls=False, use_rec=False)
    bs = [] if r.boxes is None else [np.asarray(b) for b in r.boxes]
    rects = []
    for b in bs:
        x0, y0 = b[:, 0].min(), b[:, 1].min(); x1, y1 = b[:, 0].max(), b[:, 1].max()
        if x1 - x0 > 8 and y1 - y0 > 8: rects.append([x0, y0, x1, y1])
    # об'єднати рамки на одному рівні (назва + ціна праворуч) в один рядок
    rects.sort(key=lambda r: (r[1] + r[3]) / 2)
    merged = True
    while merged:
        merged = False
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                a, b = rects[i], rects[j]
                ha, hb = a[3] - a[1], b[3] - b[1]
                ov = min(a[3], b[3]) - max(a[1], b[1])
                gap = max(a[0], b[0]) - min(a[2], b[2])
                if ov >= 0.6 * min(ha, hb) and gap < 5 * max(ha, hb) and abs(ha - hb) < 0.8 * max(ha, hb):
                    rects[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    del rects[j]; merged = True; break
            if merged: break
    return sorted(rects, key=lambda r: r[1])

def crop_gray(g, r, p=4):
    h, w = g.shape[:2]
    x0, y0, x1, y1 = int(max(0, r[0] - p)), int(max(0, r[1] - p)), int(min(w, r[2] + p)), int(min(h, r[3] + p))
    return g[y0:y1, x0:x1]

def match(rows, gt):
    cand = []
    for li, (r, hyp) in enumerate(rows):
        nh = nrm2(hyp)
        if len(nh) < 3: continue
        for gi, g in enumerate(gt):
            ng = nrm2(g)
            if not ng: continue
            sm = difflib.SequenceMatcher(None, nh, ng, autojunk=False); sc = sm.ratio()
            bl = [b for b in sm.get_matching_blocks() if b.size]
            if not bl or bl[0].b > 2 or len(ng) - (bl[-1].b + bl[-1].size) > 2: continue
            if sc >= 0.6 and 0.6 <= len(nh) / len(ng) <= 1.6: cand.append((sc, li, gi))
    cand.sort(reverse=True); ul, ug, m = set(), set(), []
    for sc, li, gi in cand:
        if li in ul or gi in ug: continue
        ul.add(li); ug.add(gi); m.append((rows[li][0][1], gi, li, sc))
    m.sort(); n = len(m)
    if not n: return []
    best = [1] * n; prev = [-1] * n
    for i in range(n):
        for j in range(i):
            if m[j][1] < m[i][1] and best[j] + 1 > best[i]: best[i], prev[i] = best[j] + 1, j
    i = max(range(n), key=lambda k: best[k]); keep = []
    while i >= 0: keep.append(m[i]); i = prev[i]
    return sorted(keep)

def rot(img, a): return {0: img, 90: cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE), 180: cv2.rotate(img, cv2.ROTATE_180), 270: cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)}[a]

def job(f):
    rid = f.split('/')[-2]; name = rid + '_' + os.path.basename(f)[:-4]
    gt = [l.strip() for l in open(f'{R}/{rid}/lines.txt', encoding='utf8') if l.strip()]
    c = cv2.imread(f)
    variants = [('o', cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)), ('w', receipt(c))]
    best = None
    for vn, g in variants:
        if max(g.shape) < 1800:
            s = 1800 / max(g.shape); g = cv2.resize(g, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
        for a in (0, 90, 270, 180):
            im = rot(g, a); rects = det_lines(im)
            rows = []
            for r in rects:
                cr = crop_gray(im, r)
                if cr.size == 0: continue
                rows.append((r, rec(cr)[0]))
            m = match(rows, gt); score = sum(x[3] for x in m)
            if best is None or score > best[0]: best = (score, vn, a, im, rows, m)
            if len(m) >= max(2, 0.6 * len(gt)): break
        if best and len(best[5]) >= max(2, 0.6 * len(gt)): break
    score, vn, a, im, rows, m = best
    res = []
    for y, gi, li, sc in m:
        r, hyp = rows[li]
        n = f'{out}/{name}_{gi:02d}'
        cv2.imwrite(n + '.png', crop_gray(im, r))
        open(n + '.gt.txt', 'w', encoding='utf8').write(gt[gi])
        res.append(f'{name}\t{vn}{a}\t{sc:.2f}\t{hyp}\t=>\t{gt[gi]}')
    return name, vn, a, len(gt), res

files = []
for rid in ids:
    p = f'{R}/{rid}/lines.txt'
    if not os.path.exists(p) or not any(l.strip() for l in open(p, encoding='utf8')): continue
    files += sorted(glob.glob(f'{R}/{rid}/photo_*.jpg') + glob.glob(f'{R}/{rid}/screen_*.jpg'))
log = open(f'{out}/match.log', 'a', encoding='utf8')
for f in files:
    try:
        name, vn, a, ng, res = job(f)
    except Exception as e:
        print('ERR', f, e, flush=True); continue
    print(name, vn, a, f'{len(res)}/{ng}', flush=True)
    log.write('\n'.join(res) + '\n'); log.flush()
