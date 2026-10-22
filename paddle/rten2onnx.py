"""Перетворення .rten (RTen/flatbuffers) назад в ONNX. python3 rten2onnx.py in.rten out.onnx
Покриває оператори, що є в PP-OCRv5 rec/det (див. rten_load.py)."""
import sys, os
import numpy as np, onnx
from onnx import helper as h, TensorProto as TP, numpy_helper as nh
from rten_load import load, sg

OPN = {v: k for k, v in vars(sg.OperatorType).items() if not k.startswith('_')}

def attrs_of(op, a):
    t = OPN[op]
    L = lambda x: [int(v) for v in x]
    if t == 'Conv':
        return dict(strides=L(a.strides), dilations=L(a.dilations), group=int(a.groups), pads=L(a.pads))
    if t == 'ConvTranspose':
        return dict(strides=L(a.strides), pads=L(a.pads))
    if t == 'BatchNormalization': return dict(epsilon=float(a.epsilon))
    if t == 'HardSigmoid': return dict(alpha=float(a.alpha), beta=float(a.beta))
    if t == 'AveragePool':
        return dict(kernel_shape=L(a.kernelSize), strides=L(a.strides), pads=L(a.pads),
                    ceil_mode=int(a.ceilMode), count_include_pad=int(a.countIncludePad))
    if t == 'MaxPool':
        return dict(kernel_shape=L(a.kernelSize), strides=L(a.strides), pads=L(a.pads), ceil_mode=int(a.ceilMode))
    if t == 'Concat': return dict(axis=int(a.axis))
    if t == 'Reshape': return dict(allowzero=int(a.allowZero))
    if t == 'Transpose': return dict(perm=L(a.perm)) if a.perm is not None and len(a.perm) else {}
    if t == 'ReduceMean': return dict(axes=L(a.axes), keepdims=int(a.keepDims)) if a.axes is not None else dict(keepdims=int(a.keepDims))
    if t == 'Softmax': return dict(axis=int(a.axis))
    if t == 'Resize':
        mode = {0: 'nearest', 1: 'linear'}[a.mode]
        ct = {0: 'half_pixel', 1: 'asymmetric', 2: 'align_corners', 3: 'pytorch_half_pixel'}[a.coordMode]
        nm = {0: 'floor', 1: 'ceil', 2: 'round_prefer_floor', 3: 'round_prefer_ceil'}[a.nearestMode]
        return dict(mode=mode, coordinate_transformation_mode=ct, nearest_mode=nm)
    if t == 'Shape':
        d = {}
        if a.start is not None: d['start'] = int(a.start)
        if a.end is not None: d['end'] = int(a.end)
        return d
    if t == 'Gemm': return dict(alpha=float(a.alpha), beta=float(a.beta), transA=int(a.transposeA), transB=int(a.transposeB))
    if t == 'LayerNormalization': return dict(axis=int(a.axis), epsilon=float(a.epsilon))
    if t == 'Flatten': return dict(axis=int(a.axis))
    if t == 'Gather': return dict(axis=int(a.axis))
    if t == 'Cast': return dict(to={0: TP.INT32, 1: TP.FLOAT, 2: TP.INT8, 3: TP.UINT8}.get(a.to, TP.FLOAT))
    return {}

def convert(path, out, input_shape=None, opset=17):
    m, b, to, ver = load(path)
    g = m.graph; nodes = g.nodes
    name = lambda i: f'v{i}'
    inits = []; ops = []; used = set()
    for i, n in enumerate(nodes):
        d = n.data; t = type(d).__name__
        if t == 'ConstantNodeT':
            shape = [int(x) for x in d.shape]
            if d.data is not None:
                arr = np.asarray(d.data.data)
            else:
                dt = {0: np.int32, 1: np.float32, 2: np.int8, 3: np.uint8}[d.dtype]
                cnt = int(np.prod(shape)) if shape else 1
                off = to + int(d.dataOffset)
                arr = np.frombuffer(b, dtype=dt, count=cnt, offset=off)
            arr = arr.reshape(shape).copy()
            if arr.dtype == np.int32: arr = arr.astype(np.int64)   # rten зберігає int64 як int32
            inits.append(nh.from_array(arr, name(i)))
        elif t == 'OperatorNodeT':
            ins = [name(j) if j >= 0 else '' for j in d.inputs]
            outs = [name(j) for j in d.outputs]
            kind = OPN[d.type]
            at = attrs_of(d.type, d.attrs) if d.attrs is not None else {}
            ops.append(h.make_node(kind, ins, outs, name=f'{kind}_{i}', **at))
    gi = [name(i) for i in g.inputs]; go = [name(i) for i in g.outputs]
    shp = input_shape or ['N', 3, 'H', 'W']
    vi = [h.make_tensor_value_info(gi[0], TP.FLOAT, shp)]
    vo = [h.make_tensor_value_info(o, TP.FLOAT, None) for o in go]
    graph = h.make_graph(ops, 'rten', vi, vo, inits)
    model = h.make_model(graph, opset_imports=[h.make_opsetid('', opset)])
    model.ir_version = 8
    onnx.save(model, out)
    return model

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])
    print('ok', sys.argv[2], os.path.getsize(sys.argv[2]))
