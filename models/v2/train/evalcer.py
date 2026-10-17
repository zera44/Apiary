"""CER рядків: python3 evalcer.py <tessdata_dir> <файл зі списком png> [-v]"""
import sys, subprocess, re
from concurrent.futures import ThreadPoolExecutor
tdir, lst = sys.argv[1], sys.argv[2]
LAT = str.maketrans('ABCEHKMOPTXaceopxyiI`', 'АВСЕНКМОРТХасеорхуіІ\'')
def norm(s): return re.sub(r'\s+', '', s.replace('N', 'Н').translate(LAT))
def lev(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p = d[:]; d[0] = i
        for j, y in enumerate(b, 1): d[j] = min(p[j] + 1, d[j - 1] + 1, p[j - 1] + (x != y))
    return d[-1]
def one(f):
    gt = open(f[:-4] + '.gt.txt', encoding='utf8').read().strip()
    r = subprocess.run(['tesseract', f, '-', '-l', 'ukr', '--psm', '7', '--tessdata-dir', tdir], capture_output=True, text=True)
    hyp = ' '.join(r.stdout.split())
    return lev(norm(hyp), norm(gt)), len(norm(gt)), gt, hyp
files = open(lst).read().split()
with ThreadPoolExecutor(2) as ex: rows = list(ex.map(one, files))
err = sum(r[0] for r in rows); tot = sum(r[1] for r in rows)
exact = sum(1 for r in rows if r[0] == 0)
print(f'{tdir}: CER {100 * err / tot:.1f}%  рядків без помилок {exact}/{len(rows)}')
if '-v' in sys.argv:
    for e, n, g, h in rows: print(e, '|', g, '|', h)
