class_name RideRepository
extends RefCounted
## Интерфейс хранилища заездов (REQ-LOC-01 крит. 5, решение В-3).
##
## Все критерии LOC формулируются через этот интерфейс; реализация MVP —
## файловая (`FileRideRepository`), SQLite — допустимая замена позже.
## Никакой код вне `src/storage/` не знает о файлах заезда.
##
## Жизненный цикл заезда (LOC-07): `save()` — полная запись; во время
## тренировки `RideRecorder` вызывает `append_samples()` (дозапись потока) и
## `save_meta()` (метаданные и события) каждые 10 с; незавершённые заезды
## (`metadata.in_progress`) при следующем запуске поднимает `recover_in_progress()`.
##
## Каскад удаления профиля (REQ-PRF-04 крит. 1): `attach_to_profiles()`
## регистрирует хук в `ProfileRepository`.

## Список заездов профиля изменился (сохранение, удаление, смена статуса).
signal rides_changed(profile_id: String)
## Заезд записан целиком через `save()` (в т. ч. при завершении тренировки) —
## подписчики (очередь выгрузки в Strava, T-049) проверяют `Ride.is_in_progress()`.
signal ride_saved(ride_id: String)


## Полная запись заезда (метаданные, события, статус, сводка, поток). Возвращает id.
func save(_ride: Ride) -> String:
	push_error("RideRepository.save: не реализовано")
	return ""


## Заезд целиком (с потоком) или null.
func get_ride(_id: String) -> Ride:
	push_error("RideRepository.get_ride: не реализовано")
	return null


## Сводки заездов профиля, новые сверху (REQ-LOC-02 крит. 1).
func list(_profile_id: String) -> Array[RideSummary]:
	push_error("RideRepository.list: не реализовано")
	return []


## Удалить заезд с потоками (REQ-LOC-06 крит. 1). false — заезда нет.
func delete(_id: String) -> bool:
	push_error("RideRepository.delete: не реализовано")
	return false


## Обновить статус выгрузки (REQ-STR-05 крит. 2): ключи `strava_status`,
## `strava_activity_id`, `last_error`, `attempts` сливаются в `Ride.upload`.
func update_upload_status(_id: String, _status: Dictionary) -> bool:
	push_error("RideRepository.update_upload_status: не реализовано")
	return false


## Удалить все заезды профиля. Возвращает число удалённых.
func delete_profile_rides(_profile_id: String) -> int:
	push_error("RideRepository.delete_profile_rides: не реализовано")
	return 0


## Дозапись сэмплов `[from_index, samples.size())` в поток заезда (LOC-07 крит. 1).
func append_samples(_id: String, _samples: SampleStream, _from_index: int) -> bool:
	push_error("RideRepository.append_samples: не реализовано")
	return false


## Запись метаданных, событий, статуса и сводки без потока (LOC-07).
func save_meta(_ride: Ride) -> bool:
	push_error("RideRepository.save_meta: не реализовано")
	return false


## Промежуточная запись метаданных и событий во время тренировки (периодический сброс
## `RideRecorder`, LOC-07 крит. 1, 4): должна укладываться в бюджет тика, поэтому реализация
## может писать дешевле, чем `save_meta`. По умолчанию — `save_meta`.
func save_progress(ride: Ride) -> bool:
	return save_meta(ride)


## Незавершённые заезды профиля (LOC-07 крит. 2, 3): помечаются `recovered`,
## `in_progress = false`, `stopped_early = true`, получают сводку по имеющимся данным
## и сохраняются; возвращаются целиком (с потоком).
func recover_in_progress(_profile_id: String) -> Array[Ride]:
	push_error("RideRepository.recover_in_progress: не реализовано")
	return []


## Подписаться на удаление профиля — каскадно удалить его заезды (REQ-PRF-04 крит. 1).
func attach_to_profiles(profiles: ProfileRepository) -> void:
	profiles.add_on_delete_hook(_on_profile_deleted)


func _on_profile_deleted(profile_id: String) -> void:
	delete_profile_rides(profile_id)
