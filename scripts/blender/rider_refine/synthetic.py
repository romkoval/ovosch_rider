"""Синтетический «сырой» вход конвейера (T-143): фигура человека в A-позе, как её отдаёт
сервис генерации 3D по фото, — без файлов владельца.

Строится по контрактному скелету (A-поза из `pipeline_data.json`) с намеренно «чужими»
пропорциями и обхватами (рост ≈ 1.86 м, ноги длиннее, руки короче, бёдра толще): трубки и
эллипсоиды по суставам → одна треугольная сетка (воксельный remesh, всё слито), плита пола под
ногами (слита со ступнями), внутренняя оболочка в груди, дыра на макушке, «варежки» без
пальцев, текстура с запечённой светотенью (цвет формы × свет × затенение). Ориентиры —
`<имя>.landmarks.json` в координатах файла (как их читает импорт Blender по умолчанию).

Варианты: `m` (метры, glTF +Y вверх), `cm` (сантиметры), `axes` (испорченные оси: лежит и
смотрит назад), испорченные копии для шага 1: `bad_notex` (нет текстуры), `bad_legs`
(слипшиеся ноги), `bad_two` (две несвязные фигуры).
"""

import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from . import common, meshops
from .contract import Contract

VARIANTS = ("m", "cm", "axes", "bad_notex", "bad_legs", "bad_two")
# «Чужие» пропорции: множители длины костей (база имени) и параметры A-позы.
SCALES = {"thigh": 1.07, "shin": 1.08, "upperarm": 0.94, "forearm": 0.96, "hand": 1.0, "spine": 1.04,
          "chest": 1.03, "neck": 1.12, "pelvis": 1.0, "head": 1.0}
APOSE = {"arm_from_vertical_deg": 36.0, "ankle_x_m": 0.13, "elbow_deg": 170.0}
VOXEL_M = 0.010
# Цвета формы (линейные) — «Волга Юнион»-подобная тёмная форма: по цвету джерси и шорты не
# разделить (регионы — по размерам спеки, шаг 8).
COLORS = {
    "skin": (0.62, 0.36, 0.25), "hair": (0.05, 0.03, 0.02), "jersey": (0.02, 0.02, 0.025),
    "jersey_side": (0.5, 0.02, 0.02), "shorts": (0.012, 0.012, 0.014), "socks": (0.85, 0.85, 0.85),
    "shoes": (0.03, 0.03, 0.035), "glove": (0.02, 0.02, 0.02), "floor": (0.4, 0.4, 0.4),
}
LIGHT = Vector((0.3, -0.5, 0.8)).normalized()


# Голова — «чужая» по размеру и месту (шаг 3 приводит к спеке): центр эллипсоида в системе
# головы (в A-позе взгляд горизонтально — это оси мира) на (вверх, вперёд) от начала head и
# полуоси (вбок, вперёд-назад, вверх) без носа. Спека: центр габарита 0.04 / 0.04, размер
# 0.155 × 0.22 × 0.20 (art-bible ред. 4.2) — здесь голова ниже, короче и длиннее.
HEAD_CENTER = (0.03, 0.035)
HEAD_HALF = (0.074, 0.096, 0.10)


def head_center(j):
    up, ahead = HEAD_CENTER
    return j["head"][0] + Vector((0.0, -ahead, up))


def joints(contract):
    """Суставы A-позы синтетики и макушка — верхняя точка эллипсоида головы."""
    params = contract.apose_params(**APOSE)
    j = contract.apose_joints(params, SCALES)
    crown = head_center(j) + Vector((0.0, 0.0, HEAD_HALF[2]))
    return j, crown


def _ring(center, x_axis, y_axis, rx, ry, n):
    return [center + x_axis * (rx * math.cos(2 * math.pi * k / n)) + y_axis * (ry * math.sin(2 * math.pi * k / n))
            for k in range(n)]


