class_name ScenarioValidator
extends RefCounted
## M16i: checks a scenario document and lists what is wrong with it. Two kinds of
## checks: schema checks (here: types, ranges, required keys, enum values the
## Registry doesn't know, the output frame size) and scene checks (SceneChecks:
## positions outside the world or in walls, times after the end of the run,
## overlapping colonies, captions in the unsafe margins).
##
## An issue is {"path": Array, "severity": ERROR | WARNING, "message": String};
## `path` is the document path of the item or key (as ScenarioDoc paths). The
## editor lists them and marks the items; saving, running and recording with
## errors warn but are allowed. Nothing here changes the document.

const ERROR := "error"
const WARNING := "warning"

## Every issue of `data`: schema checks, then scene checks (`sim`, the
## Simulation built from `data`, is needed for the checks against walls and
## the world size; without it those are skipped).
static func validate(data: Dictionary, schema: ScenarioSchema, sim: Simulation = null) -> Array[Dictionary]:
	var out := schema_issues(data, schema)
	out.append_array(SceneChecks.issues(data, schema.registry, sim))
	return out

static func issue(path: Array, severity: String, message: String) -> Dictionary:
	return {"path": path, "severity": severity, "message": message}

static func count(issues: Array[Dictionary], severity: String) -> int:
	var n := 0
	for i: Dictionary in issues:
		if i["severity"] == severity:
			n += 1
	return n

