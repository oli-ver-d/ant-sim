extends TestCase
## M16d: the editor's inspector (ScenarioInspector) and its value conversions
## (FieldValues). Widgets are driven through their signals, headless; every
## edit must go through the ScenarioDoc commands (so undo restores the data),
## every field type must have a widget, and every key of the schema must be
## reachable (shown for the full EditorDefaults examples).

var _registry := Registry.create_default()
var _schema := ScenarioSchema.new(_registry)

func _inspector(data: Dictionary, path: Variant) -> ScenarioInspector:
	var doc := ScenarioDoc.new(data, _schema)
	var ins := ScenarioInspector.new()
	ins.size = Vector2(420, 800)
	(Engine.get_main_loop() as SceneTree).root.add_child(ins)
	ins.setup(doc, _schema)
	doc.changed.connect(ins.on_doc_changed)
	ins.show_path(path)
	return ins

func _widget(ins: ScenarioInspector, path: Array) -> Control:
	var row := ins.row_at(path)
	check(row != null, "row for %s" % [path])
	return row.get_meta("widget") if row != null else null

func _basic() -> Dictionary:
	return ScenarioJson.load_file(ScenarioLoader.path_for("basic_forage"))

# --- FieldValues ----------------------------------------------------------------

func test_field_values() -> void:
	check_eq(FieldValues.parse_number(" 12.5 ", FieldSpec.number()), 12.5)
	check_eq(FieldValues.parse_number("12.6", FieldSpec.integer()), 13)
	check_eq(FieldValues.parse_number("abc", FieldSpec.number()), null)
	check_eq(FieldValues.parse_number("5", FieldSpec.number().limits(0, 1)), 1.0, "clamped")
	check_eq(FieldValues.format_number(3.0), "3")
	check_eq(FieldValues.format_number(0.55), "0.55")
	check_eq(FieldValues.tidy([540.0, 1500.5]), [540, 1500.5])
	check_eq(FieldValues.to_color("#ff0000"), Color(1, 0, 0))
	check_eq(FieldValues.to_color([0, 0.5, 1]), Color(0, 0.5, 1))
	check_eq(FieldValues.from_color(Color(1, 0, 0), "#123456"), "#ff0000")
	check_eq(FieldValues.from_color(Color(0.25, 0.5, 1), [0, 0, 0]), [0.25, 0.5, 1.0])
	check_eq(FieldValues.from_color(Color(0, 0, 0, 0.5), [0, 0, 0]), [0.0, 0.0, 0.0, 0.5], "alpha kept")
	var parsed := FieldValues.parse_json_text("{\"a\": [1, 2.5]}")
	check(parsed[0] and parsed[1] == {"a": [1, 2.5]} and parsed[1]["a"][0] is int, "raw JSON parsed, ints kept")
	check(not FieldValues.parse_json_text("{oops")[0], "bad JSON")

# --- widgets drive doc commands ------------------------------------------------------

func test_scalar_edits_and_undo() -> void:
	var ins := _inspector(_basic(), ["food", 0])
	var doc := ins.doc
	var before := ScenarioJson.stringify(doc.data)
	var amount := _widget(ins, ["food", 0, "amount"]) as SpinBox
	amount.value = 77
	check_eq(doc.get_at(["food", 0, "amount"]), 77, "int spin box")
	check(doc.get_at(["food", 0, "amount"]) is int, "stays an int")
	var radius := _widget(ins, ["food", 0, "radius"]) as LineEdit
	radius.text = "31.5"
	radius.text_submitted.emit(radius.text)
	check_eq(doc.get_at(["food", 0, "radius"]), 31.5, "float field")
	radius.focus_exited.emit()
	var pos := _widget(ins, ["food", 0, "pos"])
	var edits: Array = pos.get_meta("edits")
	(edits[0] as LineEdit).text = "100"
	(edits[0] as LineEdit).text_submitted.emit("100")
	check_eq(doc.get_at(["food", 0, "pos"])[0], 100, "vec2 x")
	check(ins.row_at(["food", 0, "amount"]) == amount.get_parent(), "no rebuild for a scalar edit")
	while doc.undo():
		pass
	check_eq(ScenarioJson.stringify(doc.data), before, "undo restores everything")
	ins.free()

