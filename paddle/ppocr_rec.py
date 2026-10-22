"""PP-OCRv5 rec (eslav): підготовка кропа, ONNX-інференс, CTC-декодування.
Та сама логіка потім у Kotlin (android/.../PaddleRec.kt)."""
import numpy as np, cv2, os
HERE = os.path.dirname(os.path.abspath(__file__))
def load_dict(p=os.path.join(HERE, 'dict_eslav.txt')):
    ch = open(p, encoding='utf8').read().split('\n')
    if ch and ch[-1] == '': ch = ch[:-1]
    return ['<blank>'] + ch + [' ']          # 0 = blank, останній = пробіл
H = 48
def prep(img, min_w=48, max_w=3200):
    """img: gray або bgr uint8 -> float32 [3,48,W] у діапазоні [-1,1]"""
    if img.ndim == 2: img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    h, w = img.shape[:2]
    nw = int(min(max(round(H * w / h), min_w), max_w))
    r = cv2.resize(img, (nw, H), interpolation=cv2.INTER_LINEAR).astype(np.float32)
    r = (r / 255.0 - 0.5) / 0.5
    return r.transpose(2, 0, 1)
def decode(probs, chars):
    """probs [T,C] -> (текст, впевненість). Жадібно: argmax, склеїти повтори, прибрати blank."""
    idx = probs.argmax(1); conf = probs.max(1); out = []; cs = []; prev = -1
    for i, c in zip(idx, conf):
        if i != prev and i != 0: out.append(chars[i]); cs.append(c)
        prev = i
    return ''.join(out), float(np.mean(cs)) if cs else 0.0
class Rec:
    def __init__(self, onnx_path, dict_path=None):
        import onnxruntime as ort
        o = ort.SessionOptions(); o.intra_op_num_threads = 2
        self.s = ort.InferenceSession(onnx_path, o, providers=['CPUExecutionProvider'])
        self.inp = self.s.get_inputs()[0].name
        self.chars = load_dict(dict_path) if dict_path else load_dict()
    def __call__(self, img):
        x = prep(img)[None]
        y = self.s.run(None, {self.inp: x})[0][0]
        return decode(y, self.chars)