## The issues at `path` or inside it.
static func under(issues: Array[Dictionary], path: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: Dictionary in issues:
		var p: Array = i["path"]
		if p.size() >= path.size() and p.slice(0, path.size()) == path:
			out.append(i)
	return out

## "2 errors, 1 warning" ("" if there are none).
static func summary(issues: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for sev: String in [ERROR, WARNING]:
		var n := count(issues, sev)
		if n > 0:
			parts.append("%d %s%s" % [n, sev, "" if n == 1 else "s"])
	return ", ".join(parts)

## One line per issue: "error  colonies/0/species: ..." (for the CLI and logs).
static func format(i: Dictionary) -> String:
	var p: PackedStringArray = []
	for k: Variant in i["path"]:
		p.append(str(k))
	return "%-8s %s: %s" % [i["severity"], "/".join(p) if not p.is_empty() else "(scenario)", i["message"]]

# --- schema checks --------------------------------------------------------------

## Issues found by walking `data` with the schema.
static func schema_issues(data: Dictionary, schema: ScenarioSchema) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_check(schema, schema.root, data, null, [], out)
	_check_output(data, out)
	return out

static func _check(schema: ScenarioSchema, spec: FieldSpec, value: Variant, parent: Variant, path: Array,
		out: Array[Dictionary]) -> void:
	if spec == null:
		return
	if spec.type == "any_of":
		var picked := schema.resolve(spec, value, parent)
		if picked == null:
			out.append(issue(path, ERROR, "%s is none of the allowed forms (%s)" % [_short(value), _kinds(spec)]))
			return
	if spec.type == "variant" and value is Dictionary:
		var tag_value: Variant = (value as Dictionary).get(spec.tag)
		if tag_value == null:
			out.append(issue(path, ERROR, "Missing \"%s\"" % spec.tag))
			return
		var names := schema.variant_names(spec)
		if not names.has(str(tag_value)):
			out.append(issue(path + [spec.tag], ERROR, "Unknown %s \"%s\" (one of %s)" % [spec.tag, tag_value, ", ".join(names)]))
			return
	var s := schema.resolve(spec, value, parent)
	if s == null:
		return
	match s.type:
		"dict":
			if not value is Dictionary:
				out.append(issue(path, ERROR, "Expected an object, got %s" % _short(value)))
				return
			var d: Dictionary = value
			for k: String in s.fields:
				if (s.fields[k] as FieldSpec).required and not d.has(k):
					out.append(issue(path, ERROR, "Missing \"%s\"" % k))
			for k: Variant in d:
				var child: FieldSpec = s.fields.get(k)
				if child != null:
					_check(schema, child, d[k], d, path + [k], out)
				elif s.fields.is_empty():
					pass
				else:
					out.append(issue(path + [k], WARNING, "Unknown key \"%s\" (kept as it is)" % k))
		"map":
			if not value is Dictionary:
				out.append(issue(path, ERROR, "Expected an object, got %s" % _short(value)))
				return
			var keys: PackedStringArray = []
			if s.keys_from != "" and parent is Dictionary:
				keys = schema.choices_for(s.keys_from, parent)
			for k: Variant in value:
				if not keys.is_empty() and not keys.has(str(k)):
					out.append(issue(path + [k], ERROR, "Unknown key \"%s\" (one of %s)" % [k, ", ".join(keys)]))
				_check(schema, s.values, value[k], value, path + [k], out)
		"list":
			if not value is Array:
				out.append(issue(path, ERROR, "Expected a list, got %s" % _short(value)))
				return
			for i: int in (value as Array).size():
				_check(schema, s.item, value[i], value, path + [i], out)
		_:
			var msg := _scalar_problem(schema, s, value, parent)
			if msg != "":
				out.append(issue(path, ERROR, msg))

## What is wrong with a scalar (or fixed-size array) value, or "".
static func _scalar_problem(schema: ScenarioSchema, s: FieldSpec, value: Variant, parent: Variant) -> String:
	match s.type:
		"int", "float":
			if not _is_num(value):
				return "Expected a number, got %s" % _short(value)
			if s.type == "int" and float(value) != floorf(float(value)):
				return "Expected a whole number, got %s" % value
			if float(value) < s.min_value or float(value) > s.max_value:
				return "%s is out of range (%s)" % [_short(value), _range(s)]
		"bool":
			if not value is bool:
				return "Expected true or false, got %s" % _short(value)
		"string":
			if not value is String:
				return "Expected text, got %s" % _short(value)
		"enum":
			if not value is String:
				return "Expected one of the choices, got %s" % _short(value)
			var choices := s.choices
			if s.choices_from != "":
				choices = schema.choices_for(s.choices_from, parent if parent is Dictionary else {})
			if not choices.is_empty() and not choices.has(value):
				return "Unknown value \"%s\" (one of %s)" % [value, ", ".join(choices)]
		"vec2", "size":
			if not _nums(value, 2):
				return "Expected [x, y], got %s" % _short(value)
			if s.type == "size" and (float(value[0]) < 0.0 or float(value[1]) < 0.0):
				return "Sizes can't be negative (%s)" % _short(value)
		"rect":
			if not _nums(value, 4):
				return "Expected [x, y, width, height], got %s" % _short(value)
		"points":
			if not value is Array:
				return "Expected a list of [x, y] points, got %s" % _short(value)
			for p: Variant in value:
				if not _nums(p, 2):
					return "Point %s is not [x, y]" % _short(p)
		"color":
			if value is String:
				if not Color.html_is_valid(value) and Color.from_string(value, Color(0, 0, 0, 0.5)) == Color(0, 0, 0, 0.5):
					return "\"%s\" is not a colour" % value
			elif not (value is Array and ((value as Array).size() == 3 or (value as Array).size() == 4)
					and _nums(value, (value as Array).size())):
				return "Expected a colour (\"#rrggbb\", a name or [r, g, b(, a)]), got %s" % _short(value)
	return ""

## output.size: even sides within OutputFrame's limits.
static func _check_output(data: Dictionary, out: Array[Dictionary]) -> void:
	var output: Variant = data.get("output")
	if not output is Dictionary or not (output as Dictionary).has("size"):
		return
	var s: Variant = output["size"]
	if not _nums(s, 2):
		return
	var size := Vector2i(int(s[0]), int(s[1]))
	if float(s[0]) != float(size.x) or float(s[1]) != float(size.y) or not OutputFrame.valid_size(size):
		out.append(issue(["output", "size"], ERROR, "%s is not a valid frame size (even sides, %d-%d px)"
				% [_short(s), OutputFrame.MIN_SIDE, OutputFrame.MAX_SIDE]))

# --- helpers ----------------------------------------------------------------------

static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and not (v is float and (is_nan(v) or is_inf(v)))

static func _nums(v: Variant, n: int) -> bool:
	if not v is Array or (v as Array).size() != n:
		return false
	for x: Variant in v:
		if not _is_num(x):
			return false
	return true

static func _range(s: FieldSpec) -> String:
	if s.max_value == FieldSpec.NO_LIMIT:
		return "at least %s" % FieldValues.format_number(s.min_value)
	if s.min_value == -FieldSpec.NO_LIMIT:
		return "at most %s" % FieldValues.format_number(s.max_value)
	return "%s to %s" % [FieldValues.format_number(s.min_value), FieldValues.format_number(s.max_value)]

static func _kinds(spec: FieldSpec) -> String:
	var out: PackedStringArray = []
	for a in spec.alternatives:
		if not out.has(a.type):
			out.append(a.type)
	return ", ".join(out)

## A value shortened for a message.
static func _short(v: Variant) -> String:
	if v == null:
		return "null"
	if v is float or v is int:
		return FieldValues.format_number(v)
	var text := ScenarioJson.inline(FieldValues.tidy_deep(v))
	return text if text.length() <= 40 else text.substr(0, 37) + "..."
