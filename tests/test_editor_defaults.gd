extends TestCase
## M16d: EditorDefaults, the GUI-free helper behind the inspector's Add buttons
## and variant switches: defaults per field type, variant switching, the Add
## actions of outline rows, new items (valid per the schema and loadable) and the
## full examples that reach every key of the schema.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()
var _schema := ScenarioSchema.new(_registry)

func _spec(path: Array) -> FieldSpec:
	var spec := _schema.root
	for key: Variant in path:
		spec = _schema.child_spec(spec, null, key)
	return spec

func test_scalar_defaults() -> void:
	check_eq(EditorDefaults.value_for(FieldSpec.integer(), _schema), 0)
	check_eq(EditorDefaults.value_for(FieldSpec.number(), _schema), 0.0)
	check_eq(EditorDefaults.value_for(FieldSpec.boolean(), _schema), false)
	check_eq(EditorDefaults.value_for(FieldSpec.text(), _schema), "")
	check_eq(EditorDefaults.value_for(FieldSpec.integer(7), _schema), 7)
	check(EditorDefaults.value_for(FieldSpec.integer(7), _schema) is int, "int default stays an int")
	check_eq(EditorDefaults.value_for(FieldSpec.number(2.5), _schema), 2.5)
	check_eq(EditorDefaults.value_for(FieldSpec.text("hi"), _schema), "hi")
	check_eq(EditorDefaults.value_for(FieldSpec.boolean(true), _schema), true)

func test_enum_defaults() -> void:
	check_eq(EditorDefaults.value_for(FieldSpec.choice(["a", "b"]), _schema), "a")
	check_eq(EditorDefaults.value_for(FieldSpec.choice(["a", "b"], "b"), _schema), "b")
	check_eq(EditorDefaults.value_for(FieldSpec.choice([]), _schema), "")
	var species := _schema.choices_for("species")
	check(not species.is_empty(), "species registered")
	check_eq(EditorDefaults.value_for(FieldSpec.choice([]).from_registry("species"), _schema), species[0])
	var castes := _schema.choices_for("castes", {"species": species[0]})
	check_eq(EditorDefaults.value_for(FieldSpec.choice([]).from_registry("castes"), _schema, {"species": species[0]}), castes[0] if not castes.is_empty() else "")

func test_geometry_defaults() -> void:
	check_eq(EditorDefaults.value_for(FieldSpec.vec2(), _schema), [0, 0])
	check_eq(EditorDefaults.value_for(FieldSpec.vec2([3, 4]), _schema), [3, 4])
	check_eq(EditorDefaults.value_for(FieldSpec.size(), _schema), [100, 100])
	check_eq(EditorDefaults.value_for(FieldSpec.size([1080, 1920]), _schema), [1080, 1920])
	check_eq(EditorDefaults.value_for(FieldSpec.rect(), _schema), [0, 0, 100, 100])
	check_eq(EditorDefaults.value_for(FieldSpec.points(), _schema), [[0, 0], [100, 0]])
	check_eq(EditorDefaults.value_for(FieldSpec.color(), _schema), "#ffffff")
	check_eq(EditorDefaults.value_for(FieldSpec.color([0, 0, 0]), _schema), [0, 0, 0])

func test_container_defaults() -> void:
	check_eq(EditorDefaults.value_for(FieldSpec.map(FieldSpec.integer()), _schema), {})
	check_eq(EditorDefaults.value_for(FieldSpec.list(FieldSpec.integer()), _schema), [])
	check_eq(EditorDefaults.value_for(FieldSpec.raw(), _schema), {})
	var d := FieldSpec.dict({"a": FieldSpec.integer(3).req(), "b": FieldSpec.integer(4), "c": FieldSpec.vec2().req()})
	check_eq(EditorDefaults.value_for(d, _schema), {"a": 3, "c": [0, 0]})
	var any := FieldSpec.any_of([FieldSpec.list(FieldSpec.integer()), FieldSpec.number(1.0)])
	check_eq(EditorDefaults.value_for(any, _schema), [])
	# Real specs.
	var colony: Variant = EditorDefaults.value_for(_spec(["colonies", 0]), _schema)
	check_eq(colony.keys(), ["species", "nest"])
	check_eq(colony["species"], _schema.choices_for("species")[0])
	check_eq(EditorDefaults.value_for(_spec(["ground"]), _schema), "soil")
	check_eq(EditorDefaults.value_for(_spec(["ticks_per_frame"]), _schema), 0.5)

