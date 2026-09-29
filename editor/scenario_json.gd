class_name ScenarioJson
extends RefCounted
## Reads and writes scenario JSON in the hand-written style of scenarios/:
## tabs, keys in the document's own order, whole numbers as ints, and a
## dictionary or array on one line when it fits in WIDTH columns (tabs count
## as TAB_WIDTH), otherwise one entry per line. The top level is always
## one key per line, and top-level lists of entries (colonies, food, events...)
## one entry per line. parse(stringify(x)) == x.

const WIDTH := 140
const TAB_WIDTH := 4

## The parsed dictionary (key order kept), or {} with an error pushed.
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Scenario JSON error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("Scenario JSON is not an object")
		return {}
	return json.data

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Scenario %s not found" % path)
		return {}
	return parse(FileAccess.get_file_as_string(path))

static func save_file(path: String, data: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(stringify(data))
	f.close()
	return OK

static func stringify(data: Dictionary) -> String:
	return _multiline(data, 0) + "\n"

## `value` at nesting `depth`, where `used` columns of its line are already
## taken (indent, key and anything after it such as a comma).
static func _write(value: Variant, depth: int, used: int) -> String:
	# Top-level sections that are lists of entries get one entry per line.
	if depth == 1 and value is Array and value.any(func(v: Variant) -> bool: return v is Dictionary):
		return _multiline(value, depth)
	var one := inline(value)
	if not (value is Dictionary or value is Array) or used + one.length() <= WIDTH:
		return one
	return _multiline(value, depth)

static func _multiline(value: Variant, depth: int) -> String:
	var pad := "\t".repeat(depth + 1)
	var lines: PackedStringArray = []
	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var keys: Array = value.keys()
		for i: int in keys.size():
			var head := JSON.stringify(str(keys[i])) + ": "
			var comma := 1 if i < keys.size() - 1 else 0
			lines.append(pad + head + _write(value[keys[i]], depth + 1, (depth + 1) * TAB_WIDTH + head.length() + comma))
		return "{\n" + ",\n".join(lines) + "\n" + "\t".repeat(depth) + "}"
	if value.is_empty():
		return "[]"
	for i: int in value.size():
		var comma := 1 if i < value.size() - 1 else 0
		lines.append(pad + _write(value[i], depth + 1, (depth + 1) * TAB_WIDTH + comma))
	return "[\n" + ",\n".join(lines) + "\n" + "\t".repeat(depth) + "]"

## `value` on one line.
static func inline(value: Variant) -> String:
	if value is Dictionary:
		var parts: PackedStringArray = []
		for k: Variant in value:
			parts.append(JSON.stringify(str(k)) + ": " + inline(value[k]))
		return "{" + ", ".join(parts) + "}"
	if value is Array:
		var parts: PackedStringArray = []
		for v: Variant in value:
			parts.append(inline(v))
		return "[" + ", ".join(parts) + "]"
	if value is float:
		return number(value)
	return JSON.stringify(value)

## A number as JSON: whole numbers without a fraction, others in the shortest
## form that parses back to the same float.
static func number(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "0"
	if v == floorf(v) and absf(v) < 1e15:
		return str(int(v))
	for decimals: int in range(1, 18):
		var s := String.num(v, decimals)
		if s.to_float() == v:
			return s
	return String.num_scientific(v)
