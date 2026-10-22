"""Читання .rten (flatbuffers): список вузлів графа. python3 rten_load.py model.rten"""
import sys, struct, os
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rten_schema'))
from rten_convert import schema_generated as sg

def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'RTEN'
    ver = struct.unpack('<I', b[4:8])[0]
    mo, ml, to = struct.unpack('<QQQ', b[8:32])
    m = sg.ModelT.InitFromObj(sg.Model.GetRootAs(b[mo:mo + ml], 0))
    return m, b, to, ver

if __name__ == '__main__':
    m, b, to, ver = load(sys.argv[1])
    g = m.graph
    print('version', ver, 'nodes', len(g.nodes), 'inputs', g.inputs, 'outputs', g.outputs)
    opn = {v: k for k, v in vars(sg.OperatorType).items() if not k.startswith('_')}
    from collections import Counter
    c = Counter()
    for n in g.nodes:
        if n.data is not None and type(n.data).__name__ == 'OperatorNodeT': c[opn[n.data.type]] += 1
    print(c)
