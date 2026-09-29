extends TestCase
## M16a: the editor's document model (ScenarioDoc) and JSON writer
## (ScenarioJson): shipped scenarios survive parse -> stringify -> parse
## unchanged (same data, same text, same run), and every command undoes and
## redoes exactly. Schema coverage is in test_scenario_schema.gd.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

## Parse -> stringify -> parse gives the same data and the file's own text,
## and builds a run with the same state hash after a few ticks.
func _round_trip(scenario: String) -> void:
	var path := ScenarioLoader.path_for(scenario)
	var text := FileAccess.get_file_as_string(path)
	var data := ScenarioJson.parse(text)
	check(not data.is_empty(), "%s parses" % scenario)
	var saved := ScenarioJson.stringify(data)
	var again := ScenarioJson.parse(saved)
	check(again == data, "%s: data changed by a round trip" % scenario)
	check_eq(ScenarioJson.stringify(again), saved, "%s: stringify is stable" % scenario)
	check(saved == text, "%s: re-saving changes the file (reformat it with ScenarioJson)" % scenario)
	# Same run as the loader's own parse.
	var a := ScenarioLoader.build(ScenarioLoader.load_data(scenario), _registry, _config)
	var b := ScenarioLoader.build(again, _registry, _config)
	for t in 20:
		a.step()
		b.step()
	check_eq(b.state_hash(), a.state_hash(), "%s: state hash after a round trip" % scenario)

func test_round_trip_basic_forage() -> void:
	_round_trip("basic_forage")

func test_round_trip_chaos_to_highway() -> void:
	_round_trip("chaos_to_highway")

func test_round_trip_colony_founding() -> void:
	_round_trip("colony_founding")

func test_round_trip_fungus_farm() -> void:
	_round_trip("fungus_farm")

func test_round_trip_harvester_founding() -> void:
	_round_trip("harvester_founding")

func test_round_trip_leaf_strip() -> void:
	_round_trip("leaf_strip")

func test_round_trip_leafcutter_life() -> void:
	_round_trip("leafcutter_life")

func test_round_trip_maze() -> void:
	_round_trip("maze")

func test_round_trip_meadow_forage() -> void:
	_round_trip("meadow_forage")

func test_round_trip_nuptial_flight() -> void:
	_round_trip("nuptial_flight")

func test_round_trip_queen_landing() -> void:
	_round_trip("queen_landing")

func test_round_trip_rain_reset() -> void:
	_round_trip("rain_reset")

func test_round_trip_trunk_trail() -> void:
	_round_trip("trunk_trail")

func test_round_trip_twig_bridge() -> void:
	_round_trip("twig_bridge")

func test_round_trip_two_species() -> void:
	_round_trip("two_species")

## Every shipped scenario has a round-trip test above.
func test_every_scenario_has_a_round_trip_test() -> void:
	for f in DirAccess.get_files_at(ScenarioLoader.SCENARIO_DIR):
		if f.ends_with(".json"):
			check(has_method("test_round_trip_" + f.get_basename()), "no round-trip test for %s" % f)

func test_writer_style() -> void:
	var data := {"name": "x", "seed": 3.0, "zoom": 0.35, "neg": -2.5, "big": 123456789.0,
			"pos": [540.0, 1500.0], "empty": {}, "none": [], "ok": true, "q": "a \"b\"",
			"long": {"a": "0123456789".repeat(5), "b": "0123456789".repeat(5), "c": "0123456789".repeat(5)}}
	var s := ScenarioJson.stringify(data)
	check(s.begins_with("{\n\t\"name\": \"x\",\n\t\"seed\": 3,\n\t\"zoom\": 0.35,\n"), "whole numbers as ints, tabs: " + s)
	check(s.contains("\t\"pos\": [540, 1500],\n"), "short array on one line")
	check(s.contains("\t\"empty\": {},\n\t\"none\": [],\n"), "empty containers")
	check(s.contains("\t\"long\": {\n\t\t\"a\": "), "too long for a line: one entry per line")
	check(s.contains("\"big\": 123456789,"), "large whole number")
	check_eq(ScenarioJson.parse(s), data, "parses back")
	check_eq(ScenarioJson.number(0.1), "0.1")
	check_eq(ScenarioJson.number(1.0 / 3.0).to_float(), 1.0 / 3.0, "full precision")

