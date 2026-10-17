import cv2, numpy as np

def order(p):
    s = p.sum(1); d = np.diff(p, axis=1).ravel()
    return np.float32([p[np.argmin(s)], p[np.argmin(d)], p[np.argmax(s)], p[np.argmax(d)]])

def best_gray(c):
    chans = [c[:, :, k] for k in range(3)] + [cv2.cvtColor(c, cv2.COLOR_BGR2GRAY)]
    return max(chans, key=lambda x: np.std(x))

def receipt(c):
    """Кольорове фото -> сіре, вирізаний і вирівняний чек (або все фото, якщо чек не знайдено)."""
    g = best_gray(c); H, W = g.shape
    sm = cv2.resize(g, None, fx=0.25, fy=0.25)
    sm = cv2.GaussianBlur(sm, (5, 5), 0)
    _, th = cv2.threshold(sm, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    th = cv2.morphologyEx(th, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    cs, _ = cv2.findContours(th, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out = g
    if cs:
        cnt = max(cs, key=cv2.contourArea)
        if cv2.contourArea(cnt) > 0.08 * sm.size:
            r = cv2.minAreaRect(cnt)
            box = order(cv2.boxPoints(r) * 4)
            w = int(max(np.linalg.norm(box[0] - box[1]), np.linalg.norm(box[2] - box[3])))
            h = int(max(np.linalg.norm(box[0] - box[3]), np.linalg.norm(box[1] - box[2])))
            M = cv2.getPerspectiveTransform(box, np.float32([[0, 0], [w, 0], [w, h], [0, h]]))
            out = cv2.warpPerspective(g, M, (w, h), borderValue=255)
    # дрібний нахил тексту: найгостріший горизонтальний профіль
    bw = cv2.adaptiveThreshold(out, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 31, 15)
    small = cv2.resize(bw, None, fx=0.5, fy=0.5)
    best = (0, -1)
    for a in np.arange(-6, 6.01, 0.5):
        M = cv2.getRotationMatrix2D((small.shape[1] / 2, small.shape[0] / 2), a, 1)
        r = cv2.warpAffine(small, M, (small.shape[1], small.shape[0]))
        v = np.var(r.sum(1))
        if v > best[1]: best = (a, v)
    if best[0]:
        M = cv2.getRotationMatrix2D((out.shape[1] / 2, out.shape[0] / 2), best[0], 1)
        out = cv2.warpAffine(out, M, (out.shape[1], out.shape[0]), borderValue=255)
    # текст ~ 30-40 px: ширина чека до 1100-1300
    if out.shape[1] < 1000:
        s = 1150 / out.shape[1]; out = cv2.resize(out, None, fx=s, fy=s, interpolation=cv2.INTER_CUBIC)
    return out
