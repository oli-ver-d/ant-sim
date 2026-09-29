class_name EditorDefaults
extends RefCounted
## Values the scenario editor's inspector puts into the document: a default for
## any FieldSpec, the value of a variant switched to another tag, the "Add ..."
## actions of an outline row with the new item each one appends, and full example
## values used by tests to reach every key of the schema. GUI-free.

const MAX_DEPTH := 12

## Outline sections in order: key, then the actions {label, id, list} they offer.
const SECTION_ACTIONS: Array[Array] = [
	["colonies", [["Add colony", "colony", ["colonies"]]]],
	["food", [["Add food", "food", ["food"]]]],
	["obstacles", [["Add obstacle", "obstacle", ["obstacles"]]]],
	["ground", [["Add ground region", "ground_region", ["ground", "regions"]]]],
	["scenery", [["Add prop", "prop", ["scenery"]], ["Add scatter", "scatter", ["scenery"]]]],
	["debris", [["Add debris", "debris", ["debris"]]]],
	["events", [["Add event", "event", ["events"]]]],
	["camera", []],
	["render", [["Add caption", "caption", ["render", "captions"]]]],
]

# --- defaults ----------------------------------------------------------------------

## A sensible value to add for `spec` (a list item, or an absent field). `context`
## is the enclosing dictionary, for choices and resolvers.
static func value_for(spec: FieldSpec, schema: ScenarioSchema, context: Dictionary = {}) -> Variant:
	return _value(spec, schema, context, 0, false, 0)

## The value of the variant dict `spec` switched to `tag_value`: the tag, then the
## variant's required fields, keeping the values `old` had for keys they share.
static func variant_value(spec: FieldSpec, schema: ScenarioSchema, tag_value: String, old: Variant = null) -> Dictionary:
	var out := {spec.tag: tag_value}
	var v := schema.variant_spec(spec, tag_value)
	if v != null:
		for key: String in v.fields:
			var fs: FieldSpec = v.fields[key]
			if fs.required:
				out[key] = _value(fs, schema, out, 0, false, 0)
		if old is Dictionary:
			for key: String in v.fields:
				if old.has(key):
					out[key] = old[key]
	return out

## A full example of `spec`: every field of every dict filled, one entry per
## list/map, variants and alternatives and enum choices picked by `k`.
static func example(spec: FieldSpec, schema: ScenarioSchema, k: int, context: Dictionary = {}, depth: int = 0) -> Variant:
	return _value(spec, schema, context, depth, true, k)

static func _zero(type: String) -> Variant:
	match type:
		"int":
			return 0
		"float":
			return 0.0
		"bool":
			return false
	return ""

static func _value(spec: FieldSpec, schema: ScenarioSchema, context: Dictionary, depth: int, full: bool, k: int) -> Variant:
	if spec.resolver.is_valid():
		spec = schema.resolve(spec, null, context)
	if full and depth > MAX_DEPTH:
		return _value(spec, schema, context, depth, false, k)
	match spec.type:
		"int", "float", "bool", "string", "vec2", "size", "rect", "color", "points", "enum":
			return _scalar(spec, schema, context, full, k)
		"dict":
			var out := {}
			for key: String in spec.fields:
				var fs: FieldSpec = spec.fields[key]
				if full or fs.required:
					out[key] = _value(fs, schema, out, depth + 1, full, k)
			return out
		"map":
			if not full:
				return {}
			var keys := schema.choices_for(spec.keys_from, context) if spec.keys_from != "" else PackedStringArray()
			var key: String = keys[0] if not keys.is_empty() else "key"
			return {key: _value(spec.values, schema, context, depth + 1, full, k)}
		"list":
			if not full:
				return []
			return _example_list(spec, schema, context, depth, k)
		"variant":
			var names := schema.variant_names(spec)
			if names.is_empty():
				return {spec.tag: ""}
			return _variant(spec, schema, names[k % names.size()] if full else names[0], depth, full, k)
		"any_of":
			if spec.alternatives.is_empty():
				return {}
			var alt: FieldSpec = spec.alternatives[k % spec.alternatives.size()] if full else spec.alternatives[0]
			return _value(alt, schema, context, depth + 1, full, k)
	return {}

static func _scalar(spec: FieldSpec, schema: ScenarioSchema, context: Dictionary, full: bool, k: int) -> Variant:
	if spec.type == "enum":
		var choices := spec.choices
		if spec.choices_from != "":
			choices = schema.choices_for(spec.choices_from, context)
		if full and not choices.is_empty():
			return choices[k % choices.size()]
		if spec.default != null:
			return spec.default
		return choices[0] if not choices.is_empty() else ""
	if spec.default != null:
		return spec.default.duplicate(true) if spec.default is Array else spec.default
	match spec.type:
		"vec2":
			return [0, 0]
		"size":
			return [100, 100]
		"rect":
			return [0, 0, 100, 100]
		"points":
			return [[0, 0], [100, 0]]
		"color":
			return "#ffffff"
		"int":
			return int(maxf(0.0, spec.min_value)) if is_finite(spec.min_value) else 0
		"float":
			return maxf(0.0, spec.min_value) if is_finite(spec.min_value) else 0.0
	return _zero(spec.type)