def _frame(d):
    d = d.normalized()
    ref = Vector((1.0, 0.0, 0.0)) if abs(d.x) < 0.9 else Vector((0.0, 1.0, 0.0))
    x = (ref - d * ref.dot(d)).normalized()
    return x, d.cross(x)


def add_tube(bm, pts, radii, n=20):
    """Труба по точкам `pts` с эллиптическими сечениями `radii` [(rx, ry)] и крышками."""
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        x, y = _frame(d)
        rings.append([bm.verts.new(v) for v in _ring(p, x, y, radii[i][0], radii[i][1], n)])
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def add_ellipsoid(bm, center, radii, rot=None):
    m = Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    m = Matrix.Translation(center) @ m
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0, matrix=m)


def _lerp_pts(a, b, n):
    return [a.lerp(b, k / (n - 1)) for k in range(n)]


def body_parts(bm, j, crown, fused_legs=False):
    H = {n: v[0] for n, v in j.items()}
    # Ноги: бедро (толще вверху), голень с икрой, стопа в туфле.
    for s in (".L", ".R"):
        hip, knee, ankle = H["thigh" + s], H["shin" + s], H["foot" + s]
        top = hip + (hip - knee).normalized() * 0.03
        add_tube(bm, _lerp_pts(top, knee, 5), [(0.100, 0.104), (0.094, 0.098), (0.083, 0.087), (0.07, 0.072), (0.058, 0.06)])
        calf = [knee, knee.lerp(ankle, 0.3), knee.lerp(ankle, 0.6), ankle]
        add_tube(bm, calf, [(0.056, 0.058), (0.064, 0.07), (0.05, 0.052), (0.036, 0.038)])
        add_ellipsoid(bm, knee, (0.056, 0.058, 0.06))
        heel, cleat = H["heel" + s], H["cleat" + s]
        toe = cleat + (cleat - heel).normalized() * 0.075
        mid = (heel + toe) * 0.5
        add_ellipsoid(bm, mid + Vector((0, 0, 0.04)), (0.05, (toe - heel).length * 0.5 + 0.012, 0.045))
        add_tube(bm, [ankle + Vector((0, 0, 0.02)), mid + Vector((0, 0.01, 0.03))], [(0.04, 0.04), (0.045, 0.05)])
    if fused_legs:
        a = (H["shin.L"] + H["thigh.L"]) * 0.5
        b = (H["shin.R"] + H["thigh.R"]) * 0.5
        add_tube(bm, _lerp_pts(a, b, 3), [(0.07, 0.07)] * 3)
    # Таз и корпус: эллиптические сечения шире, чем глубже.
    pel, spine, chest, neck, head = H["pelvis"], H["spine"], H["chest"], H["neck"], H["head"]
    hipmid = (H["thigh.L"] + H["thigh.R"]) * 0.5
    torso = [hipmid - Vector((0, 0, 0.06)), pel.lerp(spine, 0.5) + Vector((0, 0, 0.04)), spine + Vector((0, 0, 0.03)),
             chest, chest.lerp(neck, 0.6), neck - Vector((0, 0, 0.01))]
    add_tube(bm, torso, [(0.17, 0.115), (0.165, 0.11), (0.15, 0.105), (0.17, 0.115), (0.19, 0.11), (0.08, 0.07)], n=24)
    add_ellipsoid(bm, hipmid + Vector((0, 0.04, -0.03)), (0.17, 0.12, 0.1))
    # Шея и голова, нос (перед — −Y).
    add_tube(bm, [neck - Vector((0, 0, 0.02)), head + Vector((0, 0, 0.02))], [(0.062, 0.062), (0.06, 0.06)])
    hc = head_center(j)
    add_ellipsoid(bm, hc, HEAD_HALF)
    add_ellipsoid(bm, hc + Vector((0, -HEAD_HALF[1] - 0.005, -0.01)), (0.012, 0.02, 0.022))
    # Руки: плечо (дельта), предплечье, «варежка».
    for s in (".L", ".R"):
        sh, el, wr, grip = H["upperarm" + s], H["forearm" + s], H["hand" + s], H["grip" + s]
        add_ellipsoid(bm, sh + Vector((0, 0, 0.01)), (0.065, 0.06, 0.06))
        add_tube(bm, _lerp_pts(sh, el, 4), [(0.052, 0.05), (0.05, 0.048), (0.045, 0.043), (0.04, 0.04)])
        add_tube(bm, _lerp_pts(el, wr, 4), [(0.04, 0.04), (0.041, 0.038), (0.033, 0.03), (0.027, 0.024)])
        tip = wr + (grip - wr) * 2.2
        add_ellipsoid(bm, wr.lerp(tip, 0.5), (0.045, 0.024, (tip - wr).length * 0.55),
                      rot=Vector((0, 0, 1)).rotation_difference((tip - wr).normalized()).to_matrix())


