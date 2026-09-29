class_name FieldSpec
extends RefCounted
## Editor metadata for one scenario option: its type, default, range, choices
## and help text, and for containers the specs of what they hold.
##
## This is editor metadata only: the simulation keeps reading scenario data with
## dict.get(key, default), so nothing here changes a run. Specs are built with
## the static constructors and chained setters, e.g.
##     FieldSpec.number(28.0, "Pile radius (world units)").limits(1, 500)
##     FieldSpec.dict({"pos": FieldSpec.vec2().req(), "radius": ...})
##
## Types:
##   int, float, bool, string, enum   scalars (enum: `choices`, or `choices_from`
##                                    a Registry list, see ScenarioSchema.choices_for)
##   vec2 [x, y], size [w, h], rect [x, y, w, h], points [[x, y], ...], color
##   dict     fixed keys (`fields`, in their preferred order)
##   map      any keys (`keys_from` names where they come from), values of `values`
##   list     items of `item`
##   variant  a dict whose `tag` key picks one of `variants` (e.g. "type", "shape");
##            `variants_from` also takes every Registry schema "<prefix>:<tag value>"
##   any_of   one of `alternatives`, picked by the value's JSON type (see matches())
##   raw      any JSON, edited as text
## A `resolver` (Callable(parent: Dictionary) -> FieldSpec) picks a spec from
## the enclosing dictionary, e.g. a colony's nest_params from its species.

const NO_LIMIT := INF

var type: String = "raw"
var default: Variant = null
var required: bool = false
var help: String = ""
var min_value: float = -NO_LIMIT
var max_value: float = NO_LIMIT
var choices: PackedStringArray = []
var choices_from: String = ""
var fields: Dictionary = {}
var values: FieldSpec = null
var keys_from: String = ""
var item: FieldSpec = null
var tag: String = ""
var variants: Dictionary = {}
var variants_from: String = ""
var alternatives: Array[FieldSpec] = []
var resolver: Callable

func _init(type_name: String = "raw", default_value: Variant = null, help_text: String = "") -> void:
	type = type_name
	default = default_value
	help = help_text

# --- constructors ----------------------------------------------------------

static func integer(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("int", default_value, help_text)

static func number(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("float", default_value, help_text)

static func boolean(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("bool", default_value, help_text)

static func text(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("string", default_value, help_text)

## An enum with fixed choices; use from_registry() for Registry-filled ones.
static func choice(options: Array, default_value: Variant = null, help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("enum", default_value, help_text)
	s.choices = PackedStringArray(options)
	return s

static func vec2(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("vec2", default_value, help_text)

static func size(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("size", default_value, help_text)

static func rect(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("rect", default_value, help_text)

static func points(help_text: String = "") -> FieldSpec:
	return FieldSpec.new("points", null, help_text)

## A colour as a string ("#rrggbb", a named colour) or [r, g, b(, a)].
static func color(default_value: Variant = null, help_text: String = "") -> FieldSpec:
	return FieldSpec.new("color", default_value, help_text)

static func dict(field_specs: Dictionary, help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("dict", null, help_text)
	s.fields = field_specs
	return s

## A dictionary with free keys (e.g. castes -> counts), each value a `value_spec`.
static func map(value_spec: FieldSpec, key_source: String = "", help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("map", null, help_text)
	s.values = value_spec
	s.keys_from = key_source
	return s

static func list(item_spec: FieldSpec, help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("list", null, help_text)
	s.item = item_spec
	return s

## A dict whose `tag_key` value picks the variant (each a dict spec). The tag
## itself need not be listed in the variants' fields.
static func variant(tag_key: String, variant_specs: Dictionary, help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("variant", null, help_text)
	s.tag = tag_key
	s.variants = variant_specs
	return s

static func any_of(options: Array, help_text: String = "") -> FieldSpec:
	var s := FieldSpec.new("any_of", null, help_text)
	for o: FieldSpec in options:
		s.alternatives.append(o)
	return s

static func raw(help_text: String = "") -> FieldSpec:
	return FieldSpec.new("raw", null, help_text)

## A spec chosen from the enclosing dictionary when the data is known;
## `fallback` is used without data (and for listing keys).
static func resolved(pick: Callable, fallback: FieldSpec) -> FieldSpec:
	var s := fallback
	s.resolver = pick
	return s

# --- chained setters -------------------------------------------------------

func req() -> FieldSpec:
	required = true
	return self

func limits(lo: float, hi: float = NO_LIMIT) -> FieldSpec:
	min_value = lo
	max_value = hi
	return self

func describe(help_text: String) -> FieldSpec:
	help = help_text
	return self

## Enum choices (or map keys) from a Registry list, see ScenarioSchema.choices_for.
func from_registry(source: String) -> FieldSpec:
	choices_from = source
	return self

## Variants also from every Registry schema "<prefix>:<id>".
func with_registry_variants(prefix: String) -> FieldSpec:
	variants_from = prefix
	return self

# --- queries ---------------------------------------------------------------

func is_container() -> bool:
	return type in ["dict", "map", "list", "variant", "any_of"]

## Whether `value` has the JSON shape of this spec (used to pick an any_of
## alternative). Dicts must have every required field; variants their tag.
func matches(value: Variant) -> bool:
	match type:
		"int", "float":
			return value is float or value is int
		"bool":
			return value is bool
		"string", "enum":
			return value is String
		"color":
			return value is String or value is Array
		"vec2", "size", "rect", "points", "list":
			return value is Array
		"dict":
			if not value is Dictionary:
				return false
			for k: String in fields:
				if (fields[k] as FieldSpec).required and not value.has(k):
					return false
			return true
		"variant":
			return value is Dictionary and value.has(tag)
		"map":
			return value is Dictionary
		"any_of":
			for a in alternatives:
				if a.matches(value):
					return true
			return false
	return true