func test_variant_default() -> void:
	var ob: Variant = EditorDefaults.value_for(_spec(["obstacles", 0]), _schema)
	check_eq(ob, {"shape": "polyline", "points": [[0, 0], [100, 0]]})
	var food: Variant = EditorDefaults.value_for(_spec(["food", 0]), _schema)
	check_eq(food, {"type": "food_pile", "pos": [0, 0]})
	var ev: Variant = EditorDefaults.value_for(_spec(["events", 0]), _schema)
	check_eq(ev["type"], "spawn_food")
	check_eq(ev["t"], 0.0)
	check_eq(ev["food"], {"type": "food_pile", "pos": [0, 0]})
	check_eq(ev.keys(), ["type", "t", "food"])

func test_variant_value_keeps_shared_keys() -> void:
	var spec := _spec(["events", 0])
	var v := EditorDefaults.variant_value(spec, _schema, "nuptial_flight", {"type": "rain", "t": 12, "duration": 9})
	check_eq(v, {"type": "nuptial_flight", "t": 12})
	check_eq(v.keys(), ["type", "t"])
	var r := EditorDefaults.variant_value(spec, _schema, "rain", {"type": "nuptial_flight", "t": 3, "colony": 1})
	check_eq(r, {"type": "rain", "t": 3})
	var s := EditorDefaults.variant_value(spec, _schema, "spawn_food", null)
	check_eq(s.keys(), ["type", "t", "food"])
	# Food type keeps pos.
	var food := EditorDefaults.variant_value(_spec(["food", 0]), _schema, "food_pile", {"type": "other", "pos": [5, 6], "junk": 1})
	check_eq(food, {"type": "food_pile", "pos": [5, 6]})
	# Obstacle shape switch keeps common optional keys the new shape also has.
	var ob := EditorDefaults.variant_value(_spec(["obstacles", 0]), _schema, "circle", {"shape": "rect", "rect": [0, 0, 1, 1], "kind": "water"})
	check_eq(ob["shape"], "circle")
	check_eq(ob["kind"], "water")
	check(not ob.has("rect"), "rect dropped")
	check(ob.has("center") and ob.has("radius"), "circle's required keys")
	check_eq(ob.keys()[0], "shape")

func _ids(actions: Array[Dictionary]) -> Array:
	return actions.map(func(a: Dictionary) -> String: return a["id"])

func test_add_actions_rows() -> void:
	var data := ScenarioLoader.load_data("basic_forage")
	var a := EditorDefaults.add_actions(data, ["colonies"])
	check_eq(a, [{"label": "Add colony", "id": "colony", "list": ["colonies"]}])
	check_eq(EditorDefaults.add_actions(data, ["colonies", 0]), a)
	check_eq(_ids(EditorDefaults.add_actions(data, ["food", 1])), ["food"])
	check_eq(_ids(EditorDefaults.add_actions(data, ["obstacles"])), ["obstacle"])
	var g := EditorDefaults.add_actions(data, ["ground", "regions", 2])
	check_eq(g, [{"label": "Add ground region", "id": "ground_region", "list": ["ground", "regions"]}])
	var s := EditorDefaults.add_actions(data, ["scenery", 0])
	check_eq(s.map(func(x: Dictionary) -> String: return x["label"]), ["Add prop", "Add scatter"])
	check_eq(s[0]["list"], ["scenery"])
	check_eq(s[1]["list"], ["scenery"])
	check_eq(EditorDefaults.add_actions(data, ["debris"])[0]["label"], "Add debris")
	check_eq(EditorDefaults.add_actions(data, ["events", 0])[0]["label"], "Add event")
	check_eq(EditorDefaults.add_actions(data, ["render"])[0]["list"], ["render", "captions"])
	check_eq(EditorDefaults.add_actions(data, ["name"]), [])
	check_eq(EditorDefaults.add_actions(data, ["output"]), [])

