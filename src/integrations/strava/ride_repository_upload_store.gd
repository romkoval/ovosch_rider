class_name RideRepositoryUploadStore
extends UploadStatusStore
## Адаптер `UploadStatusStore` → `RideRepository` (REQ-STR-05 крит. 2): статус выгрузки
## пишется в метаданные заезда (`Ride.upload`: `strava_status`, `strava_activity_id`,
## `last_error`, `attempts`) через `RideRepository.update_upload_status`.
##
## Словарь очереди (`UploadResult.to_status_dict`) ↔ словарь заезда:
## `status → strava_status`, `activity_id → strava_activity_id`, `error → last_error`,
## `attempts → attempts`; `upload_id`/`code` в заезде не хранятся.

var _rides: RideRepository


func _init(rides: RideRepository) -> void:
	_rides = rides


func update_upload_status(ride_id: String, status: Dictionary) -> void:
	_rides.update_upload_status(ride_id, to_ride_upload(status))


func get_upload_status(ride_id: String) -> Dictionary:
	var ride := _rides.get_ride(ride_id)
	if ride == null:
		return {}
	return from_ride_upload(ride.upload)


## Словарь очереди → `Ride.upload`.
static func to_ride_upload(status: Dictionary) -> Dictionary:
	var out := {}
	if status.has("status"):
		out["strava_status"] = str(status["status"])
	if status.has("activity_id"):
		out["strava_activity_id"] = str(status["activity_id"])
	if status.has("error"):
		out["last_error"] = str(status["error"])
	if status.has("attempts"):
		out["attempts"] = int(status["attempts"])
	return out


## `Ride.upload` → словарь очереди.
static func from_ride_upload(upload: Dictionary) -> Dictionary:
	return {
		"status": str(upload.get("strava_status", UploadResult.STATUS_NONE)),
		"activity_id": str(upload.get("strava_activity_id", "")),
		"upload_id": "",
		"error": str(upload.get("last_error", "")),
		"code": "",
		"attempts": int(upload.get("attempts", 0)),
		"updated_at": 0,
	}
