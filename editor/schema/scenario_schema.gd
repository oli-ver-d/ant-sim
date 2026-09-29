class_name ScenarioSchema
extends RefCounted
## The whole scenario format as FieldSpecs: the core sections (CoreSchema,
## ScenerySchema, NestSchema, BehaviourSchema) plus what species register with
## Registry.register_schema(id, spec). Ids of registered schemas:
##   "food:<food type>"      a food entry's own keys (besides type/pos/rotation)
##   "nest:<nest type>"      a colony's nest_params for that nest type
##   "scenery:<prop type>"   a scenery prop's keys (core only so far)
## Core schemas use the same ids (in `core`); species ids must not clash with
## them (a clashing registered one is never used; tests check there are none).
##
## Editor metadata only (see FieldSpec): nothing in the simulation reads it.

var registry: Registry
## Core schemas by id (same ids as the registered ones).
var core: Dictionary[String, FieldSpec] = {}
var root: FieldSpec

func _init(reg: Registry) -> void:
	registry = reg
	CoreSchema.register(self)
	ScenerySchema.register(self)
	NestSchema.register(self)
	BehaviourSchema.register(self)
	root = CoreSchema.root(self)

func add(id: String, spec: FieldSpec) -> void:
	assert(not core.has(id), "Duplicate core schema %s" % id)
	core[id] = spec

## The schema registered as `id` (core first, then the Registry's), or null.
func schema_for(id: String) -> FieldSpec:
	if core.has(id):
		return core[id]
	return registry.schemas.get(id) as FieldSpec

