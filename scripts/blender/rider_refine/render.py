"""Кадры для отчёта (Cycles на CPU — работает и без GPU/дисплея): ракурсы контракта
(`rider_contract.json` → views, бриф §14) и произвольные камеры. Не продуктовые кадры:
синтетика и промежуточные шаги конвейера."""

import math

import bpy
from mathutils import Vector


def setup(width=640, height=360, samples=12):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.62, 0.72, 1.0)
    bg.inputs[1].default_value = 0.8
    if "rr_sun" not in bpy.data.objects:
        sun = bpy.data.objects.new("rr_sun", bpy.data.lights.new("rr_sun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
        bpy.context.scene.collection.objects.link(sun)


def camera(name, loc, target, fov_deg):
    cam_data = bpy.data.cameras.new(name)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(fov_deg)
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return cam


def shot(path, loc, target, fov_deg=40.0):
    cam = camera("rr_cam", loc, target, fov_deg)
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    return path


def view_shot(path, view):
    return shot(path, view["camera"], view["target"], view["fov_deg"])
