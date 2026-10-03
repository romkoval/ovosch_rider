class_name PerfBudget
extends RefCounted
## Бюджет производительности 3D-сцены (REQ-D3D-05 крит. 2–4, решение В-7). Числа
## продублированы в `docs/perf_budget.md`; тест сверяет документ с константами.

const MAX_MESH_INSTANCES: int = 60
const MAX_MATERIALS: int = 12
const MAX_LIGHTS: int = 3
## Ручной замер на устройстве (`RenderingServer.get_rendering_info`).
const MAX_DRAW_CALLS: int = 150
const MAX_MULTIMESH_INSTANCES: int = 2000
const MIN_PHYSICS_TICKS_PER_SECOND: int = 60


## Подсчёт узлов сцены: `{mesh_instances, materials, lights, multimesh_instances}`.
static func count(root: Node) -> Dictionary:
	var materials: Dictionary = {}
	var result := {"mesh_instances": 0, "lights": 0, "multimesh_instances": 0}
	_walk(root, result, materials)
	result["materials"] = materials.size()
	return result


static func _walk(node: Node, result: Dictionary, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		result["mesh_instances"] += 1
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat != null:
					materials[mat.get_instance_id()] = true
	elif node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null:
			result["multimesh_instances"] += mm.instance_count
			if mm.mesh != null:
				for i in mm.mesh.get_surface_count():
					var mat: Material = mm.mesh.surface_get_material(i)
					if mat != null:
						materials[mat.get_instance_id()] = true
	elif node is Light3D:
		result["lights"] += 1
	for child in node.get_children():
		_walk(child, result, materials)
