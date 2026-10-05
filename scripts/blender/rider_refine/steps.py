"""Шаги конвейера доводки «Вариант Г» (арт-библия «Гонщик»): 1, 2, 3, 4, 5, 7, 8, 11.

Каждый шаг: открыть `.blend` предыдущего шага (шаг 1 — сырой файл), сделать своё, сохранить
`NN_<шаг>.blend` в рабочий каталог, строка отчёта. Состояние между шагами — в свойстве сцены
`rr_state` (JSON) и копией в `state.json`. Ошибка — `StepError` (шаг, объект, что не так).
"""

import json
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from . import basemesh, common, meshops, regions, rig, scan, weights
from .contract import Contract, base_of, side_of


class Run:
    def __init__(self, raw, work_dir, landmarks=None, retopo="project", contract=None):
        self.raw = os.path.abspath(raw) if raw else None
        self.work = os.path.abspath(work_dir)
        self.landmarks_arg = landmarks
        self.retopo = retopo
        self.c = contract or Contract()
        self.data = self.c.data
        self.report = common.Report(self.work)
        self.state = {}

    # --- состояние и файлы ---

    def load(self, num):
        path = common.blend_path(self.work, num)
        if not os.path.isfile(path):
            raise common.StepError(num, path, "нет результата шага %d — запустите с --from %d или раньше" % (num, num))
        bpy.ops.wm.open_mainfile(filepath=path)
        self.state = json.loads(bpy.context.scene.get("rr_state", "{}"))

    def save(self, num):
        bpy.context.preferences.filepaths.save_version = 0
        bpy.context.scene["rr_state"] = json.dumps(self.state, ensure_ascii=False, sort_keys=True)
        common.save_json(os.path.join(self.work, "state.json"), self.state)
        bpy.ops.wm.save_as_mainfile(filepath=common.blend_path(self.work, num), compress=True)

    def lm(self, key="landmarks"):
        return {k: Vector(v) for k, v in self.state[key].items()} if key in self.state else None

    def set_lm(self, lm, key="landmarks"):
        self.state[key] = {k: [round(float(x), 6) for x in v] for k, v in lm.items()}

    # --- шаг 1 ---

    def step1(self):
        metrics, warns, errors = check_raw(self.raw, self.landmarks_arg, self.data)
        self.state = {"raw": self.raw, "landmarks_file": metrics.pop("landmarks_file", None)}
        if errors:
            self.report.step(1, "FAIL", "проверка сырья: %s" % "; ".join(errors), metrics, warns)
            raise common.StepError(1, os.path.basename(self.raw), "; ".join(errors))
        self.save(1)
        self.report.step(1, "OK" if not warns else "WARN", "сырьё годится (rider-photo-guide §6 п.5)", metrics, warns)
        return metrics, warns

    # --- шаг 2 ---

    def step2(self):
        self.load(1)
        obj, objects = scan.import_raw(self.raw, 2)
        if len(objects) > 1:
            raise common.StepError(2, os.path.basename(self.raw), multi_object_error(objects))
        lm, _ = scan.find_landmarks(self.raw, self.landmarks_arg, 2)
        warns = []
        me = obj.data
        image = meshops.image_of(obj)
        hint = meshops.face_colors(me, image) if image is not None else np.zeros((len(me.polygons), 3))
        attr = me.attributes.new("hint_rgb", "FLOAT_COLOR", "FACE")
        rgba = np.ones((len(me.polygons), 4), dtype=np.float32)
        rgba[:, :3] = hint
        attr.data.foreach_set("color", rgba.reshape(-1))
        co = meshops.verts_np(me)
        rot, how, w = scan.orient(co, lm)
        warns += w
        co = co @ np.array(rot).T
        if lm:
            err = scan.facing_error(co, {n: rot @ v for n, v in lm.items()})
            if err:
                raise common.StepError(2, "landmarks.json", err)
        height = co[:, 2].max() - co[:, 2].min()
        unit, k = scan.units(height, self.data, 2, obj.name)
        xf = Matrix.Diagonal((k, k, k, 1.0)) @ rot.to_4x4()
        me.transform(xf)
        if lm:
            lm = {n: xf @ v for n, v in lm.items()}
        # Куски: плита, внутренние оболочки, мелочь — прочь.
        co = meshops.verts_np(me)
        labels, counts = meshops.components(len(co), meshops.edges_np(me))
        kinds = scan.classify(co, meshops.tris_np(me), labels, counts, self.data)
        if "figure" in kinds:
            raise common.StepError(2, obj.name, "в файле несколько фигур — оставьте одну (шаг 1)")
        removed = {}
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        drop = [bm.verts[i] for i in range(len(co)) if labels[i] != 0]
        for i, kd in enumerate(kinds):
            if kd != "main":
                removed[kd] = removed.get(kd, 0) + 1
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
        # Плита, слитая со стопами: срез по верху плиты.
        co = np.array([v.co[:] for v in bm.verts])
        cut = scan.fused_slab_top(co)
        if cut is not None:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, cut),
                                   plane_no=(0, 0, 1), clear_inner=True)
            removed["slab_fused"] = 1
        # Дыры (и срез плиты) — закрыть, нормали наружу.
        holes_before = sum(1 for e in bm.edges if e.is_boundary)
        res = bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
        bmesh.ops.triangulate(bm, faces=res["faces"])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.update()
        # Начало координат — на земле под серединой голеностопов.
        co = meshops.verts_np(me)
        if lm and "foot.L" in lm and "foot.R" in lm:
            mid = (lm["foot.L"] + lm["foot.R"]) * 0.5
        else:
            low = co[co[:, 2] < co[:, 2].min() + 0.1]
            mid = Vector(((low[:, 0].max() + low[:, 0].min()) / 2, (low[:, 1].max() + low[:, 1].min()) / 2, 0.0))
        shift = Matrix.Translation((-mid.x, -mid.y, -float(co[:, 2].min())))
        me.transform(shift)
        if lm:
            lm = {n: shift @ v for n, v in lm.items()}
        loops, nonman = meshops.boundary_loops(me)
        if loops:
            warns.append("после закрытия осталось дыр: %d" % loops)
        # Разделение: туфли (срез по верху туфли, крышка), волосы (по цвету — копией).
        shoes, hair = split_parts(obj, lm, self.data)
        h = float(meshops.verts_np(me)[:, 2].max())
        self.state.update({"unit": unit, "axes": how, "rotation": [list(r) for r in rot], "height_m": round(h, 4),
                           "removed": removed})
        if lm:
            self.set_lm(lm, "landmarks_raw")
        self.save(2)
        self.report.step(2, "OK", "метры и оси брифа §4, плита и внутренние оболочки убраны, дыры закрыты, тело / туфли / волосы", {
            "unit": unit, "axes": how, "height_m": h, "removed": removed, "holes_closed_edges": holes_before,
            "body_tris": meshops.triangle_count(me), "shoes_tris": shoes, "hair_tris": hair, "nonmanifold": nonman}, warns)

    # --- шаг 3 ---

    def step3(self):
        self.load(2)
        from . import proportions
        lm = self.lm("landmarks_raw")
        obj = bpy.data.objects["scan"]
        if lm is None:
            raise common.StepError(3, "landmarks.json", "нет ориентиров суставов: положите <имя>.landmarks.json рядом с сырым файлом или --landmarks (README)")
        missing = [n for n in proportions.needed(self.c) if n not in lm]
        if missing:
            raise common.StepError(3, "landmarks.json", "нет ориентиров: %s" % ", ".join(missing))
        metrics, warns, target = proportions.fit(obj, lm, self.c)
        self.set_lm(target, "landmarks")
        self.save(3)
        self.report.step(3, "OK" if not warns else "WARN", "длины звеньев — контракт, обхваты — таблица m, голова — размер и центр спеки, A-поза контракта (рост %.2f)" % self.data["height_m"]["value"], metrics, warns)

    # --- шаг 4 ---

    def step4(self):
        self.load(3)
        scan_obj = bpy.data.objects["scan"]
        if self.retopo == "decimate":
            body, metrics, warns = basemesh.decimate(scan_obj, self.c, self.data)
        else:
            body, metrics, warns = basemesh.project(scan_obj, self.c, self.data)
        # Границы шорт и низа джерси, по которым прорезаны рёбра, — шагу 8 (decimate: нет, номинал).
        if "region_cuts" in body:
            self.state["region_cuts"] = {k: float(v) for k, v in body["region_cuts"].to_dict().items()}
            del body["region_cuts"]
        else:
            self.state.pop("region_cuts", None)
        basemesh.transfer_hint(scan_obj, body)
        from .proportions import target_joints
        metrics.update(regions.cut_hairline(body, self.c, target_joints(self.c)))
        basemesh.transfer_hint(scan_obj, body)
        tris = meshops.triangle_count(body.data)
        metrics["body_tris"] = tris
        if tris > self.data["budgets"]["tris"]["body_m"]:
            warns.append("body_m: %d треугольников > бюджета %d (с кольцом линии волос)" % (tris, self.data["budgets"]["tris"]["body_m"]))
        scan_obj.hide_set(True)
        scan_obj.hide_render = True
        self.state["retopo"] = self.retopo
        self.save(4)
        self.report.step(4, "OK" if not warns else "WARN", "ретопология: %s" % ("базовая сетка проекцией на скан" if self.retopo != "decimate" else "децимация скана (запасной путь)"), metrics, warns)

    # --- шаг 5 ---

    def step5(self):
        self.load(4)
        body = bpy.data.objects["body_m"]
        metrics, warns = weights.repose_to_rest(body, self.c)
        seat = weights.seat_on_saddle(body, self.c)
        metrics.update(seat)
        hm, hw = rest_head_check(body, self.c)
        metrics.update(hm)
        warns += hw
        for name in ("scan", "raw_hair", "raw_shoes"):
            o = bpy.data.objects.get(name)
            if o is not None:
                bpy.data.objects.remove(o)
        self.save(5)
        self.report.step(5, "OK" if not warns else "WARN", "A-поза → rest контракта (кости по таблице), таз посажен на седло bike_reference", metrics, warns)

    # --- шаг 7 ---

    def step7(self):
        self.load(5)
        body = bpy.data.objects["body_m"]
        rr = rig.build_rest_rig(self.c)
        metrics, warns = weights.auto_weights(body, rr, self.c)
        metrics.update(weights.control_pose_report(body, rr, self.c))
        lim = self.data["seat"]["max_penetration_m"]
        for phi, m in metrics["control_poses"].items():
            if not phi.startswith("phi"):
                continue
            if m["seat_penetration_m"] > lim:
                warns.append("%s: таз глубже %.3f м в седле (%.3f)" % (phi, lim, m["seat_penetration_m"]))
            if m["thigh_into_saddle_m"] > lim:
                warns.append("%s: бедро проходит сквозь седло на %.3f м — форма/веса бёдер у седла (T-106b′)" % (phi, m["thigh_into_saddle_m"]))
            if m["inverted_faces_added"]:
                warns.append("%s: вывернутых граней больше, чем в rest, на %d" % (phi, m["inverted_faces_added"]))
        self.save(7)
        self.report.step(7, "OK" if not warns else "WARN", "веса автоматически (теплом), ≤ 4 влияний, нормализованы, сокеты и хвост без весов", metrics, warns)

    # --- шаг 8 ---

    def step8(self):
        self.load(7)
        body = bpy.data.objects["body_m"]
        metrics, warns = regions.assign(body, bpy.data.objects[rig.RIG_NAME], self.c, self.state.get("region_cuts"))
        self.save(8)
        self.report.step(8, "OK" if not warns else "WARN", "регионы по размерам спеки (цвет — подсказка), UV0 по атласу, один материал M_rider", metrics, warns)

    # --- шаг 11 ---

    def step11(self):
        self.load(8)
        from . import export
        metrics, warns, errors = export.assemble_and_export(self.work, self.c)
        self.save(11)
        status = "FAIL" if errors else ("WARN" if warns else "OK")
        self.report.step(11, status, "сборка rider.glb (бриф §12) и rider.blend; проверки Т1–Т7 на стороне Blender", metrics, warns + errors)
        if errors:
            raise common.StepError(11, "rider.glb", "; ".join(errors))


