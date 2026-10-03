class_name FitDecoder
extends RefCounted
## Минимальный декодер FIT для проверок round-trip без внешнего SDK
## (REQ-LOC-05 крит. 1–4, REQ-NFR-09 крит. 1).
##
## Разбирает заголовок (12/14 байт), проверяет CRC заголовка и файла, читает
## definition/data messages по локальным типам (обе архитектуры, developer-поля
## пропускаются) и отдаёт сообщения словарями `{global, local, fields}`, где
## `fields` — `{field_num: value}`; invalid-значения → null, строки обрезаются
## по нулевому байту. Поля с несколькими значениями одного базового типа — Array.

## Результат разбора.
class Result:
	extends RefCounted
	var ok: bool = false
	var error: String = ""
	var header_size: int = 0
	var protocol_version: int = 0
	var profile_version: int = 0
	var data_size: int = 0
	var signature: String = ""
	var header_crc: int = 0
	var header_crc_ok: bool = false
	var file_crc: int = 0
	var file_crc_ok: bool = false
	var messages: Array[Dictionary] = []

	## Сообщения с данным глобальным номером.
	func messages_of(global_num: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for m in messages:
			if int(m["global"]) == global_num:
				out.append(m)
		return out

	func count(global_num: int) -> int:
		return messages_of(global_num).size()

	## Значение поля первого сообщения данного типа (null — нет/invalid).
	func first_field(global_num: int, field_num: int) -> Variant:
		var list := messages_of(global_num)
		if list.is_empty():
			return null
		return (list[0]["fields"] as Dictionary).get(field_num, null)


static func decode(bytes: PackedByteArray) -> Result:
	var r := Result.new()
	if bytes.size() < 12:
		r.error = "файл короче заголовка"
		return r
	r.header_size = bytes[0]
	if r.header_size != 12 and r.header_size != 14:
		r.error = "размер заголовка %d" % r.header_size
		return r
	var hdr := StreamPeerBuffer.new()
	hdr.data_array = bytes.slice(0, r.header_size)
	hdr.seek(1)
	r.protocol_version = hdr.get_u8()
	r.profile_version = hdr.get_u16()
	r.data_size = hdr.get_u32()
	r.signature = bytes.slice(8, 12).get_string_from_ascii()
	if r.signature != FitDefinitions.SIGNATURE:
		r.error = "нет сигнатуры .FIT"
		return r
	if r.header_size == 14:
		hdr.seek(12)
		r.header_crc = hdr.get_u16()
		r.header_crc_ok = r.header_crc == 0 or r.header_crc == FitCrc.compute(bytes, 0, 12)
	else:
		r.header_crc_ok = true
	var data_end: int = r.header_size + r.data_size
	if bytes.size() < data_end + 2:
		r.error = "файл короче заявленного размера данных"
		return r
	r.file_crc = bytes[data_end] | (bytes[data_end + 1] << 8)
	r.file_crc_ok = r.file_crc == FitCrc.compute(bytes, 0, data_end)

	var defs: Dictionary = {}
	var pos: int = r.header_size
	while pos < data_end:
		var head: int = bytes[pos]
		pos += 1
		if (head & FitDefinitions.HDR_COMPRESSED_TIMESTAMP) != 0:
			r.error = "сжатый заголовок времени не поддерживается (смещение %d)" % (pos - 1)
			return r
		var local: int = head & FitDefinitions.HDR_LOCAL_MASK
		if (head & FitDefinitions.HDR_DEFINITION) != 0:
			if pos + 5 > data_end:
				r.error = "усечённое определение"
				return r
			var arch: int = bytes[pos + 1]
			var big: bool = arch == 1
			var global_num: int = _u16(bytes, pos + 2, big)
			var num_fields: int = bytes[pos + 4]
			pos += 5
			var fields: Array = []
			var record_len: int = 0
			for i in num_fields:
				if pos + 3 > data_end:
					r.error = "усечённый список полей"
					return r
				fields.append([bytes[pos], bytes[pos + 1], bytes[pos + 2]])
				record_len += bytes[pos + 1]
				pos += 3
			var dev_len: int = 0
			if (head & FitDefinitions.HDR_DEVELOPER_DATA) != 0:
				var num_dev: int = bytes[pos]
				pos += 1
				for i in num_dev:
					dev_len += bytes[pos + 1]
					pos += 3
			defs[local] = {"global": global_num, "big": big, "fields": fields, "len": record_len, "dev_len": dev_len}
		else:
			if not defs.has(local):
				r.error = "данные без определения (локальный тип %d, смещение %d)" % [local, pos - 1]
				return r
			var d: Dictionary = defs[local]
			if pos + int(d["len"]) + int(d["dev_len"]) > data_end:
				r.error = "усечённое сообщение данных"
				return r
			var values: Dictionary = {}
			for f in d["fields"]:
				var size: int = int(f[1])
				values[int(f[0])] = _read_value(bytes, pos, size, int(f[2]), bool(d["big"]))
				pos += size
			pos += int(d["dev_len"])
			r.messages.append({"global": int(d["global"]), "local": local, "fields": values})
	r.ok = r.header_crc_ok and r.file_crc_ok and r.error.is_empty()
	return r


static func _u16(b: PackedByteArray, at: int, big: bool) -> int:
	return (b[at] << 8) | b[at + 1] if big else b[at] | (b[at + 1] << 8)


static func _read_value(b: PackedByteArray, at: int, size: int, base_type: int, big: bool) -> Variant:
	if base_type == FitDefinitions.T_STRING:
		var raw := b.slice(at, at + size)
		var zero := raw.find(0)
		if zero == 0:
			return null
		return (raw.slice(0, zero) if zero > 0 else raw).get_string_from_utf8()
	var unit: int = int(FitDefinitions.BASE_SIZE.get(base_type, 1))
	if size == unit:
		return _read_scalar(b, at, base_type, big)
	var out: Array = []
	var off: int = 0
	while off + unit <= size:
		out.append(_read_scalar(b, at + off, base_type, big))
		off += unit
	return out


static func _read_scalar(b: PackedByteArray, at: int, base_type: int, big: bool) -> Variant:
	var unit: int = int(FitDefinitions.BASE_SIZE.get(base_type, 1))
	var buf := StreamPeerBuffer.new()
	buf.big_endian = big
	buf.data_array = b.slice(at, at + unit)
	var v: Variant
	match base_type:
		FitDefinitions.T_ENUM, FitDefinitions.T_UINT8, FitDefinitions.T_UINT8Z, FitDefinitions.T_BYTE:
			v = buf.get_u8()
		FitDefinitions.T_SINT8:
			v = buf.get_8()
		FitDefinitions.T_UINT16, FitDefinitions.T_UINT16Z:
			v = buf.get_u16()
		FitDefinitions.T_SINT16:
			v = buf.get_16()
		FitDefinitions.T_UINT32, FitDefinitions.T_UINT32Z:
			v = buf.get_u32()
		FitDefinitions.T_SINT32:
			v = buf.get_32()
		FitDefinitions.T_FLOAT32:
			var raw: int = buf.get_u32()
			if raw == 0xFFFFFFFF:
				return null
			buf.seek(0)
			return buf.get_float()
		FitDefinitions.T_FLOAT64:
			return buf.get_double()
		FitDefinitions.T_SINT64:
			v = buf.get_64()
		FitDefinitions.T_UINT64, FitDefinitions.T_UINT64Z:
			v = buf.get_u64()
		_:
			return null
	if FitDefinitions.INVALID.has(base_type) and v == int(FitDefinitions.INVALID[base_type]):
		return null
	return v