func test_absent_key_default_set_and_reset() -> void:
	var ins := _inspector(_basic(), ["food", 0])
	var doc := ins.doc
	var row := ins.row_at(["food", 0, "sense_radius"])
	check(row != null and not row.get_meta("present"), "absent key shown")
	check(row.modulate.a < 1.0, "greyed out")
	var le := row.get_meta("widget") as LineEdit
	check_eq(le.text, "60", "shows the default")
	le.focus_exited.emit()
	check(not doc.has_at(["food", 0, "sense_radius"]), "leaving it unchanged adds nothing")
	le.text = "80"
	le.text_submitted.emit("80")
	check_eq(doc.get_at(["food", 0, "sense_radius"]), 80.0, "set")
	check(row.get_meta("present") and row.modulate.a == 1.0, "no longer greyed")
	var reset := row.get_meta("reset") as Button
	check(reset.visible, "reset shown")
	reset.pressed.emit()
	check(not doc.has_at(["food", 0, "sense_radius"]), "reset removes the key")
	check(ins.row_at(["food", 0, "sense_radius"]) != null, "row rebuilt")
	ins.free()

func test_bool_string_enum() -> void:
	var data := _basic()
	data["render"] = {}
	var ins := _inspector(data, ["render"])
	var doc := ins.doc
	var cb := _widget(ins, ["render", "pheromones"]) as CheckBox
	cb.button_pressed = not cb.button_pressed
	check(doc.has_at(["render", "pheromones"]), "bool set")
	ins.show_path([])
	var name_edit := _widget(ins, ["name"]) as LineEdit
	name_edit.text = "renamed"
	name_edit.text_submitted.emit("renamed")
	check_eq(doc.get_at(["name"]), "renamed", "string")
	var desc := _widget(ins, ["description"])
	check(desc is TextEdit, "description is multi-line")
	ins.show_path(["colonies", 0])
	var species := _widget(ins, ["colonies", 0, "species"]) as OptionButton
	var names := _schema.choices_for("species")
	check_eq(species.item_count, names.size(), "a choice per registered species")
	var other := -1
	for i: int in species.item_count:
		if species.get_item_text(i) != doc.get_at(["colonies", 0, "species"]):
			other = i
	species.select(other)
	species.item_selected.emit(other)
	check_eq(doc.get_at(["colonies", 0, "species"]), species.get_item_text(other), "enum set")
	check(ins.row_at(["colonies", 0, "nest_params"]) != null, "form rebuilt for the new species")
	ins.free()

func test_castes_follow_species() -> void:
	var data := _basic()
	var ins := _inspector(data, ["colonies", 0])
	ins.expand_all = true
	ins.rebuild()
	var add_row := ins.rows.get("colonies/0/population/+") as Control
	check(add_row != null, "population add row")
	var key_input: Control = add_row.get_meta("add_key")
	var species: String = data["colonies"][0]["species"]
	var castes := _schema.choices_for("castes", {"species": species})
	var population: Dictionary = data["colonies"][0].get("population", {})
	if key_input is OptionButton:
		for i: int in (key_input as OptionButton).item_count:
			var c := (key_input as OptionButton).get_item_text(i)
			check(castes.has(c) and not population.has(c), "offered caste %s" % c)
	ins.free()

func test_color_and_raw() -> void:
	var data := {"food": [{"type": "food_pile", "pos": [10, 10], "color": [1, 0, 0]}], "custom": {"a": 1}}
	var ins := _inspector(data, ["food", 0])
	var doc := ins.doc
	var btn := _widget(ins, ["food", 0, "color"]) as ColorPickerButton
	check_eq(btn.color, Color(1, 0, 0), "colour shown")
	btn.color = Color(0, 1, 0)
	btn.popup_closed.emit()
	check_eq(doc.get_at(["food", 0, "color"]), [0.0, 1.0, 0.0], "array colour stays an array")
	ins.show_path(["custom"])
	var raw := _widget(ins, ["custom"]) as TextEdit
	check(raw != null, "unknown key edited as raw JSON")
	raw.text = "{\"a\": 2, \"b\": [1]}"
	raw.focus_exited.emit()
	check_eq(doc.get_at(["custom"]), {"a": 2, "b": [1]}, "raw JSON set")
	raw.text = "{bad"
	raw.focus_exited.emit()
	check_eq(doc.get_at(["custom", "a"]), 2, "bad JSON ignored")
	ins.free()

