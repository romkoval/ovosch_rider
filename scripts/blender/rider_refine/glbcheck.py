"""Проверки Т1–Т7 брифа §14 по самому файлу `rider.glb` (читается без Blender: GLB → JSON и
буферы), со стороны конвейера (T-143, шаг 11). Импорт в Godot и Т8 — `tests/` и T-106a4."""

import json
import math
import struct

import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError("не GLB 2.0")
    jlen, jtype = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20:20 + jlen].decode("utf-8"))
    off = 20 + jlen
    binary = b""
    if off < len(data):
        blen, _ = struct.unpack_from("<II", data, off)
        binary = data[off + 8: off + 8 + blen]
    return doc, binary


def accessor(doc, binary, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    dtype = np.dtype(COMP[acc["componentType"]])
    width = WIDTH[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or dtype.itemsize * width
    count = acc["count"]
    raw = np.frombuffer(binary, dtype=np.uint8, count=stride * (count - 1) + dtype.itemsize * width, offset=start)
    out = np.lib.stride_tricks.as_strided(raw, shape=(count, dtype.itemsize * width), strides=(stride, 1)).copy()
    arr = out.view(dtype).reshape(count, width)
    if acc.get("normalized"):
        arr = arr.astype(np.float64) / np.iinfo(dtype).max
    return arr


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = t
    return m


def to_blender(g):
    """glTF (+Y вверх) → Blender: (x, y, z) → (x, −z, y)."""
    return np.array([g[0], -g[2], g[1]])


def check(path, contract):
    """Итог: метрики, ошибки (строки «Тn: …»)."""
    doc, binary = read_glb(path)
    errors = []
    data = contract.data
    nodes = doc.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}

    def world(i):
        m = node_matrix(nodes[i])
        while i in parent:
            i = parent[i]
            m = node_matrix(nodes[i]) @ m
        return m

    # Т1 (часть конвейера): арматура и сетки.
    if "rider_rig" not in by_name:
        errors.append("Т1: нет узла арматуры rider_rig")
    meshes = [n.get("name") for n in nodes if "mesh" in n]
    allowed = list(data["budgets"]["tris"].keys())
    for m in meshes:
        if m not in allowed:
            errors.append("Т1: сетка %s — не из списка брифа §3" % m)
    # Т2: кости.
    skins = doc.get("skins", [])
    if len(skins) != 1:
        errors.append("Т2: скинов %d, нужен один" % len(skins))
        return {"meshes": meshes}, errors
    joints = skins[0]["joints"]
    jnames = [nodes[j].get("name") for j in joints]
    want = contract.order
    if sorted(jnames) != sorted(want):
        errors.append("Т2: кости %s ≠ контракт" % sorted(set(jnames) ^ set(want)))
    worst = 0.0
    for j in joints:
        name = nodes[j].get("name")
        if name not in contract.by_name:
            continue
        par = parent.get(j)
        pname = nodes[par].get("name") if par is not None and par in joints else ""
        if pname != contract.parent(name):
            errors.append("Т2: %s — родитель %s, нужен %s" % (name, pname or "—", contract.parent(name) or "—"))
        head = to_blender(world(j)[:3, 3])
        worst = max(worst, float(np.linalg.norm(head - np.array(contract.head(name)))))
    if worst > 0.001:
        errors.append("Т2: rest — начало кости дальше 1 мм от контракта (%.4f м)" % worst)
    # Т3: материал, атрибуты, текстуры, анимации.
    mats = [m.get("name") for m in doc.get("materials", [])]
    if mats != ["M_rider"]:
        errors.append("Т3: материалы %s, нужен один M_rider" % mats)
    for key in ("textures", "images", "animations"):
        if doc.get(key):
            errors.append("Т3: в файле есть %s" % key)
    tris_total = {}
    inf_max = 0
    sum_err = 0.0
    socket_w = 0
    uv_bad = 0
    regions = set()
    sockets = set(contract.sockets())
    count = contract.json["regions"]["count"]
    margin = contract.json["regions"]["margin"]
    first_bike = contract.json["regions"]["first_bike"]
    for ni, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        name = n.get("name")
        if not np.allclose(world(ni), np.eye(4), atol=1e-6):
            errors.append("Т7: %s — трансформ не применён" % name)
        mesh = doc["meshes"][n["mesh"]]
        if mesh.get("name") != name:
            errors.append("бриф §12: сетка %s названа %s" % (name, mesh.get("name")))
        tris = 0
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            if prim.get("targets"):
                errors.append("Т3: %s — shape keys" % name)
            for bad in ("COLOR_0", "TEXCOORD_1", "JOINTS_1", "WEIGHTS_1"):
                if bad in attrs:
                    errors.append("Т3: %s — атрибут %s" % (name, bad))
            idx = accessor(doc, binary, prim["indices"]).reshape(-1)
            tris += len(idx) // 3
            if "TEXCOORD_0" not in attrs:
                errors.append("Т6: %s — нет UV0" % name)
            else:
                uv = accessor(doc, binary, attrs["TEXCOORD_0"])
                u = uv[idx.reshape(-1, 3), 0]
                col = np.floor(u.mean(axis=1) * count).astype(int)
                lo = (col[:, None] + margin) / count - 1e-6
                hi = (col[:, None] + 1 - margin) / count + 1e-6
                uv_bad += int(np.sum(np.any((u < lo) | (u > hi), axis=1)))
                regions |= set(int(c) for c in np.unique(col))
            if "JOINTS_0" in attrs and "WEIGHTS_0" in attrs:
                jj = accessor(doc, binary, attrs["JOINTS_0"]).astype(int)
                ww = accessor(doc, binary, attrs["WEIGHTS_0"]).astype(np.float64)
                inf_max = max(inf_max, int((ww > 0).sum(axis=1).max()))
                sum_err = max(sum_err, float(np.abs(ww.sum(axis=1) - 1.0).max()))
                for k in range(4):
                    names = np.array([jnames[j] for j in jj[:, k]])
                    socket_w += int(np.sum((ww[:, k] > 0) & np.isin(names, list(sockets))))
            else:
                errors.append("Т5: %s — без скиннинга" % name)
        tris_total[name] = tris
        budget = data["budgets"]["tris"].get(name)
        if budget is not None and tris > budget:
            errors.append("Т4: %s — %d треугольников > %d" % (name, tris, budget))
    if inf_max > data["budgets"]["max_influences"]:
        errors.append("Т5: влияний на вершину %d > 4" % inf_max)
    if sum_err > 2e-3:
        errors.append("Т5: сумма весов отличается от 1 на %.4f" % sum_err)
    if socket_w:
        errors.append("Т5: веса на сокетах у %d вершин" % socket_w)
    if uv_bad:
        errors.append("Т6: %d граней не внутри колонки атласа с отступом 10 %%" % uv_bad)
    if any(r >= first_bike for r in regions):
        errors.append("Т6: регионы велосипеда в UV тела: %s" % sorted(r for r in regions if r >= first_bike))
    if "body_m" in tris_total:
        need = data["regions"]["required_body"]["value"]
        miss = [r for r in need if r not in regions]
        if miss:
            errors.append("Т6: у body_m нет регионов %s" % miss)
    rig = by_name.get("rider_rig")
    if rig is not None and not np.allclose(node_matrix(nodes[rig]), np.eye(4), atol=1e-6):
        errors.append("Т7: rider_rig не в начале координат / поворот / масштаб")
    for i, n in enumerate(nodes):
        if "scale" in n and not np.allclose(n["scale"], [1, 1, 1], atol=1e-6):
            errors.append("Т7: узел %s — масштаб %s" % (n.get("name"), n["scale"]))
    size_mb = len(binary) / 1e6
    if size_mb > data["budgets"]["file_mb"]:
        errors.append("бриф: файл %.1f МБ > 4" % size_mb)
    metrics = {"meshes": meshes, "bones": len(jnames), "rest_max_err_m": round(worst, 6), "tris": tris_total,
               "max_influences": inf_max, "weight_sum_err": round(sum_err, 6), "socket_weighted": socket_w,
               "uv_faces_outside": uv_bad, "regions": sorted(regions), "materials": mats,
               "generator": doc.get("asset", {}).get("generator")}
    return metrics, errors
