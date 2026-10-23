"""Допоміжний запуск моделі для перевірки Java-логіки на ПК: python3 ort_runner.py model in.bin out.bin d0 d1 d2 d3
(вхід - float32 розмірів d0..d3, вихід: int32 ndim, int32 dims..., float32 дані)."""
import sys, numpy as np, onnxruntime as ort
model, fin, fout = sys.argv[1:4]; shp = [int(v) for v in sys.argv[4:8]]
x = np.fromfile(fin, dtype='<f4').reshape(shp)
s = ort.InferenceSession(model, providers=['CPUExecutionProvider'])
y = s.run(None, {s.get_inputs()[0].name: x})[0].astype('<f4')
with open(fout, 'wb') as f:
    np.array([y.ndim] + list(y.shape), dtype='<i4').tofile(f); y.tofile(f)