func test_variant_switch() -> void:
	var ins := _inspector({"obstacles": [{"shape": "rect", "rect": [0, 0, 50, 50], "kind": "water"}]}, ["obstacles", 0])
	var doc := ins.doc
	var tag := _widget(ins, ["obstacles", 0, "shape"]) as OptionButton
	check_eq(tag.get_item_text(tag.selected), "rect", "current shape")
	check(ins.row_at(["obstacles", 0, "rect"]) != null, "rect fields")
	for i: int in tag.item_count:
		if tag.get_item_text(i) == "circle":
			tag.select(i)
			tag.item_selected.emit(i)
	var o: Dictionary = doc.get_at(["obstacles", 0])
	check_eq(o["shape"], "circle", "switched")
	check(o.has("center") and o.has("radius") and not o.has("rect"), "circle's required keys, rect's gone: %s" % [o])
	check_eq(o.get("kind"), "water", "shared key kept")
	check(ins.row_at(["obstacles", 0, "center"]) != null and ins.row_at(["obstacles", 0, "rect"]) == null, "fields swapped")
	doc.undo()
	check_eq(doc.get_at(["obstacles", 0, "shape"]), "rect", "undo")
	check(ins.row_at(["obstacles", 0, "rect"]) != null, "undo rebuilds the form")
	ins.free()

func test_any_of_switch() -> void:
	var ins := _inspector({"ticks_per_frame": 1}, [])
	var doc := ins.doc
	var row := ins.row_at(["ticks_per_frame"])
	var form := row.get_meta("form") as OptionButton
	check(form != null and form.get_item_text(form.selected) == "number", "number form")
	form.select(1)
	form.item_selected.emit(1)
	check(doc.get_at(["ticks_per_frame"]) is Array, "switched to a schedule")
	check(ins.row_at(["ticks_per_frame"]).get_meta("type") == "list", "list form shown")
	ins.free()

func test_list_add_move_remove() -> void:
	var data := {"events": [{"type": "rain", "t": 1}, {"type": "nuptial_flight", "t": 5}]}
	var ins := _inspector(data, ["events"])
	var doc := ins.doc
	var add := ins.rows.get("events/+") as Button
	add.pressed.emit()
	check_eq((doc.get_at(["events"]) as Array).size(), 3, "added")
	check(doc.get_at(["events", 2]) is Dictionary and doc.get_at(["events", 2]).has("type"), "a default event")
	# The move and remove buttons are on each item's header.
	var header := ins.row_at(["events", 0])
	var buttons := header.get_children().filter(func(c: Node) -> bool: return c is Button)
	(buttons[2] as Button).pressed.emit()  # move down ("v")
	check_eq(doc.get_at(["events", 1, "type"]), "rain", "moved down")
	header = ins.row_at(["events", 1])
	buttons = header.get_children().filter(func(c: Node) -> bool: return c is Button)
	(buttons[3] as Button).pressed.emit()  # remove ("x")
	check_eq((doc.get_at(["events"]) as Array).size(), 2, "removed")
	check_eq(doc.get_at(["events", 0, "type"]), "nuptial_flight", "the other stays")
	doc.undo()
	doc.undo()
	doc.undo()
	check_eq(doc.data, data, "undone")
	ins.free()

func test_points_and_nested_absent() -> void:
	var data := {"obstacles": [{"shape": "polyline", "points": [[0, 0], [10, 0]]}]}
	var ins := _inspector(data, ["obstacles", 0])
	var doc := ins.doc
	var header := ins.row_at(["obstacles", 0, "points"])
	var add: Button = header.get_children().filter(func(c: Node) -> bool: return c is Button and c.text == "+")[0]
	add.pressed.emit()
	check_eq(doc.get_at(["obstacles", 0, "points"]), [[0, 0], [10, 0], [30, 0]], "point added after the last")
	var p1 := _widget(ins, ["obstacles", 0, "points", 1])
	var e: Array = p1.get_meta("edits")
	(e[1] as LineEdit).text = "7"
	(e[1] as LineEdit).text_submitted.emit("7")
	check_eq(doc.get_at(["obstacles", 0, "points", 1]), [10, 7], "point edited")
	# A key in a dict the file doesn't have yet: the dicts are created.
	var ins2 := _inspector({"render": {}}, ["render"])
	ins2.expand_all = true
	ins2.rebuild()
	var ratio := _widget(ins2, ["render", "layout", "ratio"])
	var le: LineEdit = ratio.get_meta("line")
	le.text = "0.6"
	le.text_submitted.emit("0.6")
	check_eq(ins2.doc.get_at(["render", "layout"]), {"ratio": 0.6}, "missing dict created")
	var slider: HSlider = ratio.get_meta("slider")
	check_eq(slider.value, 0.6, "slider follows")
	ins.free()
	ins2.free()

