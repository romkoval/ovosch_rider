"""Арматура `rider_rig` в Blender из контракта и A-поза контрактного скелета (T-143;
бриф 5.1–5.3; REQ-D3D-09 п.7 — кости)."""

import math
import unittest

import bpy
from mathutils import Vector

from rider_refine import common, rig
from rider_refine.contract import Contract


class RigFromContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = Contract()

    def setUp(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def test_rest_rig_matches_reference_glb(self):
        arm = rig.build_rest_rig(self.c)
        self.assertEqual(arm.name, "rider_rig")
        bpy.ops.import_scene.gltf(filepath=common.RIG_GLB)
        ref = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o is not arm)
        bones = arm.data.bones
        self.assertEqual(len(bones), 25)
        for b in bones:
            rb = ref.data.bones[b.name]
            self.assertEqual(b.parent.name if b.parent else "", self.c.parent(b.name), b.name)
            self.assertLess((b.head_local - rb.head_local).length, 0.001, b.name)
            self.assertLess((b.head_local - self.c.head(b.name)).length, 1e-5, b.name)
            self.assertLess((b.tail_local - self.c.tail(b.name)).length, 1e-5, b.name)
            m, n = b.matrix_local.to_3x3(), rb.matrix_local.to_3x3()
            for i in range(3):
                self.assertLess(math.degrees(m.col[i].angle(n.col[i])), 0.05, "%s ось %d" % (b.name, i))
            self.assertGreater(m.col[0].x, 0.95, "%s: X кости ∥ X мира" % b.name)
            self.assertEqual(b.use_deform, not self.c.is_socket(b.name), "%s: Deform" % b.name)
        self.assertTrue(arm.matrix_world == arm.matrix_world.Identity(4))

    def test_apose(self):
        """A-поза (pipeline_data «apose»; art-bible «A-поза контрактного скелета» ред. 4.2,
        критерии [авто]): рост 1.74–1.76, ноги прямые, голеностопы ±0.10–0.12, руки 40–45° от
        вертикали во фронтальной плоскости, локоть ≈ 165°, pelvis … neck вертикально ± 3°, ось
        head — 17.5–22.5° вперёд от вертикали, длины костей — контрактные."""
        j = self.c.apose_joints()
        H = {n: v[0] for n, v in j.items()}
        h = self.c.apose_height(j)
        self.assertTrue(1.74 <= h <= 1.76, "рост A-позы %.4f" % h)
        self.assertAlmostEqual(h, self.c.data["height_m"]["value"], delta=self.c.data["height_m"]["tol"])
        for s, sx in ((".L", 1), (".R", -1)):
            self.assertTrue(0.10 <= sx * H["foot" + s].x <= 0.12)
            a, b = H["shin" + s] - H["thigh" + s], H["foot" + s] - H["shin" + s]
            self.assertLess(math.degrees(a.angle(b)), 0.01, "нога прямая")
            arm = H["forearm" + s] - H["upperarm" + s]
            self.assertAlmostEqual(arm.y, 0.0, delta=1e-6)
            self.assertTrue(40 <= math.degrees(arm.angle(Vector((0, 0, -1)))) <= 45)
            el = math.degrees((H["upperarm" + s] - H["forearm" + s]).angle(H["hand" + s] - H["forearm" + s]))
            self.assertAlmostEqual(el, 165.0, delta=0.5)
            self.assertAlmostEqual(H["cleat" + s].z, 0.0, delta=1e-6)
            self.assertAlmostEqual(H["heel" + s].z, 0.0, delta=1e-6)
        for a, b in (("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head")):
            d = H[b] - H[a]
            self.assertLess(math.degrees(d.angle(Vector((0, 0, 1)))), 3.0, a)
        hh, ht, _ = j["head"]
        axis = ht - hh
        tilt = math.degrees(math.atan2(-axis.y, axis.z))
        self.assertTrue(17.5 <= tilt <= 22.5, "ось head вперёд от вертикали %.2f°" % tilt)
        self.assertAlmostEqual(axis.x, 0.0, delta=1e-6)
        self.assertAlmostEqual(H["head"].z, 1.596, delta=0.002, msg="начало head в A-позе (расчёт спеки)")
        for n in self.c.order:
            h, t, _ = j[n]
            self.assertAlmostEqual((t - h).length, (self.c.tail(n) - self.c.head(n)).length, delta=1e-6, msg=n)
            p = self.c.parent(n)
            if p:
                self.assertAlmostEqual((H[n] - H[p]).length, self.c.length(n, p), delta=1e-6, msg=n)

    def test_crown_is_head_mesh_point_not_bone_tail(self):
        """Макушка (ред. 4.2): в A-позе 0.15 вверх и 0.03 вперёд от начала head в системе головы
        (взгляд горизонтально); в rest — та же точка в системе кости head; не окончание head и
        без отдельного «расстояния до макушки по оси кости»."""
        self.assertNotIn("crown_from_head_m", self.c.data["apose"])
        j = self.c.apose_joints()
        rel = self.c.crown(j) - j["head"][0]
        self.assertAlmostEqual(rel.z, 0.15, delta=1e-6)
        self.assertAlmostEqual(-rel.y, 0.03, delta=1e-6)
        self.assertAlmostEqual(rel.x, 0.0, delta=1e-6)
        self.assertGreater((self.c.crown(j) - j["head"][1]).length, 0.01, "макушка — не окончание кости head")
        rest = self.c.rest_joints()
        crown_rest = self.c.crown(rest)
        self.assertAlmostEqual((crown_rest - self.c.head("head")).length, rel.length, delta=1e-6)
        # Центр головы спеки в rest (0, 1.45, −0.36) Godot = (0, −0.36, 1.45) Blender ± 0.02.
        from rider_refine.contract import bone_matrix
        h, t, z = rest["head"]
        c = bone_matrix(h, t, z) @ self.c.head_center_local()
        want = Vector(self.c.data["proportions"]["head_center_rest_m"]["value"])
        self.assertLess((c - want).length, 0.005, "центр головы спеки в rest %s" % c)

    def test_head_up_in_rest_tilts_10_15(self):
        """Ось «вверх» головы (вертикаль A-позы, перенесённая поворотом кости head) в rest
        наклонена вперёд на 10–15° (ред. 4.2): взгляд в rest 10–15° ниже горизонта."""
        tilt = self.c.head_up_rest_tilt_deg()
        self.assertTrue(10.0 <= tilt <= 15.0, "%.2f°" % tilt)
        self.assertAlmostEqual(self.c.head_up_rest().x, 0.0, delta=1e-6)

    def test_apose_rig_poses_exactly_to_rest(self):
        fit = rig.build_armature(self.c, self.c.apose_joints(), "fit_rig")
        rig.pose_to(fit, {n: self.c.rest_matrix(n) for n in self.c.order})
        for pb in fit.pose.bones:
            self.assertLess((pb.head - self.c.head(pb.name)).length, 1e-4, pb.name)
            self.assertLess((pb.tail - self.c.tail(pb.name)).length, 1e-4, pb.name)