func test_add_actions_camera() -> void:
	var list := EditorDefaults.add_actions({"camera": [{"t": 0}]}, ["camera", 0])
	check_eq(list, [{"label": "Add camera key", "id": "camera_key", "list": ["camera"]}])
	var absent := EditorDefaults.add_actions({}, ["camera"])
	check_eq(absent[0]["list"], ["camera"])
	var tracks := EditorDefaults.add_actions({"camera": {"surface": [], "nest": []}}, ["camera", "nest"])
	check_eq(tracks.size(), 2)
	check_eq(tracks[0], {"label": "Add camera key", "id": "camera_key", "list": ["camera", "surface"]})
	check_eq(tracks[1], {"label": "Add nest camera key", "id": "nest_camera_key", "list": ["camera", "nest"]})

func test_add_actions_scenario_row() -> void:
	var a := EditorDefaults.add_actions({}, [])
	check_eq(_ids(a), ["colony", "food", "obstacle", "ground_region", "prop", "scatter", "debris", "event", "camera_key", "caption"])
	var t := EditorDefaults.add_actions({"camera": {}}, [])
	check_eq(_ids(t), ["colony", "food", "obstacle", "ground_region", "prop", "scatter", "debris", "event", "camera_key", "nest_camera_key", "caption"])
	# The action lists are copies.
	a[0]["list"].append("x")
	check_eq(EditorDefaults.add_actions({}, [])[0]["list"], ["colonies"])

## A document with a list for every action, filled with `n` new items each.
func _doc_with_items(at: Vector2) -> Dictionary:
	var data := {"seed": 1, "camera": {"surface": [], "nest": []}, "render": {"captions": [{"t": 1, "until": 6, "text": "a"}]},
			"ground": {"regions": []}, "scenery": [], "debris": [], "events": [], "obstacles": [], "food": [], "colonies": []}
	for a: Dictionary in EditorDefaults.add_actions(data, []):
		var item: Variant = EditorDefaults.new_item(a["id"], data, _schema, at)
		check(item != null, "item for " + a["id"])
		var v: Variant = data
		var list: Array = a["list"]
		for key: Variant in list:
			v = v[key]
		(v as Array).append(item)
	return data

func test_new_items_schema_valid() -> void:
	var data := _doc_with_items(Vector2(400.6, 700.2))
	check_eq(_schema.unknown_paths(data), PackedStringArray(), "unknown paths")
	for a: Dictionary in EditorDefaults.add_actions(data, []):
		var list: Array = a["list"]
		var container: Variant = data
		for key: Variant in list:
			container = container[key]
		var idx := (container as Array).size() - 1
		var path := list + [idx]
		var spec := _schema.spec_at(data, path)
		check(spec != null and spec.type == "dict", "spec for " + a["id"])
		if spec == null:
			continue
		var item: Dictionary = (container as Array)[idx]
		for key: String in spec.fields:
			if (spec.fields[key] as FieldSpec).required:
				check(item.has(key), "%s has required %s" % [a["id"], key])

func test_new_items_positions_are_ints() -> void:
	var item: Dictionary = EditorDefaults.new_item("food", {}, _schema, Vector2(400.6, 700.2))
	check_eq(item["pos"], [401, 700])
	check(item["pos"][0] is int, "ints")
	var ob: Dictionary = EditorDefaults.new_item("obstacle", {}, _schema, Vector2(400, 700))
	check_eq(ob["rect"], [340, 690, 120, 20])
	check_eq(EditorDefaults.new_item("nope", {}, _schema, Vector2.ZERO), null)

func test_new_items_load_and_run() -> void:
	var data := _doc_with_items(Vector2(540, 900))
	var sim := ScenarioLoader.build(data, _registry, _config, 3)
	check(sim != null, "builds")
	for i in 5:
		sim.step()
	check(sim.tick_count >= 5, "steps")