def check_raw(path, landmarks_override, data):
    """Шаг 1: метрики сырья (`rider-photo-guide.md` §6 п.5). Итог: метрики, предупреждения,
    ошибки (ошибка — сырьё не годится, конвейер стоп)."""
    errors, warns = [], []
    obj, objects = scan.import_raw(path, 1)
    n_objects = len(objects)
    if n_objects > 1:
        return {"objects": n_objects}, warns, [multi_object_error(objects)]
    try:
        lm, lm_file = scan.find_landmarks(path, landmarks_override, 1)
    except common.StepError as e:
        return {"objects": n_objects}, warns, [e.what]
    me = obj.data
    co = meshops.verts_np(me)
    tris = meshops.tris_np(me)
    rot, how, w = scan.orient(co, lm)
    warns += w
    co = co @ np.array(rot).T
    height = float(co[:, 2].max() - co[:, 2].min())
    try:
        unit, k = scan.units(height, data, 1, obj.name)
    except common.StepError as e:
        return {"height_file_units": height}, warns, [e.what]
    if lm:
        err = scan.facing_error(co, {n: rot @ v for n, v in lm.items()})
        if err:
            errors.append(err)
    co = co * k
    if lm:
        lm = {n: (rot @ v) * k for n, v in lm.items()}
    labels, counts = meshops.components(len(co), meshops.edges_np(me))
    kinds = scan.classify(co, tris, labels, counts, data)
    loops, nonman = meshops.boundary_loops(me)
    main = tris[np.all(labels[tris] == 0, axis=1)]
    zmin = float(co[labels == 0][:, 2].min())
    slab = "slab" in kinds or scan.fused_slab_top(co[labels == 0]) is not None
    body_h = float(co[labels == 0][:, 2].max()) - zmin
    legs, arms, _, _ = scan.section_counts(co, main, lm, body_h)
    image = meshops.image_of(obj)
    ang = scan.arm_angle(lm)
    metrics = {
        "objects": n_objects, "tris": int(len(tris)), "verts": int(len(co)), "unit": unit, "axes": how,
        "height_m": round(body_h, 4), "shells": int(len(counts)),
        "shells_kinds": {kd: kinds.count(kd) for kd in sorted(set(kinds))}, "holes": loops, "nonmanifold_edges": nonman,
        "floor_slab": slab, "legs_section_loops": legs, "arms_section_loops": arms,
        "texture": ("%dx%d" % tuple(image.size)) if image is not None else None,
        "arm_from_vertical_deg": round(ang, 1) if ang is not None else None,
        "landmarks_file": lm_file,
    }
    if kinds.count("figure"):
        errors.append("несвязные куски размером с фигуру: %d — в файле не одна фигура" % (kinds.count("figure") + 1))
    if image is None:
        errors.append("нет текстуры цвета — регионы кожи, перчаток, волос не по чему подсказать (скачайте GLB с текстурой)")
    if kinds.count("figure"):
        pass  # сечения у двух фигур ни о чём не говорят: ошибка «не одна фигура» выше
    elif legs == 0 or arms == 0:
        errors.append("сечение %s не задевает фигуру (0 контуров) — ориентиры не на этой фигуре или не в её единицах"
                      % ("на середине бедра" if legs == 0 else "на уровне локтя"))
    else:
        if legs < 2:
            errors.append("ноги слиплись: на середине бедра %d контур(а) вместо 2" % legs)
        if arms < 3:
            errors.append("руки срослись с корпусом: на уровне локтя %d контур(а) вместо 3" % arms)
    if kinds.count("fragment"):
        warns.append("несвязные мелкие куски: %d (шаг 2 уберёт)" % kinds.count("fragment"))
    if kinds.count("other"):
        warns.append("крупные отдельные куски: %d — проверьте (шаг 2 оставит только тело)" % kinds.count("other"))
    if loops:
        warns.append("дыр: %d (шаг 2 закроет)" % loops)
    if lm is None:
        warns.append("нет ориентиров суставов (landmarks.json): шаг 3 не пройдёт")
    lo, hi = data["raw_check"]["arm_from_vertical_deg"]
    if ang is not None and not lo <= ang <= hi:
        warns.append("поза не A: руки под %.0f° к вертикали (нужно %g–%g°)" % (ang, lo, hi))
    if unit != "m":
        warns.append("единицы файла — %s (шаг 2 переведёт в метры)" % unit)
    return metrics, warns, errors


