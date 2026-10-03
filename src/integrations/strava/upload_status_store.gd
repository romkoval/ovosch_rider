class_name UploadStatusStore
extends RefCounted
## Интерфейс хранения статуса выгрузки заезда (REQ-STR-05 крит. 2).
##
## Реализацию поверх `RideRepository` (метаданные заезда `strava_status`,
## `strava_activity_id`) пишет владелец хранилища заездов; до её появления — адаптер
## `RideRepository.update_upload_status/get_upload_status` или `MemoryUploadStatusStore`
## в тестах. Словарь статуса — `UploadResult.to_status_dict()`:
## `{status, activity_id, upload_id, error, code, attempts, updated_at}`.


func update_upload_status(_ride_id: String, _status: Dictionary) -> void:
	push_error("UploadStatusStore.update_upload_status: not implemented")


## Статус заезда; пустой словарь или `{status: "none"}`, если выгрузок не было.
func get_upload_status(_ride_id: String) -> Dictionary:
	push_error("UploadStatusStore.get_upload_status: not implemented")
	return {}
