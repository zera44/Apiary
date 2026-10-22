"""CER рядків (та сама нормалізація, що в evalcer.py для tesseract): python3 eval_rec.py model.onnx list.txt [-v]"""
import sys, re, cv2
from ppocr_rec import Rec
LAT = str.maketrans('ABCEHKMOPTXaceopxyiI`', 'АВСЕНКМОРТХасеорхуіІ\'')
def norm(s): return re.sub(r'\s+', '', s.replace('N', 'Н').translate(LAT))
def lev(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p = d[:]; d[0] = i
        for j, y in enumerate(b, 1): d[j] = min(p[j] + 1, d[j - 1] + 1, p[j - 1] + (x != y))
    return d[-1]
def evaluate(rec, files, verbose=False):
    err = tot = ex = 0; rows = []
    for f in files:
        gt = open(f[:-4] + '.gt.txt', encoding='utf8').read().strip()
        hyp, _ = rec(cv2.imread(f))
        e = lev(norm(hyp), norm(gt)); err += e; tot += len(norm(gt)); ex += e == 0; rows.append((e, gt, hyp))
    return 100 * err / tot, ex, len(files), rows
if __name__ == '__main__':
    rec = Rec(sys.argv[1]); files = open(sys.argv[2]).read().split()
    cer, ex, n, rows = evaluate(rec, files)
    print(f'{sys.argv[1]}: CER {cer:.1f}%  рядків без помилок {ex}/{n}')
    if '-v' in sys.argv:
        for e, g, h in rows: print(e, '|', g, '|', h)
