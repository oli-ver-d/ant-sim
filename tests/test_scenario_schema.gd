extends TestCase
## M16a: the scenario schema covers every option: every key the shipped
## scenarios and the species' nest_params use, and every string key the code
## reads from dictionaries (except those in the ignore list, which are not
## scenario data).
##
## Ignore list: tests/fixtures/schema_ignored_keys.txt, one line per entry:
##     <res:// script path> <key | *>    # why it isn't scenario data
## "*" ignores every key of a script that reads no scenario data.

const IGNORE_FILE := "res://tests/fixtures/schema_ignored_keys.txt"

var _registry := Registry.create_default()
var _schema := ScenarioSchema.new(_registry)

## Keys passed as string literals to .get("k" / .has("k" / ["k"] in `path`.
static func code_keys(path: String) -> PackedStringArray:
	var re := RegEx.create_from_string("(?:\\.get|\\.has|\\.get_or_add)\\(\\s*\"([a-z_][a-z0-9_]*)\"|\\[\\s*\"([a-z_][a-z0-9_]*)\"\\s*\\]")
	var out: PackedStringArray = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m in re.search_all(line.split("#")[0] if not "\"#" in line else line):
			var k := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
			if not out.has(k):
				out.append(k)
	return out

static func scripts_in(dir: String, recursive: bool) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	if recursive:
		for d in DirAccess.get_directories_at(dir):
			out.append_array(scripts_in(dir.path_join(d), true))
	return out

## {path: {key or "*": true}}
static func ignored() -> Dictionary:
	var out := {}
	for line in FileAccess.get_file_as_string(IGNORE_FILE).split("\n"):
		var entry := line.split("#")[0].strip_edges()
		if entry == "":
			continue
		var parts := entry.split(" ", false)
		if parts.size() < 2:
			continue
		if not out.has(parts[0]):
			out[parts[0]] = {}
		for k in parts.slice(1):
			out[parts[0]][k] = true
	return out

func _check_code(scripts: PackedStringArray) -> void:
	var known := _schema.all_key_names()
	var skip := ignored()
	var missing: PackedStringArray = []
	for path in scripts:
		var skip_here: Dictionary = skip.get(path, {})
		if skip_here.has("*"):
			continue
		for k in code_keys(path):
			if not known.has(k) and not skip_here.has(k):
				missing.append("%s %s" % [path, k])
	check(missing.is_empty(), "keys read in code but not in the schema or the ignore list:\n  " + "\n  ".join(missing))

func test_code_keys_sim() -> void:
	_check_code(scripts_in("res://sim", false) + scripts_in("res://sim/food", true) + scripts_in("res://sim/items", true))

func test_code_keys_nests() -> void:
	_check_code(scripts_in("res://sim/nests", true))

func test_code_keys_scenery() -> void:
	_check_code(scripts_in("res://sim/scenery", true))

func test_code_keys_behaviours() -> void:
	_check_code(scripts_in("res://sim/behaviours", true))

func test_code_keys_species() -> void:
	_check_code(scripts_in("res://species", true))

func test_code_keys_render() -> void:
	_check_code(scripts_in("res://render", true))

func test_code_keys_scenario_player() -> void:
	_check_code(PackedStringArray(["res://scenes/scenario_player.gd"]))

## Every ignore entry names a script that exists and a key it still reads.
func test_ignore_list_is_current() -> void:
	var skip := ignored()
	for path: String in skip:
		if not FileAccess.file_exists(path):
			check(false, "ignore list names a missing script %s" % path)
			continue
		var keys := code_keys(path)
		for k: String in skip[path]:
			check(k == "*" or keys.has(k), "ignore list: %s no longer reads '%s'" % [path, k])

func test_shipped_scenarios_in_schema() -> void:
	for f in DirAccess.get_files_at("res://scenarios"):
		if f.ends_with(".json"):
			var unknown := _schema.unknown_paths(ScenarioLoader.load_data("res://scenarios".path_join(f)))
			check(unknown.is_empty(), "%s: not in the schema: %s" % [f, ", ".join(unknown)])

## The species' own nest_params, state_params and tunables fit the schema.
func test_species_defaults_in_schema() -> void:
	for id: String in _registry.species:
		var def: SpeciesDef = _registry.species[id]
		var colony := {"species": id, "nest": [0, 0], "nest_params": def.nest_params,
				"state_params": def.state_params}
		var unknown := _schema.unknown_paths({"colonies": [colony]})
		check(unknown.is_empty(), "%s defaults: not in the schema: %s" % [id, ", ".join(unknown)])

func test_every_nest_type_has_a_schema() -> void:
	for id: String in _registry.nest_types:
		check(_schema.schema_for("nest:" + id) != null, "no schema for nest type %s" % id)

func test_every_food_type_has_a_schema() -> void:
	for id: String in _registry.food_source_types:
		check(_schema.schema_for("food:" + id) != null, "no schema for food type %s" % id)

func test_every_scenery_type_has_a_schema() -> void:
	for id: String in _registry.scenery_types:
		check(_schema.schema_for("scenery:" + id) != null, "no schema for scenery type %s" % id)

func test_registered_schemas_dont_clash_with_core() -> void:
	for id: String in _registry.schemas:
		check(not _schema.core.has(id), "registered schema %s clashes with a core one" % id)
		check(_registry.schemas[id] is FieldSpec, "registered schema %s is not a FieldSpec" % id)

func test_spec_at_resolves_variants_and_colonies() -> void:
	var data := ScenarioLoader.load_data("basic_forage")
	check_eq(_schema.spec_at(data, ["food", 0, "radius"]).type, "float", "food_pile radius")
	check_eq(_schema.spec_at(data, ["colonies", 0, "species"]).type, "enum", "colony species")
	check_eq(_schema.spec_at(data, ["colonies", 0, "params", "sensor_distance"]).type, "float", "SimConfig param")
	check(_schema.spec_at(data, ["no_such_key"]) == null, "unknown key has no spec")
	check(_schema.choices_for("castes", data["colonies"][0]).has("major"), "castes of the colony's species")
