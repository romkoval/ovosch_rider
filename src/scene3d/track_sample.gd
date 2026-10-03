class_name TrackSample
extends RefCounted
## Точка трассы на дистанции s (REQ-D3D-06 крит. 1): позиция, направление движения,
## нормаль и уклон. Объект переиспользуется (`Track.sample_into`), чтобы игровой цикл
## не аллоцировал каждый кадр (REQ-D3D-05 крит. 4).

var position: Vector3 = Vector3.ZERO
## Единичный вектор направления движения.
var forward: Vector3 = Vector3.FORWARD
## Единичная нормаль дороги.
var up: Vector3 = Vector3.UP
## Уклон, доли (0.05 = 5 % подъём).
var grade: float = 0.0


## Правый вектор дороги (ортогонален forward и up).
func right() -> Vector3:
	return forward.cross(up).normalized()


## Трансформ велосипедиста в этой точке (-Z смотрит вперёд, как у Camera3D/look_at).
func transform() -> Transform3D:
	var basis := Basis.looking_at(forward, up)
	return Transform3D(basis, position)
