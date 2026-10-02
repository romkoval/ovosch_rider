class_name IntervalsPlanService
extends RefCounted
## План на сегодня: сеть → кэш (REQ-INT-02, REQ-INT-04 крит. 1–2 данные, REQ-INT-07, REQ-NFR-03).
##
## `load_today(profile_id, today)`:
## - успех → список тренировок сохраняется в `PlanCache` (крит. 1), `ApiResult.ok`,
##   `code` `ok` или `no_workout_today` (пустой список тоже кэшируется);
## - сеть недоступна / 5xx / 429 → кэш на сегодня: если есть — `ok`, `from_cache`,
##   `code = from_cache`, `message` «из кэша, загружен <время>» (крит. 2); кэша другой
##   даты не бывает в выдаче (крит. 3); кэша нет — исходная ошибка с `can_retry`;
## - 401/403 и «не настроено» — ошибка без обращения к кэшу (ключ надо чинить).
## Данные `ApiResult.data`: `Array[Dictionary]` `{event_id, name, duration_sec,
## training_load, workout, parse_result}` — записи с `workout == null` (ошибка разбора)
## в кэш не попадают, но в сетевой выдаче остаются для показа причины.

var _client: IntervalsIcuClient
var _cache: PlanCache
var _profile_id: String


func _init(client: IntervalsIcuClient, cache: PlanCache) -> void:
	_client = client
	_cache = cache
	_profile_id = client.profile_id()


func load_today(today: String = "") -> ApiResult:
	var date := today if not today.is_empty() else IntervalsIcuClient.local_date()
	var result: ApiResult = await _client.get_today_workouts(date)
	if result.ok:
		var loaded_at := int(Time.get_unix_time_from_system())
		_cache.save(_profile_id, date, result.data, loaded_at)
		result.loaded_at = loaded_at
		return result
	if result.code == ApiResult.CODE_AUTH_FAILED or result.code == ApiResult.CODE_NOT_CONFIGURED:
		return result
	var cached := _cache.get_today(_profile_id, date)
	if cached.is_empty():
		return result
	var from_cache := ApiResult.success(cached["workouts"], ApiResult.CODE_FROM_CACHE,
			PlanCache.cache_label(int(cached["loaded_at"]), date))
	from_cache.from_cache = true
	from_cache.loaded_at = int(cached["loaded_at"])
	from_cache.can_retry = true
	if (cached["workouts"] as Array).is_empty():
		from_cache.code = ApiResult.CODE_NO_WORKOUT_TODAY
	return from_cache


## Только кэш, без сети (для запуска без сети — 0 запросов, REQ-INT-07 крит. 4).
func cached_today(today: String = "") -> ApiResult:
	var date := today if not today.is_empty() else IntervalsIcuClient.local_date()
	var cached := _cache.get_today(_profile_id, date)
	if cached.is_empty():
		return ApiResult.failure(ApiResult.CODE_NETWORK, "план на сегодня не загружен", 0, true)
	var r := ApiResult.success(cached["workouts"], ApiResult.CODE_FROM_CACHE, PlanCache.cache_label(int(cached["loaded_at"]), date))
	r.from_cache = true
	r.loaded_at = int(cached["loaded_at"])
	if (cached["workouts"] as Array).is_empty():
		r.code = ApiResult.CODE_NO_WORKOUT_TODAY
	return r


## Длительность для списка (REQ-INT-04 крит. 2): `мм:сс` до часа, иначе `ч:мм:сс`.
static func format_duration(sec: int) -> String:
	var s := maxi(sec, 0)
	if s < 3600:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