func test_new_items_load_each_species() -> void:
	for species: String in _schema.choices_for("species"):
		var data := {"seed": 1, "colonies": [{"species": species, "nest": [540, 900]}], "food": [EditorDefaults.new_item("food", {}, _schema, Vector2(300, 500))]}
		var sim := ScenarioLoader.build(data, _registry, _config, 1)
		for i in 3:
			sim.step()
		check(sim != null, species + " loads")

func test_camera_and_caption_times() -> void:
	var cam := {"camera": [{"t": 0}, {"t": 4.5}]}
	check_eq(EditorDefaults.new_item("camera_key", cam, _schema, Vector2(1, 2)), {"t": 6.5, "pos": [1, 2], "zoom": 1})
	check_eq(EditorDefaults.new_item("camera_key", {}, _schema, Vector2(1, 2))["t"], 0)
	var tracks := {"camera": {"surface": [{"t": 3}], "nest": [{"t": 10}]}}
	check_eq(EditorDefaults.new_item("camera_key", tracks, _schema, Vector2.ZERO)["t"], 5)
	check_eq(EditorDefaults.new_item("nest_camera_key", tracks, _schema, Vector2.ZERO)["t"], 12)
	var caps := {"render": {"captions": [{"t": 1, "until": 6.5, "text": "x"}]}}
	check_eq(EditorDefaults.new_item("caption", caps, _schema, Vector2.ZERO), {"t": 6.5, "text": "Caption"})
	var no_until := {"render": {"captions": [{"t": 2, "text": "x"}]}}
	check_eq(EditorDefaults.new_item("caption", no_until, _schema, Vector2.ZERO)["t"], 6)
	check_eq(EditorDefaults.new_item("caption", {}, _schema, Vector2.ZERO)["t"], 0)

## A full example document built from the root spec with variant number `k`.
func _example_unknown(k: int) -> void:
	var data: Dictionary = EditorDefaults.example(_schema.root, _schema, k)
	check(data.size() > 10, "example %d has the sections" % k)
	var unknown := _schema.unknown_paths(data)
	check_eq(unknown, PackedStringArray(), "example %d unknown paths" % k)

func test_example_0() -> void:
	_example_unknown(0)

func test_example_1() -> void:
	_example_unknown(1)

func test_example_2() -> void:
	_example_unknown(2)

func test_example_3() -> void:
	_example_unknown(3)

func test_example_4() -> void:
	_example_unknown(4)

func test_example_5() -> void:
	_example_unknown(5)

func test_example_shapes() -> void:
	var data: Dictionary = EditorDefaults.example(_schema.root, _schema, 0)
	var colony: Dictionary = data["colonies"][0]
	check_eq(colony["species"], _schema.choices_for("species")[0])
	check(colony["params"] is Dictionary and colony["params"].size() > 5, "params filled")
	check_eq((data["food"] as Array).size(), _schema.variant_names(_spec(["food", 0])).size(), "a food per variant")
	check_eq((data["events"] as Array).size(), _schema.variant_names(_spec(["events", 0])).size(), "an event per variant")
	check_eq((data["obstacles"] as Array).map(func(o: Dictionary) -> String: return o["shape"]), ["polyline", "polygon", "rect", "circle"])
	check(data["max_agents"].has("surface"), "dict fields all present")
	var b: Dictionary = EditorDefaults.example(_schema.root, _schema, 1)
	check(b["colonies"][0]["species"] != colony["species"] or _schema.choices_for("species").size() == 1, "k picks another species")
	check_eq(EditorDefaults.example(FieldSpec.map(FieldSpec.integer(), "species"), _schema, 0), {_schema.choices_for("species")[0]: 0})
	check_eq(EditorDefaults.example(FieldSpec.map(FieldSpec.integer()), _schema, 0), {"key": 0})
	check_eq(EditorDefaults.example(FieldSpec.choice(["a", "b", "c"]), _schema, 4), "b")
	var any := FieldSpec.any_of([FieldSpec.integer(1), FieldSpec.text("x")])
	check_eq(EditorDefaults.example(any, _schema, 1), "x")
