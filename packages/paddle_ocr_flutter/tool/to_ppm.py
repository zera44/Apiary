"""Фото -> PPM (P6, RGB) тим самим декодером, що й курсова (cv2.imread), для tool/OcrV2Main.java.
python3 tool/to_ppm.py вихідна_тека фото.jpg..."""
import os, sys
import cv2

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for p in sys.argv[2:]:
    img = cv2.imread(p)
    if img is None:
        print('не прочитано', p); continue
    name = os.path.splitext(os.path.basename(p))[0]
    h, w = img.shape[:2]
    with open(os.path.join(out, name + '.ppm'), 'wb') as f:
        f.write(b'P6\n%d %d\n255\n' % (w, h))
        f.write(cv2.cvtColor(img, cv2.COLOR_BGR2RGB).tobytes())
