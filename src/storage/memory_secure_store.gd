class_name MemorySecureStore
extends SecureStore
## Хранилище секретов только в памяти — для тестов и режима разработки.
## Ничего не пишет на диск (REQ-NFR-05 крит. 2).

var _secrets: Dictionary = {}


func set_secret(key: String, value: String) -> bool:
	if not SecureStore.is_valid_key(key) or value.is_empty():
		return false
	_secrets[key] = value
	return true


func get_secret(key: String) -> String:
	return str(_secrets.get(key, ""))


func delete_secret(key: String) -> bool:
	return _secrets.erase(key)


func has_secret(key: String) -> bool:
	return _secrets.has(key)


func list_keys(prefix: String = "") -> Array[String]:
	var out: Array[String] = []
	for k in _secrets.keys():
		var key: String = k
		if prefix.is_empty() or key.begins_with(prefix):
			out.append(key)
	out.sort()
	return out


## Число хранимых секретов.
func size() -> int:
	return _secrets.size()
