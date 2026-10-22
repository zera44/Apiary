"""Донавчання PP-OCRv5 eslav rec (CTC) на кропах рядків чеків.
python3 train_rec.py --base rec.onnx --train train.txt --eval eval.txt --out dir --epochs 20 --lr 3e-4"""
import argparse, os, random, re, time, math
import numpy as np, cv2, torch
from pt_rec import load_torch, write_back
from ppocr_rec import load_dict, prep, decode
from eval_rec import norm, lev
ap = argparse.ArgumentParser()
ap.add_argument('--base'); ap.add_argument('--train'); ap.add_argument('--eval', action='append', default=[])
ap.add_argument('--out'); ap.add_argument('--epochs', type=int, default=20); ap.add_argument('--lr', type=float, default=3e-4)
ap.add_argument('--bs', type=int, default=16); ap.add_argument('--aug', type=int, default=3); ap.add_argument('--threads', type=int, default=2)
ap.add_argument('--seed', type=int, default=1)
a = ap.parse_args()
torch.set_num_threads(a.threads); random.seed(a.seed); np.random.seed(a.seed); torch.manual_seed(a.seed)
os.makedirs(a.out, exist_ok=True)
chars = load_dict(); cid = {c: i for i, c in enumerate(chars)}
LAT = {'`': "'"}
def enc(t):
    t = ''.join(LAT.get(c, c) for c in t)
    if any(c not in cid for c in t): return None
    return [cid[c] for c in t]

def aug(im):
    g = im.copy()
    s = random.uniform(0.7, 1.4); g = cv2.resize(g, None, fx=s, fy=s * random.uniform(0.9, 1.1), interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC)
    py, px = random.randint(0, 8), random.randint(0, 12)
    g = cv2.copyMakeBorder(g, py, py, px, px, cv2.BORDER_REPLICATE)
    h, w = g.shape; ang = random.uniform(-1.5, 1.5); sh = random.uniform(-0.08, 0.08)
    M = np.float32([[1, sh, 0], [np.tan(ang * 0.01745), 1, 0]])
    g = cv2.warpAffine(g, M, (w, h), borderMode=cv2.BORDER_REPLICATE)
    if random.random() < 0.5: g = cv2.GaussianBlur(g, (0, 0), random.uniform(0.5, 1.5))
    k = random.random()
    if k < 0.2: g = cv2.erode(g, np.ones((2, 2), np.uint8))
    elif k < 0.4: g = cv2.dilate(g, np.ones((2, 2), np.uint8))
    g = g.astype(np.float32); g = g * random.uniform(0.6, 1.0) + random.uniform(0, 60)
    g += np.random.normal(0, random.uniform(0, 12), g.shape)
    if random.random() < 0.3:   # перекіс освітлення
        grad = np.linspace(random.uniform(-30, 30), random.uniform(-30, 30), g.shape[1])[None]; g += grad
    return np.clip(g, 0, 255).astype(np.uint8)

def load_list(p, aug_ok):
    items = []; dropped = 0
    for f in open(p).read().split():
        gt = open(f[:-4] + '.gt.txt', encoding='utf8').read().strip()
        e = enc(gt)
        if e is None or not e: dropped += 1; continue
        im = cv2.imread(f, 0)
        if im is None or im.shape[0] < 8: continue
        items.append((im, gt, e))
    return items, dropped

train, dr = load_list(a.train, True); print('train', len(train), 'dropped(out-of-dict)', dr, flush=True)
evals = [(p, load_list(p, False)[0]) for p in a.eval]
m, mp = load_torch(a.base)
bn = [x for x in m.modules() if isinstance(x, torch.nn.BatchNorm2d)]
params = [p for p in m.parameters() if p.requires_grad]
opt = torch.optim.AdamW(params, lr=a.lr, weight_decay=1e-4)
total_steps = a.epochs * math.ceil(len(train) * a.aug / a.bs)
sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=a.lr, total_steps=total_steps, pct_start=0.1)
ctc = torch.nn.CTCLoss(blank=0, zero_infinity=True)

def batchify(ims):
    xs = [prep(i) for i in ims]; W = max(x.shape[2] for x in xs)
    t = np.ones((len(xs), 3, 48, W), np.float32)
    for i, x in enumerate(xs): t[i, :, :, :x.shape[2]] = x
    return torch.from_numpy(t), [x.shape[2] for x in xs]

def cer_eval(items):
    m.eval(); err = tot = 0
    with torch.no_grad():
        for im, gt, _ in items:
            y = m(torch.from_numpy(prep(im)[None]))[0].numpy()
            hyp, _ = decode(y, chars); err += lev(norm(hyp), norm(gt)); tot += len(norm(gt))
    return 100 * err / max(tot, 1)

def report(tag):
    r = [f'{os.path.basename(p)} {cer_eval(it):.1f}%' for p, it in evals]
    print(tag, ' | '.join(r), flush=True); return [cer_eval(it) for _, it in evals]
base = report('base'); best = base[0] if base else 1e9
step = 0; t0 = time.time()
for ep in range(a.epochs):
    m.train(); [b.eval() for b in bn]          # BN зі збереженою статистикою
    order = []
    for _ in range(a.aug): order += [(aug(im), e) for im, _, e in train]
    # групування за шириною: сортування в блоках
    random.shuffle(order); blocks = [sorted(order[i:i + a.bs * 8], key=lambda z: z[0].shape[1] / z[0].shape[0]) for i in range(0, len(order), a.bs * 8)]
    batches = [b[i:i + a.bs] for b in blocks for i in range(0, len(b), a.bs)]; random.shuffle(batches)
    tl = 0
    for b in batches:
        x, ws = batchify([z[0] for z in b])
        y = m(x).clamp_min(1e-8).log().transpose(0, 1)       # [T,N,C]
        T = y.shape[0]
        il = torch.tensor([min(T, math.ceil(w / 8)) for w in ws]); tg = torch.tensor([c for z in b for c in z[1]]); tl_ = torch.tensor([len(z[1]) for z in b])
        loss = ctc(y, tg, il, tl_)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(params, 5.0); opt.step()
        if step < total_steps - 1: sched.step()
        step += 1; tl += float(loss)
    r = report(f'ep{ep + 1} loss {tl / len(batches):.3f} {time.time() - t0:.0f}s')
    if evals and r[0] < best:
        best = r[0]; write_back(m, mp, a.base, os.path.join(a.out, 'best.onnx')); print('  saved best', best, flush=True)
write_back(m, mp, a.base, os.path.join(a.out, 'last.onnx'))
