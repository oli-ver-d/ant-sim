class_name FieldValues
extends RefCounted
## Conversions between scenario JSON values and what the inspector's widgets
## show (numbers as text, colours, vectors), kept apart from the GUI so they
## can be tested headless.

## A number typed into a field: an int for "int" specs (floats rounded), a
## float otherwise, clamped to the spec's limits. Null if it isn't a number.
static func parse_number(text: String, spec: FieldSpec) -> Variant:
	text = text.strip_edges()
	if not text.is_valid_float():
		return null
	var v := clampf(text.to_float(), spec.min_value, spec.max_value)
	if spec.type == "int":
		return int(roundf(v))
	return v

## How a number is shown (whole numbers without ".0", as the JSON writer does).
static func format_number(v: Variant) -> String:
	if v is int:
		return str(v)
	if v is float:
		return ScenarioJson.number(v)
	return ""

## A colour value ("#rrggbb", a named colour, or [r, g, b(, a)] in 0-1).
static func to_color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is String:
		return Color.from_string(v, fallback)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return fallback

## `c` in the same form as `like` (an array stays an array, else "#rrggbb").
static func from_color(c: Color, like: Variant) -> Variant:
	if like is Array:
		var out: Array = [_round3(c.r), _round3(c.g), _round3(c.b)]
		if like.size() > 3 or c.a < 1.0:
			out.append(_round3(c.a))
		return out
	return "#" + c.to_html(c.a < 1.0)

static func _round3(x: float) -> float:
	return snappedf(x, 0.001)

## Components of a vec2 / size / rect value (missing ones 0).
static func components(v: Variant, count: int) -> Array:
	var out: Array = []
	for i: int in count:
		out.append(v[i] if v is Array and i < v.size() and (v[i] is float or v[i] is int) else 0)
	return out

## Whole floats as ints, so an edited [x, y] stays [540, 1500].
static func tidy(v: Variant) -> Variant:
	if v is float and v == roundf(v) and absf(v) < 1e15:
		return int(v)
	if v is Array:
		return v.map(tidy)
	return v

## The value as JSON text for a raw field.
static func to_json_text(v: Variant) -> String:
	if v is Dictionary:
		return ScenarioJson.stringify(v)
	return ScenarioJson.inline(v)

## Parses a raw field's text; returns [ok, value].
static func parse_json_text(text: String) -> Array:
	var json := JSON.new()
	if json.parse(text) != OK:
		return [false, null]
	return [true, tidy_deep(json.data)]

static func tidy_deep(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = tidy_deep(v[k])
		return out
	if v is Array:
		return v.map(tidy_deep)
	return tidy(v)
