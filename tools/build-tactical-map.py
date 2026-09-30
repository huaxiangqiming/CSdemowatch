"""Strip Source2Viewer 20 GLB to gray structural geometry; no replay data touched.
Usage: python tools/build-tactical-map.py exported/world.glb app/maps/de_ancient/map.glb
Requires numpy. Retains authored triangles, strips textures/decorative meshes,
bakes glTF transforms, normalizes to (CS2 X, CS2 Z, -CS2 Y) Source units.
"""
import collections
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.tools' / 'pythonpkgs'))
import numpy as np


def build(source, target):
    blob = source.read_bytes()
    length = struct.unpack_from('<I', blob, 12)[0]
    doc = json.loads(blob[20:20 + length])
    binary = memoryview(blob)[28 + length:]

    def accessor(index):
        a = doc['accessors'][index]
        v = doc['bufferViews'][a['bufferView']]
        dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
        components = {'SCALAR': 1, 'VEC3': 3}[a['type']]
        size = np.dtype(dtype).itemsize
        return np.ndarray((a['count'], components), dtype=dtype, buffer=binary,
                          offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
                          strides=(v.get('byteStride', size * components), size))

    # Exporter's world space is (CS2 Y, CS2 Z, CS2 X) meters.
    axis = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], dtype=np.float64)
    exclude = re.compile(r'npcclip|playerclip|grenadeclip|blocklight|overlay|water|dust|candle|foliage|fern|ivy|grass|leaf|leaves|vine|tree|banyan|trunk|yucca|palm|shrub|flower|pottery|lantern|decal|cable|rope|cloth|debris|garbage|trash|skybox', re.I)
    structural = re.compile(r'wall|floor|ground|stair|step|pillar|column|rock|stone|boulder|crate|box|door|roof|scaffold|temple|arch|concrete|plaster|brick|wood|metal|platform', re.I)
    buckets = collections.defaultdict(list)
    included = []
    skipped = 0

    def visit(index, parent):
        nonlocal skipped
        node = doc['nodes'][index]
        if any(k in node for k in ('translation', 'rotation', 'scale')):
            raise ValueError('Expected Source2Viewer matrix nodes; unsupported TRS')
        matrix = parent @ np.array(node.get('matrix', np.eye(4).flatten(order='F')), dtype=np.float64).reshape(4, 4, order='F')
        if 'mesh' in node:
            mesh = doc['meshes'][node['mesh']]
            name = mesh.get('name', '')
            if exclude.search(name) or ('prop_' in name and not structural.search(name)):
                skipped += 1
            else:
                included.append(name)
                for p in mesh['primitives']:
                    if p.get('mode', 4) != 4:
                        continue
                    source_indices = accessor(p['indices']).reshape(-1)
                    used, inverse = np.unique(source_indices, return_inverse=True)
                    positions = accessor(p['attributes']['POSITION'])[used].astype(np.float64)
                    positions = ((positions @ matrix[:3, :3].T + matrix[:3, 3]) @ axis.T / 0.0254).astype('<f4')
                    indices = inverse.astype(np.uint32)
                    if 'NORMAL' in p['attributes']:
                        normals = accessor(p['attributes']['NORMAL'])[used].astype(np.float64) @ np.linalg.inv(matrix[:3, :3]) @ axis.T
                        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
                    else:
                        raise ValueError('Missing normals in ' + name)
                    faces = indices.reshape(-1, 3)
                    cells = np.floor(positions[faces].mean(axis=1)[:, [0, 2]] / 512).astype(int)
                    for cell in np.unique(cells, axis=0):
                        selected = faces[np.all(cells == cell, axis=1)].reshape(-1)
                        local, local_indices = np.unique(selected, return_inverse=True)
                        key = tuple(cell.tolist())
                        buckets[key].append((positions[local], normals[local].astype('<f4'), local_indices.astype('<u4')))
        for child in node.get('children', []):
            visit(child, matrix)

    for root in doc['scenes'][doc.get('scene', 0)]['nodes']:
        visit(root, np.eye(4))
    output = {'asset': {'version': '2.0', 'generator': 'CSdemowatch tactical filter / Source2Viewer 20'},
              'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [],
              'materials': [{'name': 'Tactical gray', 'pbrMetallicRoughness': {'baseColorFactor': [0.55, 0.57, 0.60, 1], 'metallicFactor': 0, 'roughnessFactor': 1}, 'doubleSided': True}],
              'accessors': [], 'bufferViews': [], 'buffers': []}
    data = bytearray()

    def add_array(array, kind, component):
        data.extend(b'\0' * (-len(data) % 4))
        view = len(output['bufferViews'])
        output['bufferViews'].append({'buffer': 0, 'byteOffset': len(data), 'byteLength': array.nbytes})
        data.extend(array.tobytes())
        a = {'bufferView': view, 'componentType': component, 'count': len(array), 'type': kind}
        if kind == 'VEC3':
            a.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        output['accessors'].append(a)
        return len(output['accessors']) - 1

    triangles = 0
    source_triangles = 0
    for key, parts in sorted(buckets.items()):
        positions, normals, indices = [], [], []
        base = 0
        for pos, norm, ind in parts:
            positions.append(pos)
            normals.append(norm)
            indices.append(ind + base)
            base += len(pos)
            source_triangles += len(ind) // 3
        vertices, remap = np.unique(np.round(np.concatenate(positions), 3), axis=0, return_inverse=True)
        faces = remap[np.concatenate(indices)].reshape(-1, 3)
        if not len(faces):
            continue
        vertices = vertices.astype('<f4')
        faces = faces.astype('<u4')
        face_normals = np.cross(vertices[faces[:, 1]] - vertices[faces[:, 0]], vertices[faces[:, 2]] - vertices[faces[:, 0]])
        vertex_normals = np.zeros_like(vertices)
        for corner in range(3):
            np.add.at(vertex_normals, faces[:, corner], face_normals)
        vertex_normals /= np.maximum(np.linalg.norm(vertex_normals, axis=1, keepdims=True), 1e-9)
        triangles += len(faces)
        pos = add_array(vertices, 'VEC3', 5126)
        norm = add_array(vertex_normals, 'VEC3', 5126)
        ind = add_array(faces.reshape(-1), 'SCALAR', 5125)
        index = len(output['nodes'])
        output['scenes'][0]['nodes'].append(index)
        output['nodes'].append({'name': 'Structure_%d_%d' % key, 'mesh': index})
        output['meshes'].append({'primitives': [{'attributes': {'POSITION': pos, 'NORMAL': norm}, 'indices': ind, 'material': 0}]})
    output['buffers'] = [{'byteLength': len(data)}]
    encoded = json.dumps(output, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    data.extend(b'\0' * (-len(data) % 4))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(data)) + struct.pack('<I4s', len(encoded), b'JSON') + encoded + struct.pack('<I4s', len(data), b'BIN\0') + data)
    report = {'source': str(source), 'source_sha256': hashlib.sha256(blob).hexdigest(), 'output_sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'included_nodes': len(included), 'excluded_nodes': skipped, 'source_triangles': source_triangles, 'triangles': triangles, 'chunks': len(buckets), 'bytes': target.stat().st_size, 'simplification': 'Authored collision triangles preserved; weld=0.001 Source units; invisible clip volumes removed', 'normalization': 'export X,Y,Z -> Z,Y,-X; divide by 0.0254; no replay conversion'}
    target.with_suffix('.build.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    build(Path(sys.argv[1]), Path(sys.argv[2]))
