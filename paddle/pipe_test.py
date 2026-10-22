import cv2, numpy as np, sys, time
from rapidocr import RapidOCR
from ppocr_rec import Rec
S='/tmp/claude-0/-home-claude/ba1cc883-a7ef-5ff4-87a2-21e2a549f7f8/scratchpad/models'
eng = RapidOCR()
rec = Rec(S+'/rec_eslav.onnx')
def crop(img, box):
    box = np.array(box, np.float32)
    w = int(max(np.linalg.norm(box[0]-box[1]), np.linalg.norm(box[2]-box[3])))
    h = int(max(np.linalg.norm(box[0]-box[3]), np.linalg.norm(box[1]-box[2])))
    M = cv2.getPerspectiveTransform(box, np.float32([[0,0],[w,0],[w,h],[0,h]]))
    return cv2.warpPerspective(img, M, (w,h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
for f in sys.argv[1:]:
    img = cv2.imread(f); t=time.time()
    r = eng(img, use_det=True, use_cls=False, use_rec=False)
    boxes = r.boxes if r.boxes is not None else []
    print(f, 'boxes', len(boxes), f'det {time.time()-t:.1f}s')
    for b in sorted(boxes, key=lambda b: b[:,1].mean()):
        c = crop(img, b)
        if c.shape[0] > c.shape[1]: c = cv2.rotate(c, cv2.ROTATE_90_COUNTERCLOCKWISE)
        print('  ', rec(c)[0])
