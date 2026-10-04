"""Сетки: numpy-массивы из bpy, связные куски, сечения, дыры, выборка текстуры."""

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def verts_np(mesh):
    a = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_verts_np(mesh, co):
    mesh.vertices.foreach_set("co", np.asarray(co, dtype=np.float64).reshape(-1))
    mesh.update()


def tris_np(mesh):
    """Треугольники (индексы вершин) после триангуляции петель."""
    mesh.calc_loop_triangles()
    a = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
    mesh.loop_triangles.foreach_get("vertices", a)
    return a.reshape(-1, 3)


def edges_np(mesh):
    a = np.empty(len(mesh.edges) * 2, dtype=np.int64)
    mesh.edges.foreach_get("vertices", a)
    return a.reshape(-1, 2)


def components(n_verts, edges):
    """Связные куски по рёбрам: метка куска на вершину (0 — самый большой)."""
    parent = np.arange(n_verts)

    def find(i):
        root = i
        while parent[root] != root:
            root = parent[root]
        while parent[i] != root:
            parent[i], i = root, parent[i]
        return root

    for a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            if ra < rb:
                parent[rb] = ra
            else:
                parent[ra] = rb
    roots = np.array([find(i) for i in range(n_verts)])
    uniq, inv, counts = np.unique(roots, return_inverse=True, return_counts=True)
    order = np.lexsort((uniq, -counts))  # по убыванию размера, при равенстве — по номеру
    rank = np.empty_like(order)
    rank[order] = np.arange(len(order))
    return rank[inv], counts[order]


def boundary_loops(mesh):
    """Число замкнутых граничных контуров (дыр) и число неманифолдных рёбер."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    boundary = [e for e in bm.edges if e.is_boundary]
    nonmanifold = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    seen = set()
    loops = 0
    for e in boundary:
        if e.index in seen:
            continue
        loops += 1
        stack = [e]
        while stack:
            cur = stack.pop()
            if cur.index in seen:
                continue
            seen.add(cur.index)
            for v in cur.verts:
                for e2 in v.link_edges:
                    if e2.is_boundary and e2.index not in seen:
                        stack.append(e2)
    bm.free()
    return loops, nonmanifold


def section_loops(co, tris, origin, normal, region=None):
    """Число замкнутых контуров сечения плоскостью (origin, normal). `region(points)` — маска
    точек сечения, которые учитываются (например, полоса по высоте)."""
    d = (co - np.asarray(origin)) @ np.asarray(normal)
    s = d[tris] > 0.0
    cross = (s.sum(axis=1) == 1) | (s.sum(axis=1) == 2)
    ct = tris[cross]
    if len(ct) == 0:
        return 0
    # Узел — пересечённое ребро (пара вершин), грань соединяет свои два узла.
    nodes = {}
    pairs = []
    pts = []
    for tri in ct:
        ids = []
        for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            if (d[a] > 0.0) != (d[b] > 0.0):
                key = (a, b) if a < b else (b, a)
                if key not in nodes:
                    nodes[key] = len(nodes)
                    t = d[a] / (d[a] - d[b])
                    pts.append(co[a] + (co[b] - co[a]) * t)
                ids.append(nodes[key])
        if len(ids) == 2:
            pairs.append(ids)
    pts = np.array(pts)
    keep = np.ones(len(pts), dtype=bool) if region is None else region(pts)
    pairs = [p for p in pairs if keep[p[0]] and keep[p[1]]]
    labels, _ = components(len(pts), pairs)
    used = np.zeros(len(pts), dtype=bool)
    for a, b in pairs:
        used[a] = used[b] = True
    return len(np.unique(labels[used])) if used.any() else 0


def bvh_from(co, tris):
    return BVHTree.FromPolygons([Vector(v) for v in co], [tuple(int(i) for i in t) for t in tris])


def inside(bvh, point, direction=(0.3, 0.2, 0.93)):
    """Точка внутри замкнутой сетки: чётность пересечений луча."""
    d = Vector(direction).normalized()
    p = Vector(point)
    hits = 0
    for _ in range(64):
        loc, _n, _i, _dist = bvh.ray_cast(p, d)
        if loc is None:
            break
        hits += 1
        p = loc + d * 1e-5
    return hits % 2 == 1


def image_of(obj):
    """Первая текстура цвета материала (glTF: Base Color) или None."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None and node.image.size[0] > 0:
                return node.image
    return None


def image_np(image):
    w, h = image.size
    px = np.empty(w * h * image.channels, dtype=np.float32)
    image.pixels.foreach_get(px)
    return px.reshape(h, w, image.channels)[:, :, :3]


def face_colors(mesh, image):
    """Цвет грани — среднее текселей под UV её углов (линейный, как в Blender), N × 3."""
    pix = image_np(image)
    h, w = pix.shape[:2]
    uv_layer = mesh.uv_layers.active
    n = len(mesh.polygons)
    if uv_layer is None or n == 0:
        return np.zeros((n, 3), dtype=np.float32)
    uv = np.empty(len(mesh.loops) * 2, dtype=np.float64)
    uv_layer.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    x = np.clip((np.mod(uv[:, 0], 1.0) * w).astype(int), 0, w - 1)
    y = np.clip((np.mod(uv[:, 1], 1.0) * h).astype(int), 0, h - 1)
    loop_rgb = pix[y, x].astype(np.float64)
    starts = np.empty(n, dtype=np.int64)
    counts = np.empty(n, dtype=np.int64)
    mesh.polygons.foreach_get("loop_start", starts)
    mesh.polygons.foreach_get("loop_total", counts)
    return (np.add.reduceat(loop_rgb, starts, axis=0) / counts[:, None]).astype(np.float32)


def mesh_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def from_bmesh(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def evaluated_copy(obj, name):
    """Сетка объекта после модификаторов — новой сеткой."""
    dg = bpy.context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def seg_dist(p, a, b):
    """Расстояние от точек p (N × 3) до отрезка ab и параметр t проекции (0..1)."""
    ab = b - a
    ll = float(ab @ ab)
    t = np.clip(((p - a) @ ab) / max(ll, 1e-12), 0.0, 1.0)
    q = a + t[:, None] * ab
    return np.linalg.norm(p - q, axis=1), t


def seg_param(p, a, b):
    """Параметр проекции точек на прямую ab без ограничения (0 — a, 1 — b)."""
    ab = b - a
    return ((p - a) @ ab) / max(float(ab @ ab), 1e-12)