def remesh(bm, name):
    me = meshops.from_bmesh(name + "_parts", bm)
    obj = meshops.mesh_object(name + "_parts", me)
    mod = obj.modifiers.new("remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = VOXEL_M
    mod.adaptivity = 0.0
    out = meshops.evaluated_copy(obj, name)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(me)
    return out


def figure(contract, fused_legs=False, offset=None):
    j, crown = joints(contract)
    bm = bmesh.new()
    body_parts(bm, j, crown, fused_legs)
    # Плита пола под ногами, слита со ступнями.
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.0, 0.0, -0.012)) @ Matrix.Diagonal((0.9, 0.7, 0.03, 1.0)))
    me = remesh(bm, "raw")
    if offset is not None:
        me.transform(Matrix.Translation(offset))
    return me, j, crown


def _part_color(p, n, j, crown):
    """Цвет формы точки поверхности по суставам (подсказка, как текстура скана; границы —
    не по спеке: рукав длиннее, носки ниже — шаг 8 берёт размеры спеки, не цвет)."""
    H = {k: v[0] for k, v in j.items()}
    if p.z < 0.005:
        return COLORS["floor"]
    best, part = 1e9, "jersey"
    segs = [("thigh", "shin"), ("shin", "foot"), ("upperarm", "forearm"), ("forearm", "hand"), ("hand", "grip")]
    for s in (".L", ".R"):
        for a, b in segs:
            pa, pb = H[a + s], H[b + s]
            if b == "grip":
                pb = pa + (pb - pa) * 2.2
            ab = pb - pa
            t = max(0.0, min(1.0, (p - pa).dot(ab) / ab.length_squared))
            d = (p - (pa + ab * t)).length
            if d < best:
                best, part = d, (a, t)
    torso_d = min((p - H[k]).length for k in ("pelvis", "spine", "chest", "neck"))
    head_d = (p - head_center(j)).length
    if head_d < 0.13 and p.z > H["neck"].z + 0.03:
        back = p.y - H["head"].y
        return COLORS["hair"] if (p.z > H["head"].z + 0.09 or (back > 0.03 and p.z > H["head"].z)) else COLORS["skin"]
    if p.z < H["foot.L"].z + 0.035:
        return COLORS["shoes"]
    if isinstance(part, tuple) and best < torso_d:
        a, t = part
        if a == "thigh":
            return COLORS["shorts"] if t < 0.72 else COLORS["skin"]
        if a == "shin":
            return COLORS["skin"] if t < 0.55 else COLORS["socks"]
        if a == "upperarm":
            return COLORS["jersey"] if t < 0.58 else COLORS["skin"]
        if a == "forearm":
            return COLORS["skin"] if t < 0.92 else COLORS["glove"]
        return COLORS["glove"]
    if p.z < H["spine"].z - 0.02:
        return COLORS["shorts"]
    if p.z < H["neck"].z and abs(p.x) > 0.13 and abs(n.x) > 0.75:
        return COLORS["jersey_side"]
    return COLORS["jersey"] if p.z < H["neck"].z + 0.03 else COLORS["skin"]


