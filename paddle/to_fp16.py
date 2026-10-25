"""Ваги ONNX у fp16 (Cast назад у fp32 при завантаженні): модель вдвічі менша, обчислення ті самі, fp32."""
import sys, onnx, numpy as np
from onnx import numpy_helper, helper, TensorProto
src, dst = sys.argv[1:3]
m = onnx.load(src); g = m.graph
casts = []; keep = []
for t in g.initializer:
    if t.data_type == TensorProto.FLOAT and int(np.prod(t.dims)) >= 256:
        a = numpy_helper.to_array(t)
        h = numpy_helper.from_array(a.astype(np.float16), t.name + '_f16')
        keep.append(h)
        casts.append(helper.make_node('Cast', [t.name + '_f16'], [t.name], to=TensorProto.FLOAT, name='cast_' + t.name))
    else:
        keep.append(t)
del g.initializer[:]; g.initializer.extend(keep)
nodes = list(g.node); del g.node[:]; g.node.extend(casts + nodes)
onnx.save(m, dst)
