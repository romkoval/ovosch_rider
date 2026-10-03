class_name MemoryUploadStatusStore
extends UploadStatusStore
## Статусы выгрузки в памяти — для тестов и до появления адаптера к `RideRepository`.

var statuses: Dictionary = {}
## Журнал всех обновлений `[ride_id, status_dict]` — для проверки переходов (REQ-STR-05 крит. 1).
var history: Array[Array] = []


func update_upload_status(ride_id: String, status: Dictionary) -> void:
	statuses[ride_id] = status.duplicate()
	history.append([ride_id, status.duplicate()])


func get_upload_status(ride_id: String) -> Dictionary:
	return (statuses.get(ride_id, {}) as Dictionary).duplicate()


## Последовательность статусов заезда по журналу.
func status_sequence(ride_id: String) -> Array[String]:
	var out: Array[String] = []
	for h in history:
		if h[0] == ride_id:
			out.append(str(h[1].get("status", "")))
	return out
