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
        """A-поза (pipeline_data «apose»): рост 1.78 ± 0.01, ноги прямые, голеностопы ±0.10–0.12,
        руки 40–45° от вертикали во фронтальной плоскости, локоть ≈ 165°, корпус и голова прямо,
        длины костей — контрактные."""
        j = self.c.apose_joints()
        H = {n: v[0] for n, v in j.items()}
        self.assertAlmostEqual(self.c.apose_height(j), 1.78, delta=0.01)
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
            self.assertLess(math.degrees(d.angle(Vector((0, 0, 1)))), 0.01, a)
        for n in self.c.order:
            h, t, _ = j[n]
            self.assertAlmostEqual((t - h).length, (self.c.tail(n) - self.c.head(n)).length, delta=1e-6, msg=n)
            p = self.c.parent(n)
            if p:
                self.assertAlmostEqual((H[n] - H[p]).length, self.c.length(n, p), delta=1e-6, msg=n)

    def test_apose_rig_poses_exactly_to_rest(self):
        fit = rig.build_armature(self.c, self.c.apose_joints(), "fit_rig")
        rig.pose_to(fit, {n: self.c.rest_matrix(n) for n in self.c.order})
        for pb in fit.pose.bones:
            self.assertLess((pb.head - self.c.head(pb.name)).length, 1e-4, pb.name)
            self.assertLess((pb.tail - self.c.tail(pb.name)).length, 1e-4, pb.name)
