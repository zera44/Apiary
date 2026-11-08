# Еталон для test/fz2_test.dart: вхідні фрагменти (як їх бачить fz2.py після pandas) і очікувана розмітка.
# python3 gen_fixture.py raw16.csv rawDr.csv out.json (запускати з теки, де лежить fz2.py)
import pandas as pd, json, math, sys, fz2
def clean(v):
    if isinstance(v, float) and math.isnan(v): return None
    if hasattr(v, 'item'): v = v.item()
    return v
out = {}
for fn in sys.argv[1:-1]:
    d = pd.read_csv(fn)
    for r in d.receipt.unique():
        frags = d[d.receipt == r].to_dict('records')
        lab = fz2.label(frags)
        key = fn.split('/')[-1].replace('.csv','') + '/' + r
        inp = []
        for f in frags:
            g = {k: clean(v) for k, v in f.items()}
            g['text'] = str(f['text'])
            inp.append(g)
        exp = []
        for f, c, mu in lab:
            exp.append(dict(box=clean(f.get('box_id')), text=str(f.get('text')), xl=clean(f.get('x_left')), xr=clean(f.get('x_right')), cls=c,
                            virtual=bool(f.get('virtual')), value=f.get('value')))
        out[key] = dict(frags=inp, expected=exp)
json.dump(out, open(sys.argv[-1], 'w'), ensure_ascii=False)
print(len(out), 'receipts')