def head_verts(body):
    """Координаты вершин граней головы (метка звена `seg_bone` шага 4; волос отдельно ещё нет —
    сетка головы без волос)."""
    from .proportions import segments
    me = body.data
    a = me.attributes.get("seg_bone")
    co = meshops.verts_np(me)
    if a is None:
        return co[:0]
    sb = np.empty(len(me.polygons), dtype=np.int64)
    a.data.foreach_get("value", sb)
    k = [s[0] for s in segments()].index("head")
    idx = sorted({v for p in me.polygons if sb[p.index] == k for v in p.vertices})
    return co[idx]


def rest_head_check(body, contract):
    """Голова на выходе шага 5 (art-bible «A-поза контрактного скелета», ред. 4.2, критерии
    [авто]): центр габарита сетки головы в rest — (0, 1.45, −0.36) ± 0.02 Godot = (0, −0.36,
    1.45) Blender; ось «вверх» головы наклонена вперёд на 10–15°. Итог: метрики, предупреждения."""
    from . import proportions
    p = contract.data["proportions"]
    joints = contract.rest_head_joints()
    box = proportions.head_box(head_verts(body), joints)
    c = None
    if box is not None:
        h, q, _ = proportions.head_system(joints)
        c = h + q @ box[0]
    tilt = contract.head_up_rest_tilt_deg()
    metrics = {"head_up_rest_tilt_deg": round(tilt, 2)}
    warns = []
    lo, hi = p["head_up_rest_deg"]["range"]
    if not lo <= tilt <= hi:
        warns.append("голова в rest: ось «вверх» наклонена на %.1f° (спека %.0f–%.0f°)" % (tilt, lo, hi))
    if c is None:
        warns.append("голова в rest: нет граней головы (метки звена шага 4) — центр не измерен")
        return metrics, warns
    want = Vector(p["head_center_rest_m"]["value"])
    err = (Vector(c) - want).length
    metrics.update({"head_center_rest_m": [round(float(x), 4) for x in c], "head_center_rest_err_m": round(err, 4)})
    if err > p["head_center_rest_m"]["tol"]:
        warns.append("голова в rest: центр (%.3f, %.3f, %.3f) — от спеки (0, −0.36, 1.45) на %.3f м (допуск %.2f)"
                     % (c[0], c[1], c[2], err, p["head_center_rest_m"]["tol"]))
    return metrics, warns