func test_output_size_presets() -> void:
	var ins2 := _inspector({"output": {}}, ["output"])
	var size := _widget(ins2, ["output", "size"])
	var presets: OptionButton = size.get_meta("presets")
	check(presets.get_item_text(presets.selected).begins_with("portrait "), "default shown as portrait")
	for i: int in presets.item_count:
		if presets.get_item_text(i).begins_with("landscape "):
			presets.select(i)
			presets.item_selected.emit(i)
	check_eq(ins2.doc.get_at(["output", "size"]), [1920, 1080], "preset set")
	var safe := _widget(ins2, ["output", "safe_zones"]) as OptionButton
	check(safe.item_count >= 3, "safe zone presets")
	ins2.free()

func test_edit_as_json() -> void:
	var ins := _inspector(_basic(), ["food", 0])
	var doc := ins.doc
	var header := ins._box.get_child(0)
	var json_btn: Button = header.get_children().filter(func(c: Node) -> bool: return c is Button and c.text == "Edit as JSON")[0]
	json_btn.pressed.emit()
	var edit := _widget(ins, ["food", 0]) as TextEdit
	check(edit != null and edit.text.contains("food_pile"), "JSON of the item")
	edit.text = "{\"type\": \"food_pile\", \"pos\": [1, 2]}"
	var apply: Button = ins._box.get_children().filter(func(c: Node) -> bool: return c is Button and c.text == "Apply")[0]
	apply.pressed.emit()
	check_eq(doc.get_at(["food", 0]), {"type": "food_pile", "pos": [1, 2]}, "applied")
	check(ins.row_at(["food", 0, "pos"]) != null, "back to the form")
	ins.free()

# --- coverage ---------------------------------------------------------------------------

## A widget of the right kind for every field type.
func test_every_type_has_a_widget() -> void:
	var spec := FieldSpec.dict({
		"i": FieldSpec.integer(1), "f": FieldSpec.number(1.0), "s": FieldSpec.number(0.5).limits(0, 1),
		"b": FieldSpec.boolean(true), "t": FieldSpec.text("x"), "e": FieldSpec.choice(["a", "b"], "a"),
		"v": FieldSpec.vec2([0, 0]), "z": FieldSpec.size([2, 2]), "r": FieldSpec.rect([0, 0, 1, 1]),
		"p": FieldSpec.points(), "c": FieldSpec.color("#ffffff"), "d": FieldSpec.dict({"x": FieldSpec.integer()}),
		"m": FieldSpec.map(FieldSpec.integer()), "l": FieldSpec.list(FieldSpec.integer()),
		"var": FieldSpec.variant("kind", {"one": FieldSpec.dict({"q": FieldSpec.integer()})}),
		"any": FieldSpec.any_of([FieldSpec.number(), FieldSpec.list(FieldSpec.number())]),
		"raw": FieldSpec.raw(),
	})
	_schema.root.fields["_all_types"] = spec
	var data := {"_all_types": {"p": [[0, 0]], "m": {"k": 1}, "l": [1], "var": {"kind": "one"}, "any": 1, "raw": {"x": 1}}}
	var ins := _inspector(data, ["_all_types"])
	ins.expand_all = true
	ins.rebuild()
	var want := {"i": "SpinBox", "f": "LineEdit", "s": "HBoxContainer", "b": "CheckBox", "t": "LineEdit",
			"e": "OptionButton", "v": "HBoxContainer", "z": "HBoxContainer", "r": "HBoxContainer",
			"c": "ColorPickerButton", "raw": "TextEdit", "any": "LineEdit", "var/kind": "OptionButton",
			"p/0": "HBoxContainer", "m/k": "SpinBox", "l/0": "SpinBox", "d/x": "SpinBox", "var/q": "SpinBox"}
	for k: String in want:
		var w := _widget(ins, ["_all_types"] + Array(k.split("/")).map(
				func(s: String) -> Variant: return int(s) if s.is_valid_int() else s))
		check(w != null and w.get_class() == want[k], "%s: %s" % [k, w.get_class() if w != null else "none"])
	for k: String in ["d", "m", "l", "var", "p"]:
		check(ins.row_at(["_all_types", k]) != null, "group for " + k)
	check((_widget(ins, ["_all_types", "s"]) as Control).get_meta("slider") is HSlider, "0-1 float has a slider")
	_schema.root.fields.erase("_all_types")
	ins.free()