## Every schema id starting with "<prefix>:", sorted.
func ids_with_prefix(prefix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in core.keys() + registry.schemas.keys():
		if id.begins_with(prefix + ":") and not out.has(id):
			out.append(id)
	out.sort()
	return out

## Choices for an enum or map keys from a named source. `context` is the
## enclosing dictionary (e.g. a colony, for its species' castes).
func choices_for(source: String, context: Dictionary = {}) -> PackedStringArray:
	var out: PackedStringArray = []
	match source:
		"species":
			out = PackedStringArray(registry.species.keys())
		"food_types":
			out = PackedStringArray(registry.food_source_types.keys())
		"nest_types":
			out = PackedStringArray(registry.nest_types.keys())
		"scenery_types":
			out = PackedStringArray(registry.scenery_types.keys())
		"item_types":
			out = PackedStringArray(registry.item_types.keys())
		"refuse_kinds":
			out = PackedStringArray(registry.refuse_kinds.keys())
		"states":
			out = PackedStringArray(registry.behaviours.keys())
		"castes", "channels":
			var def: SpeciesDef = registry.species.get(str(context.get("species", "")))
			if def != null:
				for x: Resource in (def.castes if source == "castes" else def.channels):
					out.append(str(x.get("id") if source == "castes" else x.get("name")))
		"params":
			out = params_spec(context).fields.keys()
	out.sort()
	return out

# --- walking ---------------------------------------------------------------

## The concrete spec for `value` held by `spec`: any_of picks the matching
## alternative, a variant becomes a dict of its tag plus that variant's
## fields, and a resolver picks from `parent`.
func resolve(spec: FieldSpec, value: Variant, parent: Variant = null) -> FieldSpec:
	if spec == null:
		return null
	if spec.resolver.is_valid() and parent is Dictionary:
		var picked: FieldSpec = spec.resolver.call(parent)
		if picked != null and picked != spec:
			return resolve(picked, value, parent)
	match spec.type:
		"any_of":
			for a in spec.alternatives:
				if a.matches(value):
					return resolve(a, value, parent)
			return null
		"variant":
			var tag_value := str(value.get(spec.tag, "")) if value is Dictionary else ""
			var v := variant_spec(spec, tag_value)
			var merged := FieldSpec.dict({spec.tag: FieldSpec.choice(variant_names(spec)).req()}, spec.help)
			if v != null:
				merged.fields.merge(v.fields)
			return merged
	return spec

## The spec of variant `tag_value` (its own or a registered one), or null.
func variant_spec(spec: FieldSpec, tag_value: String) -> FieldSpec:
	if spec.variants.has(tag_value):
		return spec.variants[tag_value]
	if spec.variants_from != "":
		return schema_for(spec.variants_from + ":" + tag_value)
	return null

func variant_names(spec: FieldSpec) -> PackedStringArray:
	var out := PackedStringArray(spec.variants.keys())
	if spec.variants_from != "":
		for id in ids_with_prefix(spec.variants_from):
			var n := id.substr(spec.variants_from.length() + 1)
			if not out.has(n):
				out.append(n)
	return out

## The spec of the child `key` (a String for dicts, an int for lists) of
## `value`, which has (unresolved) spec `spec`. Null if unknown.
func child_spec(spec: FieldSpec, value: Variant, key: Variant, parent: Variant = null) -> FieldSpec:
	var s := resolve(spec, value, parent)
	if s == null:
		return null
	match s.type:
		"dict":
			return s.fields.get(key)
		"map":
			return s.values
		"list":
			return s.item
		"points":
			return FieldSpec.vec2()
	return null

## The spec at `path` in `data` (the whole document), resolved for the value
## found there. Null if the path leaves the schema.
func spec_at(data: Dictionary, path: Array) -> FieldSpec:
	var spec := root
	var value: Variant = data
	var parent: Variant = null
	for key: Variant in path:
		var child := child_spec(spec, value, key, parent)
		if child == null:
			return null
		parent = value
		value = value[key] if _has(value, key) else null
		spec = child
	return resolve(spec, value, parent)

## Paths (as "a/0/b" strings) in `data` that the schema doesn't know.
func unknown_paths(data: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	_walk(root, data, null, "", out)
	return out

func _walk(spec: FieldSpec, value: Variant, parent: Variant, at: String, out: PackedStringArray) -> void:
	var s := resolve(spec, value, parent)
	if s == null:
		out.append(at + " (no matching alternative)")
		return
	match s.type:
		"dict", "map":
			if not value is Dictionary:
				return
			for k: Variant in value:
				var child: FieldSpec = s.values if s.type == "map" else s.fields.get(k)
				if child == null:
					out.append(at.path_join(str(k)))
				else:
					_walk(child, value[k], value, at.path_join(str(k)), out)
		"list":
			if value is Array:
				for i: int in value.size():
					_walk(s.item, value[i], value, at.path_join(str(i)), out)

## Every key name the schema knows (dict fields, including every variant and
## alternative, core and registered schemas). For the code coverage test.
func all_key_names() -> Dictionary:
	var names := {}
	var seen := {}
	_collect(root, names, seen)
	for id: String in core:
		_collect(core[id], names, seen)
	for id: String in registry.schemas:
		_collect(registry.schemas[id], names, seen)
	for k: String in params_spec({}).fields:
		names[k] = true
	return names

func _collect(spec: FieldSpec, names: Dictionary, seen: Dictionary) -> void:
	if spec == null or seen.has(spec):
		return
	seen[spec] = true
	if spec.tag != "":
		names[spec.tag] = true
	for k: String in spec.fields:
		names[k] = true
		_collect(spec.fields[k], names, seen)
	for v: FieldSpec in spec.variants.values():
		_collect(v, names, seen)
	for a in spec.alternatives:
		_collect(a, names, seen)
	_collect(spec.values, names, seen)
	_collect(spec.item, names, seen)

static func _has(value: Variant, key: Variant) -> bool:
	if value is Dictionary:
		return value.has(key)
	if value is Array:
		return key is int and key >= 0 and key < value.size()
	return false

# --- colony helpers (used by CoreSchema) -------------------------------------

## A colony's nest_params: the schema of its nest type ("nest_type", else its
## species' own), or any dictionary if that has none.
func nest_params_spec(colony: Dictionary) -> FieldSpec:
	var nest_type := str(colony.get("nest_type", ""))
	if nest_type == "":
		var def: SpeciesDef = registry.species.get(str(colony.get("species", "")))
		nest_type = def.nest_type if def != null else ""
	var spec := schema_for("nest:" + nest_type)
	return spec if spec != null else FieldSpec.map(FieldSpec.raw(), "", "Nest parameters")

## A colony's params: every SimConfig export plus its species' tunables, with
## their defaults (the species' value where it overrides the config's).
func params_spec(colony: Dictionary) -> FieldSpec:
	var fields := {}
	var config := SimConfig.new()
	var def: SpeciesDef = registry.species.get(str(colony.get("species", "")))
	for prop in config.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = config.get(prop["name"])
			if v is float or v is int or v is bool:
				fields[prop["name"]] = _scalar_spec(v)
	if def != null:
		for k: Variant in def.tunables:
			fields[str(k)] = _scalar_spec(def.tunables[k])
	return FieldSpec.dict(fields, "SimConfig values and species tunables for this colony")

static func _scalar_spec(v: Variant) -> FieldSpec:
	if v is bool:
		return FieldSpec.boolean(v)
	if v is int:
		return FieldSpec.integer(v)
	if v is float:
		return FieldSpec.number(v)
	return FieldSpec.raw()
