"""PP-OCRv5 rec: ONNX -> PyTorch (onnx2torch) для донавчання -> ваги назад в ONNX (форма й динамічна ширина лишаються)."""
import warnings; warnings.filterwarnings('ignore')
import numpy as np, onnx, torch
from onnx import numpy_helper as nh
from onnx2torch import convert

def load_torch(onnx_path):
    m = convert(onnx_path)
    om = onnx.load(onnx_path)
    inits = {i.name: i for i in om.graph.initializer}
    used_by_node = {}
    mapping = {}      # ключ state_dict -> ім'я ініціалізатора ONNX
    for n in om.graph.node:
        kind, idx = n.name.rsplit('_', 1)
        if kind == 'Conv':
            mapping[f'{n.name}.weight'] = n.input[1]
            if len(n.input) > 2 and n.input[2]: mapping[f'{n.name}.bias'] = n.input[2]
        elif kind == 'BatchNormalization':
            for k, i in zip(('weight', 'bias', 'running_mean', 'running_var'), n.input[1:5]): mapping[f'{n.name}.{k}'] = i
        elif kind == 'ConvTranspose':
            mapping[f'{n.name}.weight'] = n.input[1]
            if len(n.input) > 2 and n.input[2]: mapping[f'{n.name}.bias'] = n.input[2]
    consumed = set(mapping.values())
    rest = [i.name for i in om.graph.initializer if i.name not in consumed]
    sd = m.state_dict()
    ik = sorted([k for k in sd if k.startswith('initializers.onnx_initializer_')], key=lambda k: int(k.rsplit('_', 1)[1]))
    # initializers, що бере onnx2torch: лише float та int, що не параметри вузлів; порядок як у графі
    cand = [r for r in rest]
    j = 0
    for k in ik:
        a = sd[k].numpy()
        while j < len(cand):
            b = nh.to_array(inits[cand[j]])
            j += 1
            if b.shape == a.shape and np.array_equal(b.astype(a.dtype), a):
                mapping[k] = cand[j - 1]; break
        else:
            raise RuntimeError('не знайшов ініціалізатор для ' + k)
    return m, mapping

def write_back(m, mapping, onnx_in, onnx_out):
    om = onnx.load(onnx_in); sd = m.state_dict()
    inits = {i.name: i for i in om.graph.initializer}
    for k, name in mapping.items():
        old = nh.to_array(inits[name])
        new = sd[k].detach().cpu().numpy().astype(old.dtype).reshape(old.shape)
        inits[name].CopyFrom(nh.from_array(new, name))
    onnx.save(om, onnx_out)

if __name__ == '__main__':
    import sys
    m, mp = load_torch(sys.argv[1]); print('mapped', len(mp), 'of', len(m.state_dict()))
    write_back(m, mp, sys.argv[1], sys.argv[2])