## A variant dict of `tag_value` with the required fields, or all of them if `full`.
static func _variant(spec: FieldSpec, schema: ScenarioSchema, tag_value: String, depth: int, full: bool, k: int) -> Dictionary:
	var out := {spec.tag: tag_value}
	var v := schema.variant_spec(spec, tag_value)
	if v != null:
		for key: String in v.fields:
			var fs: FieldSpec = v.fields[key]
			if full or fs.required:
				out[key] = _value(fs, schema, out, depth + 1, full, k)
	return out

static func _example_list(spec: FieldSpec, schema: ScenarioSchema, context: Dictionary, depth: int, k: int) -> Array:
	var out: Array = []
	var item := spec.item
	if item.type == "variant":
		for name: String in schema.variant_names(item):
			out.append(_variant(item, schema, name, depth + 1, true, k))
		if out.is_empty():
			out.append(_value(item, schema, context, depth + 1, true, k))
	elif item.type == "any_of":
		for i: int in item.alternatives.size():
			out.append(_value(item.alternatives[i], schema, context, depth + 1, true, k + i))
	else:
		out.append(_value(item, schema, context, depth + 1, true, k))
	return out

# --- add actions -------------------------------------------------------------------

## The "Add ..." actions {label, id, list} of the outline row at `path`: the
## section's own (any item under it included), all sections' on the Scenario row.
static func add_actions(data: Dictionary, path: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: Array in SECTION_ACTIONS:
		if not path.is_empty() and path[0] != section[0]:
			continue
		if section[0] == "camera":
			if data.get("camera") is Dictionary:
				out.append({"label": "Add camera key", "id": "camera_key", "list": ["camera", "surface"]})
				out.append({"label": "Add nest camera key", "id": "nest_camera_key", "list": ["camera", "nest"]})
			else:
				out.append({"label": "Add camera key", "id": "camera_key", "list": ["camera"]})
			continue
		for a: Array in section[1]:
			out.append({"label": a[0], "id": a[1], "list": (a[2] as Array).duplicate()})
	return out

# --- new items ---------------------------------------------------------------------

static func _pt(at: Vector2) -> Array:
	return [roundi(at.x), roundi(at.y)]

static func _list_at(data: Dictionary, list: Array) -> Array:
	var v: Variant = data
	for key: Variant in list:
		v = v.get(key) if v is Dictionary else null
	return v if v is Array else []

static func _next_t(items: Array, key: String, gap: float) -> Variant:
	var best := -1.0
	for it: Variant in items:
		if it is Dictionary:
			var v: Variant = it.get(key)
			if v is float or v is int:
				best = maxf(best, float(v))
	return 0 if best < 0.0 else _clean(best + gap)

static func _clean(v: float) -> Variant:
	return int(v) if is_equal_approx(v, roundf(v)) else v

## The new item for the action `id` of add_actions, placed at world point `at`.
## Null for an unknown id.
static func new_item(id: String, data: Dictionary, schema: ScenarioSchema, at: Vector2) -> Variant:
	var x := roundi(at.x)
	var y := roundi(at.y)
	match id:
		"colony":
			var species := schema.choices_for("species")
			return {"species": species[0] if not species.is_empty() else "", "nest": [x, y]}
		"food":
			return {"type": "food_pile", "pos": [x, y], "radius": 24, "amount": 200}
		"obstacle":
			return {"shape": "rect", "kind": "wall", "rect": [x - 60, y - 10, 120, 20]}
		"ground_region":
			return {"material": "moss", "shape": "circle", "center": [x, y], "radius": 150}
		"prop":
			return {"type": "rock", "center": [x, y], "radius": 40}
		"scatter":
			return {"scatter": {"preset": "meadow", "rect": [x - 200, y - 200, 400, 400]}}
		"debris":
			return {"type": "twig", "pos": [x, y], "length": 32}
		"event":
			return {"type": "rain", "t": 0, "duration": 5, "area": {"center": [x, y], "radius": 150}}
		"camera_key", "nest_camera_key":
			var cam: Variant = data.get("camera")
			var keys: Array = []
			if cam is Array:
				keys = cam
			elif cam is Dictionary:
				keys = cam.get("nest" if id == "nest_camera_key" else "surface", []) as Array
			return {"t": _next_t(keys, "t", 2.0), "pos": [x, y], "zoom": 1}
		"caption":
			var caps := _list_at(data, ["render", "captions"])
			var t: Variant = 0
			if not caps.is_empty() and caps[-1] is Dictionary:
				var last: Dictionary = caps[-1]
				var until: Variant = last.get("until")
				var start: Variant = last.get("t")
				if until is float or until is int:
					t = until
				elif start is float or start is int:
					t = _clean(float(start) + 4.0)
			return {"t": t, "text": "Caption"}
	return null
