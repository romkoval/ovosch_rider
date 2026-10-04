"""Конвейер доводки на синтетике (T-143; REQ-D3D-09 п.7, 9 — механизм; п.1–5 — проверка на
синтетическом выходе): шаги 1–5, 7, 8, 11 без ручных действий, детерминизм, испорченные копии,
сантиметры и испорченные оси, фикстура `tests/fixtures/rider_synthetic/rider_synthetic.glb` для GUT."""

import json
import math
import os
import shutil
import tempfile
import unittest

import bpy
import numpy as np
from mathutils import Vector

from rider_refine import common, glbcheck, meshops, proportions, steps, synthetic, weights
from rider_refine.contract import Contract
from rider_refine.steps import Run

FIXTURE = os.path.join(common.ROOT, "tests", "fixtures", "rider_synthetic", "rider_synthetic.glb")


def run(raw, work, first=1, last=11):
    r = Run(raw, work)
    for n, _, _ in common.STEPS:
        if first <= n <= last:
            getattr(r, "step%d" % n)()
    return r


class Pipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="rider_refine_")
        cls.c = Contract()
        cls.raw = {v: synthetic.build(v, os.path.join(cls.tmp, "raw"), cls.c) for v in synthetic.VARIANTS}
        cls.work = os.path.join(cls.tmp, "m")
        run(cls.raw["m"], cls.work)
        cls.glb = os.path.join(cls.work, "rider.glb")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def blend(self, num):
        bpy.ops.wm.open_mainfile(filepath=common.blend_path(self.work, num))
        return bpy.data.objects

    def report(self):
        return common.load_json(os.path.join(self.work, "report.json"))

    # --- шаги ---

    def test_all_steps_leave_blend_and_report(self):
        rep = self.report()
        for n, name, _ in common.STEPS:
            self.assertTrue(os.path.isfile(common.blend_path(self.work, n)), "%02d_%s.blend" % (n, name))
            self.assertIn("%02d_%s" % (n, name), rep)
            self.assertNotEqual(rep["%02d_%s" % (n, name)]["status"], "FAIL")
        self.assertTrue(os.path.isfile(os.path.join(self.work, "rider.blend")))

    def test_step2_units_axes_slab_shells_holes(self):
        objs = self.blend(2)
        me = objs["scan"].data
        co = meshops.verts_np(me)
        shoes = meshops.verts_np(objs["raw_shoes"].data)
        self.assertAlmostEqual(float(shoes[:, 2].min()), 0.0, delta=1e-6, msg="подошвы на земле")
        self.assertAlmostEqual(float(co[:, 2].min()), float(shoes[:, 2].max()), delta=0.002, msg="тело — от верха туфель")
        self.assertTrue(1.7 < float(co[:, 2].max()) < 2.0, "метры")
        low = shoes[shoes[:, 2] < 0.02]
        ext = low.max(axis=0) - low.min(axis=0)
        self.assertLess(ext[0] * ext[1], 0.2, "плиты пола нет: след у земли — стопы (%s)" % ext)
        labels, counts = meshops.components(len(co), meshops.edges_np(me))
        self.assertEqual(len(counts), 1, "одна оболочка: внутренняя и мелочь убраны")
        self.assertEqual(meshops.boundary_loops(me), (0, 0), "дыр и неманифолдных рёбер нет")
        state = json.loads(bpy.context.scene["rr_state"])
        lm = {k: Vector(v) for k, v in state["landmarks_raw"].items()}
        self.assertGreater(lm["crown"].z, lm["pelvis"].z, "Z вверх")
        self.assertGreater(lm["thigh.L"].x, 0.0, "левая сторона +X")
        self.assertLess(lm["cleat.L"].y, lm["heel.L"].y, "лицом в -Y")
        self.assertIn("raw_shoes", objs)
        self.assertLess(meshops.verts_np(objs["raw_shoes"].data)[:, 2].max(), 0.09)

    def test_step3_proportions(self):
        objs = self.blend(3)
        co = meshops.verts_np(objs["scan"].data)
        h = float(co[:, 2].max())
        self.assertTrue(1.74 <= h <= 1.76, "рост (верх сетки головы над z = 0) %.4f — ред. 4.2: 1.74–1.76" % h)
        rep = self.report()["03_proportions"]["metrics"]
        fig = self.c.data["figures"]["m"]
        for k in ("thigh_at_shorts_d_m", "calf_d_m", "upperarm_d_m", "pelvis_outer_m", "neck_d_m", "shoulders_outer_m",
                  "waist_width_m"):
            lo, hi = fig[k]
            self.assertTrue(lo - 0.01 <= rep[k] <= hi + 0.01, "%s = %s (таблица m %s)" % (k, rep[k], fig[k]))

    def test_step3_head_rev42(self):
        """Голова на выходе шага 3 (art-bible «A-поза контрактного скелета», ред. 4.2, [авто]):
        макушка (верх сетки головы) 0.14–0.16 м над началом head и 0.02–0.04 м впереди; высота
        «подбородок — макушка» 0.21–0.23; ширина и длина — таблица ± 0.01; голова не по оси кости."""
        objs = self.blend(3)
        co = meshops.verts_np(objs["scan"].data)
        state = json.loads(bpy.context.scene["rr_state"])
        j = {k: Vector(v) for k, v in state["landmarks"].items()}
        m = proportions.head_measures(co, j)
        self.assertTrue(0.14 <= m["crown_up_m"] <= 0.16, "макушка над началом head %.4f" % m["crown_up_m"])
        self.assertTrue(0.02 <= m["crown_forward_m"] <= 0.04, "макушка впереди начала head %.4f" % m["crown_forward_m"])
        self.assertTrue(0.21 <= m["head_height_m"] <= 0.23, "высота головы %.4f" % m["head_height_m"])
        w, _, ln = self.c.data["proportions"]["head_size_m"]["value"]
        self.assertAlmostEqual(m["head_width_m"], w, delta=0.01)
        self.assertAlmostEqual(m["head_length_m"], ln, delta=0.01)
        # Верх сетки головы — вершина сетки над z = 0, а начало head — на 1.596 (длины контракта).
        self.assertAlmostEqual(j["head"].z, 1.596, delta=0.002)
        self.assertAlmostEqual(float(co[:, 2].max()) - j["head"].z, m["crown_up_m"], delta=0.005)
        tilt = math.degrees(math.atan2(-(j["crown"] - j["head"]).y, (j["crown"] - j["head"]).z))
        self.assertLess(tilt, 17.5, "макушка спеки не на оси кости head (ось — 20° вперёд)")

    def test_step4_base_mesh(self):
        objs = self.blend(4)
        me = objs["body_m"].data
        self.assertLessEqual(meshops.triangle_count(me), 8000)
        self.assertEqual(meshops.boundary_loops(me), (0, 0))
        for key in ("seg_bone", "seg_t", "seg_n", "hint_rgb"):
            self.assertIsNotNone(me.attributes.get(key), key)

    def test_step5_rest_and_saddle(self):
        objs = self.blend(5)
        body = objs["body_m"]
        tree = weights.saddle_tree()
        co = meshops.verts_np(body.data)
        top = weights.saddle_top(tree, co)
        m = ~np.isnan(top) & (co[:, 2] > top - 0.12)
        self.assertTrue(m.any(), "таз над седлом")
        self.assertGreaterEqual(float(np.min(co[m, 2] - top[m])), 0.0, "ни одна вершина таза и шорт не ниже седла")
        s = self.c.head("pelvis")
        s_top = weights.saddle_top(tree, np.array([s[:]]))[0]
        lo, hi = self.c.data["seat"]["s_above_saddle_m"]
        self.assertTrue(lo - 1e-4 <= s.z - s_top <= hi, "S над седлом %.4f" % (s.z - s_top))
        self.assertNotIn("scan", objs)
        self.assertNotIn("fit_rig", objs)

    def test_step5_head_in_rest_rev42(self):
        """Голова на выходе шага 5 (rest; ред. 4.2, [авто]): центр габарита сетки головы без
        волос (0, 1.45, −0.36) ± 0.02 Godot; ось «вверх» головы наклонена вперёд на 10–15°."""
        objs = self.blend(5)
        box = proportions.head_box(steps.head_verts(objs["body_m"]), self.c.rest_head_joints())
        self.assertIsNotNone(box, "грани головы с меткой звена")
        hh, q, _ = proportions.head_system(self.c.rest_head_joints())
        c = Vector(hh + q @ box[0])
        godot = Vector((-c.x, c.z, c.y))
        self.assertLess((godot - Vector((0.0, 1.45, -0.36))).length, 0.02, "центр головы в rest (Godot) %s" % godot)
        tilt = self.c.head_up_rest_tilt_deg()
        self.assertTrue(10.0 <= tilt <= 15.0, "ось «вверх» головы в rest %.2f°" % tilt)
        rep = self.report()["05_rest"]["metrics"]
        self.assertLessEqual(rep["head_center_rest_err_m"], 0.02)

    def test_step7_weights(self):
        objs = self.blend(7)
        body = objs["body_m"]
        groups = [g.name for g in body.vertex_groups]
        self.assertTrue(set(groups) <= set(self.c.deform_bones()) - {"hair_tail.1", "hair_tail.2"}, groups)
        w = weights.weight_matrix(body)
        self.assertLessEqual(int((w > 0).sum(axis=1).max()), 4)
        self.assertLess(float(np.abs(w.sum(axis=1) - 1.0).max()), 1e-4)
        self.assertEqual(body.parent, objs["rider_rig"])
        cp = self.report()["07_weights"]["metrics"]["control_poses"]
        for phi in ("phi0", "phi90", "phi180", "phi270"):
            self.assertLessEqual(cp[phi]["seat_penetration_m"], self.c.data["seat"]["max_penetration_m"], phi)

    def test_step8_regions_uv_material(self):
        objs = self.blend(8)
        me = objs["body_m"].data
        self.assertEqual([m.name for m in me.materials], ["M_rider"])
        self.assertEqual(len(me.uv_layers), 1)
        self.assertEqual(len(me.color_attributes), 0)
        self.assertEqual([i.name for i in bpy.data.images], [])
        reg = np.empty(len(me.polygons), dtype=np.int32)
        me.attributes["region"].data.foreach_get("value", reg)
        self.assertEqual(sorted(set(reg.tolist())), self.c.data["regions"]["required_body"]["value"])

    def test_step11_glb_t1_t7(self):
        metrics, errors = glbcheck.check(self.glb, self.c)
        self.assertEqual(errors, [])
        self.assertEqual(metrics["meshes"], ["body_m"])
        self.assertEqual(metrics["bones"], 25)
        self.assertLessEqual(metrics["rest_max_err_m"], 0.001)
        self.assertLessEqual(metrics["tris"]["body_m"], 8000)
        self.assertLessEqual(metrics["max_influences"], 4)
        self.assertEqual(metrics["socket_weighted"], 0)
        self.assertEqual(metrics["uv_faces_outside"], 0)
        self.assertEqual(metrics["materials"], ["M_rider"])
        doc, _ = glbcheck.read_glb(self.glb)
        self.assertNotIn("images", doc)
        self.assertNotIn("textures", doc)
        attrs = doc["meshes"][0]["primitives"][0]["attributes"]
        self.assertEqual(sorted(attrs), ["JOINTS_0", "NORMAL", "POSITION", "TEXCOORD_0", "WEIGHTS_0"])
        # Импорт Blender по умолчанию: арматура rider_rig в начале координат, масштаб 1, лицом -Y.
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=self.glb)
        arm = bpy.data.objects["rider_rig"]
        self.assertLess(arm.matrix_world.translation.length, 1e-6)
        self.assertLess(max(abs(s - 1.0) for s in arm.scale), 1e-6)
        for n in self.c.order:
            self.assertLess((arm.data.bones[n].head_local - self.c.head(n)).length, 0.001, n)
        self.assertLess(arm.data.bones["grip.L"].head_local.y, arm.data.bones["pelvis"].head_local.y)

    # --- повторяемость, варианты входа, испорченные копии ---

    def test_rerun_same_rider_glb(self):
        work2 = os.path.join(self.tmp, "m2")
        run(self.raw["m"], work2)
        a = open(self.glb, "rb").read()
        b = open(os.path.join(work2, "rider.glb"), "rb").read()
        self.assertEqual(a, b, "повторный прогон на том же входе — тот же rider.glb")

    def test_resume_from_step(self):
        """--from N: продолжение с результата шага N − 1."""
        work = os.path.join(self.tmp, "resume")
        shutil.copytree(self.work, work)
        run(self.raw["m"], work, first=8, last=11)
        self.assertEqual(open(os.path.join(work, "rider.glb"), "rb").read(), open(self.glb, "rb").read())

    def test_cm_and_broken_axes_normalize(self):
        ref = None
        for v in ("m", "cm", "axes"):
            work = os.path.join(self.tmp, "norm_" + v)
            run(self.raw[v], work, 1, 2)
            bpy.ops.wm.open_mainfile(filepath=common.blend_path(work, 2))
            co = meshops.verts_np(bpy.data.objects["scan"].data)
            state = json.loads(bpy.context.scene["rr_state"])
            box = np.concatenate([co.min(axis=0), co.max(axis=0)])
            if ref is None:
                ref = box
                self.assertEqual(state["unit"], "m")
                continue
            self.assertLess(float(np.abs(box - ref).max()), 0.002, "%s: та же фигура после нормализации" % v)
            self.assertEqual(state["unit"], "cm" if v == "cm" else "m")

    def test_broken_copies_fail_at_step1(self):
        for v, what in (("bad_notex", "нет текстуры"), ("bad_legs", "ноги слиплись"), ("bad_two", "не одна фигура")):
            with self.assertRaises(common.StepError) as ctx:
                run(self.raw[v], os.path.join(self.tmp, v), 1, 1)
            self.assertEqual(ctx.exception.step, 1, v)
            self.assertIn(what, ctx.exception.what, v)

    def _copy_with_landmarks(self, name, text=None, src=None):
        d = os.path.join(self.tmp, name)
        os.makedirs(d, exist_ok=True)
        raw = os.path.join(d, name + ".glb")
        shutil.copy(src or self.raw["m"], raw)
        lm = os.path.splitext(self.raw["m"])[0] + ".landmarks.json"
        if text is None:
            shutil.copy(lm, os.path.join(d, name + ".landmarks.json"))
        else:
            open(os.path.join(d, name + ".landmarks.json"), "w").write(text)
        return raw

    def test_bad_landmarks_and_multi_object_fail_at_step1(self):
        """Битый JSON, NaN, перепутанные .L/.R, несколько сеток в файле — StepError шага 1 с
        понятным текстом (не трейсбек, не разворот на 180°, не «ноги слиплись»)."""
        lm = common.load_json(os.path.splitext(self.raw["m"])[0] + ".landmarks.json")
        swapped = {"joints": {n.replace(".L", ".#").replace(".R", ".L").replace(".#", ".R"): v for n, v in lm["joints"].items()}}
        nan = {"joints": dict(lm["joints"], **{"thigh.L": [float("nan"), 0.0, 1.0]})}
        cases = [("badjson", "{joints: [oops", None, "JSON"), ("nanlm", json.dumps(nan), None, "thigh.L"),
                 ("swapped", json.dumps(swapped), None, ".L/.R"), ("multi", None, common.BIKE_GLB, "сеток")]
        for name, text, src, what in cases:
            raw = self._copy_with_landmarks(name, text, src)
            with self.assertRaises(common.StepError) as ctx:
                run(raw, os.path.join(self.tmp, name + "_w"), 1, 1)
            self.assertEqual(ctx.exception.step, 1, name)
            self.assertIn(what, ctx.exception.what, name)
            self.assertNotIn("ноги слиплись", ctx.exception.what, name)

    def test_single_mesh_under_empty_root_passes_step1(self):
        """Единственная сетка — ребёнок пустого корня («world», «RootNode»): обычный вход."""
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=self.raw["m"])
        mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
        root = bpy.data.objects.new("world", None)
        bpy.context.scene.collection.objects.link(root)
        root.location = (0.0, 0.0, 0.0)
        mesh.parent = root
        raw = os.path.join(self.tmp, "parented", "parented.glb")
        os.makedirs(os.path.dirname(raw), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=raw, export_format="GLB")
        shutil.copy(os.path.splitext(self.raw["m"])[0] + ".landmarks.json", os.path.join(os.path.dirname(raw), "parented.landmarks.json"))
        run(raw, os.path.join(self.tmp, "parented_w"), 1, 1)

    def test_decimate_reaches_rider_glb(self):
        """Запасной путь шага 4 (`--retopo decimate`) доходит до rider.glb (метки звена для шага 8)."""
        work = os.path.join(self.tmp, "decimate")
        r = Run(self.raw["m"], work, retopo="decimate")
        for n, _, _ in common.STEPS:
            getattr(r, "step%d" % n)()
        _, errors = glbcheck.check(os.path.join(work, "rider.glb"), self.c)
        self.assertEqual(errors, [])

    def test_missing_landmarks_fail_at_step3(self):
        raw = os.path.join(self.tmp, "nolm", "scan.glb")
        os.makedirs(os.path.dirname(raw))
        shutil.copy(self.raw["m"], raw)
        r = run(raw, os.path.join(self.tmp, "nolm_w"), 1, 2)
        with self.assertRaises(common.StepError) as ctx:
            r.step3()
        self.assertEqual(ctx.exception.step, 3)
        self.assertIn("ориентир", ctx.exception.what)

    def test_gut_fixture_is_pipeline_output(self):
        """`tests/fixtures/rider_synthetic/rider_synthetic.glb` (источник модели GUT
        test_rider_rig_contract) — выход этого конвейера; пересборка — test.sh --update-fixture."""
        if os.environ.get("RR_UPDATE_FIXTURE"):
            shutil.copy(self.glb, FIXTURE)
        self.assertTrue(os.path.isfile(FIXTURE))
        self.assertLess(os.path.getsize(FIXTURE), 1024 * 1024)
        fresh, _ = glbcheck.read_glb(self.glb)
        fixed, _ = glbcheck.read_glb(FIXTURE)
        if fresh["asset"].get("generator") == fixed["asset"].get("generator"):
            self.assertEqual(open(FIXTURE, "rb").read(), open(self.glb, "rb").read(), "фикстура устарела: test.sh --update-fixture")
        else:
            m1, _ = glbcheck.check(self.glb, self.c)
            m2, e2 = glbcheck.check(FIXTURE, self.c)
            self.assertEqual(e2, [])
            for k in ("bones", "regions", "materials", "meshes"):
                self.assertEqual(m1[k], m2[k], k)