def multi_object_error(names):
    """Сырьё из нескольких сеток: art-bible «Вариант Г», шаг 0 — вход «всё слито в одну сетку»,
    шаг 1 — «один исходный файл тела». Части не склеиваются молча: по файлу не понять, части ли
    это одной фигуры (тело + волосы) или сцена (фигура, подставка, велосипед)."""
    shown = ", ".join(names[:6]) + (" …" if len(names) > 6 else "")
    return ("в файле %d сеток (%s), ждём одну сетку фигуры: если это части одной фигуры — объедините их "
            "в одну сетку (Blender: выделить, Ctrl+J) и экспортируйте заново; лишнее (пол, подставка, "
            "велосипед) — удалите" % (len(names), shown))


def raw_score(metrics, warns, errors):
    """Чем меньше, тем лучше (сравнение 2–3 вариантов сырья)."""
    return 1000 * len(errors) + 10 * len(warns) + metrics.get("holes", 0) + metrics.get("shells", 0)


def split_parts(obj, lm, data):
    """Туфли — срез по верху туфли (0.8 высоты голеностопа над подошвой), снизу у тела —
    крышка; куски туфель — объект `raw_shoes`. Волосы — грани над основанием черепа с тёмным
    не-телесным цветом текстуры — копией в `raw_hair` (тело остаётся целым)."""
    me = obj.data
    ankle_z = min(lm["foot.L"].z, lm["foot.R"].z) if lm and "foot.L" in lm else 0.085
    top = 0.8 * ankle_z
    bm = bmesh.new()
    bm.from_mesh(me)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, top), plane_no=(0, 0, 1))
    cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    below = [f for f in bm.faces if f.calc_center_median().z < top]
    shoes_bm = bmesh.new()
    if below:
        tmp = me.copy()
        bm.to_mesh(tmp)
        shoes_bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        shoes_bm.faces.ensure_lookup_table()
        keep = [f for f in shoes_bm.faces if f.calc_center_median().z >= top]
        bmesh.ops.delete(shoes_bm, geom=keep, context="FACES")
        r = bmesh.ops.holes_fill(shoes_bm, edges=shoes_bm.edges[:], sides=0)
        bmesh.ops.triangulate(shoes_bm, faces=r["faces"])
    bmesh.ops.delete(bm, geom=below, context="FACES")
    r = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.triangulate(bm, faces=r["faces"])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    shoes_me = meshops.from_bmesh("raw_shoes", shoes_bm)
    shoes_obj = meshops.mesh_object("raw_shoes", shoes_me)
    shoes_obj.hide_render = True
    # Волосы: копия граней по цвету.
    hair_tris = 0
    if lm and "head" in lm and me.attributes.get("hint_rgb") is not None:
        n = len(me.polygons)
        rgba = np.empty(n * 4, dtype=np.float32)
        me.attributes["hint_rgb"].data.foreach_get("color", rgba)
        rgb = rgba.reshape(-1, 4)[:, :3]
        cen = np.empty(n * 3)
        me.polygons.foreach_get("center", cen)
        cen = cen.reshape(-1, 3)
        dark = rgb.max(axis=1) < 0.12
        skinlike = (rgb[:, 0] > rgb[:, 2] * 1.6) & (rgb[:, 0] > 0.15)
        sel = (cen[:, 2] > lm["head"].z) & dark & ~skinlike
        bmh = bmesh.new()
        bmh.from_mesh(me)
        bmh.faces.ensure_lookup_table()
        bmesh.ops.delete(bmh, geom=[bmh.faces[i] for i in range(n) if not sel[i]], context="FACES")
        hair_me = meshops.from_bmesh("raw_hair", bmh)
        hair_tris = meshops.triangle_count(hair_me)
        hair_obj = meshops.mesh_object("raw_hair", hair_me)
        hair_obj.hide_render = True
    return meshops.triangle_count(shoes_me), hair_tris