func test_parse_keeps_key_order() -> void:
	var data := ScenarioJson.parse("{\"z\": 1, \"a\": {\"y\": 2, \"b\": 3}}")
	check_eq(data.keys(), ["z", "a"])
	check_eq(data["a"].keys(), ["y", "b"])

# --- commands ------------------------------------------------------------------

func _doc() -> ScenarioDoc:
	return ScenarioDoc.new(ScenarioLoader.load_data("basic_forage"), ScenarioSchema.new(_registry))

## Undo restores the exact text (so also key order), redo the edited text.
func _check_undo_redo(doc: ScenarioDoc, before: String, what: String) -> void:
	var after := ScenarioJson.stringify(doc.data)
	check(after != before, "%s changed the data" % what)
	check(doc.is_dirty(), "%s makes the doc dirty" % what)
	check(doc.undo(), "%s undoes" % what)
	check_eq(ScenarioJson.stringify(doc.data), before, "%s undone" % what)
	check(not doc.is_dirty(), "%s undone: clean again" % what)
	check(doc.redo(), "%s redoes" % what)
	check_eq(ScenarioJson.stringify(doc.data), after, "%s redone" % what)

func test_set_existing_value() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.set_at(["food", 1, "amount"], 99)
	check_eq(doc.get_at(["food", 1, "amount"]), 99)
	_check_undo_redo(doc, before, "set")

func test_set_new_key_goes_where_the_schema_orders_it() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	# "warmup" comes right after "duration" in the schema.
	doc.set_at(["warmup"], 5)
	check_eq(doc.data.keys().slice(0, 5), ["name", "description", "seed", "duration", "warmup"])
	_check_undo_redo(doc, before, "add key")

func test_set_creates_missing_dictionaries() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.set_at(["colonies", 0, "nest_params", "brood", "egg"], 20)
	check_eq(doc.get_at(["colonies", 0, "nest_params"]), {"brood": {"egg": 20}})
	_check_undo_redo(doc, before, "nested add")
	check(doc.undo(), "undo again")
	check(not doc.has_at(["colonies", 0, "nest_params"]), "nest_params removed again")

func test_unknown_keys_are_kept() -> void:
	var doc := _doc()
	doc.set_at(["my_note"], "kept")
	doc.set_at(["food", 0, "amount"], 1)
	check_eq(doc.data["my_note"], "kept")
	check(ScenarioJson.stringify(doc.data).contains("\"my_note\": \"kept\""), "unknown key saved")

func test_remove_key_restores_position() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.remove_at(["seed"])
	check(not doc.data.has("seed"), "removed")
	_check_undo_redo(doc, before, "remove key")

func test_remove_list_item() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.remove_at(["food", 0])
	check_eq(doc.get_at(["food"]).size(), 1)
	_check_undo_redo(doc, before, "remove item")

func test_insert_item() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.insert_at(["food", 1], {"type": "food_pile", "pos": [1, 2]})
	check_eq(doc.get_at(["food", 1, "pos"]), [1, 2])
	check_eq(doc.get_at(["food"]).size(), 3)
	_check_undo_redo(doc, before, "insert")

func test_insert_creates_list() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	doc.insert_at(["events", 0], {"t": 5, "type": "rain"})
	check_eq(doc.get_at(["events", 0, "type"]), "rain")
	_check_undo_redo(doc, before, "insert into new list")

func test_move_item() -> void:
	var doc := _doc()
	var before := ScenarioJson.stringify(doc.data)
	var first: Dictionary = doc.get_at(["food", 0]).duplicate(true)
	doc.move_item(["food", 0], 1)
	check_eq(doc.get_at(["food", 1]), first)
	_check_undo_redo(doc, before, "move")

func test_changed_signal_and_save() -> void:
	var doc := _doc()
	var paths: Array = []
	doc.changed.connect(func(p: Array) -> void: paths.append(p))
	doc.set_at(["food", 0, "amount"], 7)
	check_eq(paths, [["food", 0, "amount"]])
	var path := OS.get_user_data_dir().path_join("test_scenario_doc.json")
	check_eq(doc.save(path), OK)
	check(not doc.is_dirty(), "clean after save")
	var loaded := ScenarioDoc.load_file(path)
	# JSON numbers load as floats, so compare as text.
	check_eq(ScenarioJson.stringify(loaded.data), ScenarioJson.stringify(doc.data))
	check_eq(loaded.file_path, path)
	DirAccess.remove_absolute(path)