## Every key of the full example document `k` has a row when its section is
## shown (all groups open); returns the key names shown.
func _shown_keys(k: int) -> Dictionary:
	var data: Dictionary = EditorDefaults.example(_schema.root, _schema, k)
	var ins := _inspector(data, [])
	ins.expand_all = true
	var shown := {}
	var paths: Array = [[]]
	for key: String in data:
		if not EditorOutline.SCENARIO_KEYS.has(key):
			paths.append([key])
	for p: Array in paths:
		ins.show_path(p)
		for rk: String in ins.rows:
			shown[rk] = true
	var missing: PackedStringArray = []
	_expect_rows(data, [], shown, missing)
	check(missing.is_empty(), "keys without a row (k=%d): %s" % [k, ", ".join(missing.slice(0, 20))])
	ins.free()
	var names := {}
	for rk: String in shown:
		names[rk.get_slice("/", rk.get_slice_count("/") - 1)] = true
	return names

func _expect_rows(v: Variant, at: Array, shown: Dictionary, missing: PackedStringArray) -> void:
	if v is Dictionary:
		for key: Variant in v:
			var p := at + [key]
			if not shown.has(ScenarioInspector.key_of(p)):
				missing.append(ScenarioInspector.key_of(p))
			_expect_rows(v[key], p, shown, missing)
	elif v is Array:
		for i: int in v.size():
			_expect_rows(v[i], at + [i], shown, missing)

func test_every_key_shown_0() -> void:
	_shown_keys(0)

func test_every_key_shown_1() -> void:
	_shown_keys(1)

func test_every_key_shown_2() -> void:
	_shown_keys(2)

func test_every_key_shown_3() -> void:
	_shown_keys(3)

func test_ground_material_dropdown_has_swatches() -> void:
	var data := _basic()
	data["ground"] = {"base": "soil", "regions": [{"material": "moss", "shape": "circle", "center": [500, 500], "radius": 100}]}
	var ins := _inspector(data, ["ground", "regions", 0])
	var opt := _widget(ins, ["ground", "regions", 0, "material"]) as OptionButton
	check(opt != null, "material is an OptionButton")
	if opt != null:
		check(opt.item_count >= GroundMap.MATERIALS.size(), "all materials listed")
		for i: int in opt.item_count:
			check(opt.get_item_icon(i) != null, "icon on item %d" % i)
		check_eq(opt.get_item_text(opt.selected), "moss")
	ins.free()

func test_reseed_scatter() -> void:
	var data := _basic()
	data["scenery"] = [{"type": "rock", "center": [100, 100], "radius": 10}, {"scatter": {"preset": "meadow"}}]
	var ins := _inspector(data, ["scenery", 0])
	var names: Array[String] = []
	for b: Node in ins.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	check(not names.has("Reseed"), "no Reseed for a hand-placed prop")
	ins.show_path(["scenery", 1])
	var reseed: Button = null
	for b: Node in ins.find_children("*", "Button", true, false):
		if (b as Button).text == "Reseed":
			reseed = b
	check(reseed != null, "Reseed on a scatter")
	if reseed == null:
		ins.free()
		return
	reseed.pressed.emit()
	var first: Variant = ins.doc.get_at(["scenery", 1, "scatter", "seed"])
	check(first is int, "seed set")
	ins.reseed_scatter(["scenery", 1])
	check(ins.doc.get_at(["scenery", 1, "scatter", "seed"]) != first, "a different seed each time")
	ins.doc.undo()
	ins.doc.undo()
	check(not ins.doc.has_at(["scenery", 1, "scatter", "seed"]), "undone")
	ins.free()

## Across the examples, every key name the schema knows is shown somewhere.
func test_every_schema_key_reachable() -> void:
	var names := {}
	for k: int in 6:
		names.merge(_shown_keys(k))
	var missing: PackedStringArray = []
	for key: String in _schema.all_key_names():
		if not names.has(key):
			missing.append(key)
	check(missing.is_empty(), "schema keys never shown: %s" % ", ".join(missing))