def bake_texture(me, j, crown, name):
    """Текстура «запечённого» вида: пиксель на вершину (цвет формы × свет × затенение снизу),
    UV вершины — центр её пикселя (без швов: сетка в glTF не рвётся)."""
    n = len(me.vertices)
    w = 512
    h = 1
    while w * h < n:
        h *= 2
    img = bpy.data.images.new(name + "_tex", w, h, alpha=False)
    px = np.zeros((h, w, 4), dtype=np.float32)
    px[:, :, 3] = 1.0
    me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
    for v in me.vertices:
        x, y = v.index % w, v.index // w
        c = Vector(_part_color(v.co, v.normal, j, crown))
        light = 0.35 + 0.65 * max(0.0, v.normal.dot(LIGHT))
        ao = 0.55 + 0.45 * min(1.0, max(0.0, v.co.z / 0.5)) if v.co.z < 0.5 else 1.0
        px[y, x, :3] = tuple(min(1.0, comp * light * ao * 1.6) for comp in c)
    uv_layer = me.uv_layers.new(name="UVMap")
    vidx = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vidx)
    uvs = np.stack(((vidx % w + 0.5) / w, (vidx // w + 0.5) / h), axis=1)
    uv_layer.data.foreach_set("uv", uvs.reshape(-1))
    img.pixels.foreach_set(px.reshape(-1))
    img.pack()
    return img


def material_with(img, name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if img is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def corrupt(me, landmarks, variant):
    """Порча единиц и осей файла: та же порча — у ориентиров."""
    m = Matrix.Identity(4)
    if variant == "cm":
        m = Matrix.Scale(100.0, 4)
    elif variant == "axes":
        # «Сервис» записал Z-up без перевода и лицом назад: после импорта фигура лежит.
        m = Matrix.Rotation(math.radians(90.0), 4, "X") @ Matrix.Rotation(math.radians(180.0), 4, "Z")
    me.transform(m)
    return {k: list(m @ Vector(v)) for k, v in landmarks.items()}


def build(variant, out_dir, contract=None):
    """Собрать вариант: `<out>/synthetic_<variant>.glb` и `.landmarks.json`. Итог — путь glb."""
    assert variant in VARIANTS, variant
    contract = contract or Contract()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    name = "synthetic_" + variant
    me, j, crown = figure(contract, fused_legs=(variant == "bad_legs"))
    if variant == "bad_two":
        me2, _, _ = figure(contract, offset=Vector((1.1, 0.3, 0.0)))
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.from_mesh(me2)
        bm.to_mesh(me)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(me)
    # Дыра на макушке.
    hole = [f for f in bm.faces if (f.calc_center_median() - crown).length < 0.025]
    bmesh.ops.delete(bm, geom=hole, context="FACES")
    # Внутренняя оболочка в груди.
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.06, matrix=Matrix.Translation(j["chest"][0] + Vector((0, 0.01, 0.02))))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    landmarks = {n: list(v[0]) for n, v in j.items() if not n.startswith("hair_tail")}
    landmarks["crown"] = list(crown)
    img = None if variant == "bad_notex" else bake_texture(me, j, crown, name)
    if img is None:
        me.uv_layers.new(name="UVMap")
    landmarks = corrupt(me, landmarks, variant)
    obj = meshops.mesh_object(name, me)
    me.materials.append(material_with(img, "M_scan"))
    os.makedirs(out_dir, exist_ok=True)
    glb = os.path.join(out_dir, name + ".glb")
    for o in bpy.context.view_layer.objects:
        o.select_set(o == obj)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_animations=False, export_image_format="AUTO")
    common.save_json(os.path.join(out_dir, name + ".landmarks.json"), {
        "about": "Ориентиры суставов синтетики T-143: координаты файла после импорта Blender по умолчанию (+Y Up)",
        "units": "file", "joints": {k: [round(x, 6) for x in v] for k, v in landmarks.items()}})
    return glb


def build_all(out_dir, variants=VARIANTS):
    contract = Contract()
    return [build(v, out_dir, contract) for v in variants]
