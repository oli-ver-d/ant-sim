class_name ScenarioInspector
extends ScrollContainer
## The scenario editor's inspector: a form built from the schema for the
## selected outline row (an item, a section, or the scenario's own settings).
## Every edit goes through the ScenarioDoc commands (set_at, remove_at,
## insert_at, move_item), so it can be undone like any other.
##
## Widgets per field type: int SpinBox; float text field (plus a slider when
## both limits are set); bool CheckBox; string LineEdit (TextEdit for text and
## description); enum OptionButton (choices from the schema or the Registry;
## castes follow the colony's species); vec2 / size / rect number fields (the
## output size also a preset menu); color ColorPickerButton; points a list of
## [x, y] rows; dict, map and list collapsible groups (lists with add, move and
## remove, maps with add key); variant a type selector that swaps the fields;
## any_of a form selector; raw (and keys the schema doesn't know) JSON text.
##
## Keys that aren't in the file show their default greyed out; editing one adds
## it, and its reset button (x) removes it again, so files stay minimal.
## The whole item can also be edited as JSON ("Edit as JSON").

const LABEL_WIDTH := 150
const INDENT := 14
const ABSENT := Color(1, 1, 1, 0.5)
const INVALID := Color(1, 0.55, 0.55)

var doc: ScenarioDoc
var schema: ScenarioSchema
## The path shown (null: nothing).
var path: Variant = null
## Opens every group (tests use it to reach every key).
var expand_all := false
## Every field shown, by path string ("colonies/0/nest"): its row (a label and
## widgets, or a group header) with metas "type" (the field type), "present"
## and "widget" (the main input control, if any).
var rows: Dictionary = {}

var _box: VBoxContainer
## True while the inspector's own command runs (the doc's changed signal then
## doesn't rebuild the form under the widget being edited).
var _own_edit := false
## Groups the user opened or closed, by path string.
var _open: Dictionary = {}
var _json_mode := false
## New scatter seeds ("Reseed").
var _seeds := RandomNumberGenerator.new()

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)

func setup(scenario_doc: ScenarioDoc, scenario_schema: ScenarioSchema) -> void:
	doc = scenario_doc
	schema = scenario_schema
	path = null
	_open.clear()
	_json_mode = false
	rebuild()

func show_path(p: Variant) -> void:
	if p != path:
		_json_mode = false
	path = p
	rebuild()

## The editor calls this on every doc change; changes made elsewhere (undo,
## the outline, later the canvas) rebuild the form.
func on_doc_changed(_changed: Array) -> void:
	if not _own_edit:
		rebuild()

## The row shown for `p` (see `rows`), or null.
func row_at(p: Array) -> Control:
	return rows.get(key_of(p))

static func key_of(p: Array) -> String:
	return "/".join(p.map(func(k: Variant) -> String: return str(k)))

# --- building ---------------------------------------------------------------------

func rebuild() -> void:
	var scroll := scroll_vertical
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	rows.clear()
	if doc == null or path == null or not (doc.has_at(path) or (path as Array).is_empty()):
		_note(_box, "Nothing selected")
		return
	var p: Array = path
	if p.is_empty():
		_build_root()
	else:
		_build_header(p)
		if _json_mode:
			_build_json(p)
		else:
			var spec := _raw_spec_at(p)
			var parent: Variant = doc.get_at(p.slice(0, -1))
			var value: Variant = doc.get_at(p)
			var s := _concrete(spec, value, parent)
			if spec != null and spec.type in ["variant", "dict", "map", "list", "points"] and s != null:
				_build_contents(_box, p, spec, value, true, parent, 0)
			else:
				_add_field(_box, p, spec, value, true, parent, 0,
						_item_label(p[-1], value) if p[-1] is int else str(p[-1]))
	set_deferred("scroll_vertical", scroll)

## The scenario's own settings (the "Scenario" outline row).
func _build_root() -> void:
	for k: String in EditorOutline.SCENARIO_KEYS:
		_add_field(_box, [k], schema.root.fields.get(k), doc.data.get(k), doc.data.has(k), doc.data, 1, k)

func _build_header(p: Array) -> void:
	var bar := HBoxContainer.new()
	_box.add_child(bar)
	rows[key_of(p)] = _meta(bar, "item", true, null)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var json := _button("Form" if _json_mode else "Edit as JSON", "Edit the whole item as JSON text")
	json.pressed.connect(func() -> void:
		_json_mode = not _json_mode
		rebuild())
	bar.add_child(json)
	var item: Variant = doc.get_at(p)
	if p.size() == 2 and p[0] == "scenery" and item is Dictionary and item.get("scatter") is Dictionary:
		var reseed := _button("Reseed", "Scatter again with a new seed (sets the scatter's \"seed\")")
		reseed.pressed.connect(func() -> void: reseed_scatter(p))
		bar.add_child(reseed)
	if p[-1] is int:
		var del := _button("Delete", "Remove this item")
		del.pressed.connect(func() -> void: _remove(p))
		bar.add_child(del)

## Sets the scatter at `p` (a "scenery" entry) to a new random seed. The
## editor's own RNG, never a simulation's.
func reseed_scatter(p: Array) -> void:
	var old: Variant = doc.get_at(p + ["scatter", "seed"])
	var s := _seeds.randi_range(1, 999999)
	while (old is int or old is float) and int(old) == s:
		s = _seeds.randi_range(1, 999999)
	doc.set_at(p + ["scatter", "seed"], s, "Reseed scatter")

func _build_json(p: Array) -> void:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 400)
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_override("font", SystemFont.new())
	edit.text = FieldValues.to_json_text(doc.get_at(p))
	_box.add_child(edit)
	var apply := _button("Apply", "Replace the item with this JSON")
	apply.pressed.connect(func() -> void:
		var parsed := FieldValues.parse_json_text(edit.text)
		if not parsed[0]:
			edit.modulate = INVALID
			return
		_json_mode = false
		_commit(p, parsed[1], null, true))
	_box.add_child(apply)
	rows[key_of(p)] = _meta(edit, "raw", true, edit)

## The unresolved spec at `p` (a variant stays a variant, so its tag can be
## switched); null if the path leaves the schema.
func _raw_spec_at(p: Array) -> FieldSpec:
	var spec := schema.root
	var value: Variant = doc.data
	var parent: Variant = null
	for key: Variant in p:
		var child := schema.child_spec(spec, value, key, parent)
		if child == null:
			return null
		parent = value
		value = _child(value, key)
		spec = child
	return spec

static func _child(value: Variant, key: Variant) -> Variant:
	if value is Dictionary:
		return value.get(key)
	if value is Array and key is int and key >= 0 and key < value.size():
		return value[key]
	return null

## `spec` with its resolver applied (a colony's params or nest_params).
func _picked(spec: FieldSpec, parent: Variant) -> FieldSpec:
	if spec != null and spec.resolver.is_valid() and parent is Dictionary:
		var p: FieldSpec = spec.resolver.call(parent)
		if p != null:
			return p
	return spec

## The spec to draw: resolver applied, a variant as the dict of its fields.
func _concrete(spec: FieldSpec, value: Variant, parent: Variant) -> FieldSpec:
	spec = _picked(spec, parent)
	if spec == null or spec.type == "any_of":
		return spec
	return schema.resolve(spec, value, parent if parent is Dictionary else {})

## One field: a row for a scalar, a collapsible group for a container.
## `extra` (e.g. an any_of form selector) goes after the label.
func _add_field(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int, label: String, extra: Control = null) -> void:
	spec = _picked(spec, parent)
	if spec == null:
		_add_raw(box, fpath, value, present, label, "Not in the schema: kept as it is", false, extra)
		return
	if spec.type == "any_of" and extra == null:
		_add_any_of(box, fpath, spec, value, present, parent, depth, label)
		return
	if spec.type in ["dict", "map", "list", "variant", "points"]:
		_add_group(box, fpath, spec, value, present, parent, depth, label, extra)
		return
	var row := _row(box, fpath, label, spec, present, extra)
	var w: Control
	var shown: Variant = value if present else spec.default
	match spec.type:
		"int":
			w = _int_widget(fpath, spec, shown, present, row)
		"float":
			w = _float_widget(fpath, spec, shown, present, row)
		"bool":
			w = _bool_widget(fpath, shown, row)
		"string":
			w = _string_widget(fpath, shown, present, row, label)
		"enum":
			w = _enum_widget(fpath, spec, value, present)
		"vec2", "size", "rect":
			w = _vector_widget(fpath, spec, shown, present, row)
		"color":
			w = _color_widget(fpath, spec, value, present, row)
		_:
			w = _raw_widget(fpath, value, present, row)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(w)
	row.set_meta("widget", w)
	_add_reset(row, fpath, present, spec.required)

func _add_raw(box: Container, fpath: Array, value: Variant, present: bool, label: String, help: String,
		required: bool, extra: Control = null) -> void:
	var spec := FieldSpec.raw(help)
	spec.required = required
	var row := _row(box, fpath, label, spec, present, extra)
	var w := _raw_widget(fpath, value, present, row)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(w)
	row.set_meta("widget", w)
	_add_reset(row, fpath, present, required)

## A label, `extra`, then the caller adds the widget and the reset button.
func _row(box: Container, fpath: Array, label: String, spec: FieldSpec, present: bool, extra: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = LABEL_WIDTH
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = _tooltip(spec)
	row.add_child(l)
	if extra != null:
		row.add_child(extra)
	rows[key_of(fpath)] = _meta(row, spec.type, present, null)
	if not present:
		row.modulate = ABSENT
	return row

func _meta(c: Control, type: String, present: bool, widget: Control) -> Control:
	c.set_meta("type", type)
	c.set_meta("present", present)
	c.set_meta("widget", widget)
	return c

func _tooltip(spec: FieldSpec) -> String:
	var t := spec.help
	if spec.default != null:
		t += ("\n" if t != "" else "") + "Default: " + FieldValues.to_json_text(spec.default)
	if spec.required:
		t += ("\n" if t != "" else "") + "Required"
	return t

## The reset button: removes the key (back to the default). Hidden for
## required keys and keys that aren't set.
func _add_reset(row: Control, fpath: Array, present: bool, required: bool) -> void:
	if required or (not fpath.is_empty() and fpath[-1] is int):
		# List items have their own remove button.
		return
	var b := _button("x", "Reset to the default (remove the key)")
	b.visible = present
	b.pressed.connect(func() -> void: _remove(fpath))
	row.add_child(b)
	row.set_meta("reset", b)

# --- containers -------------------------------------------------------------------

func _add_group(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int, label: String, extra: Control = null) -> void:
	var key := key_of(fpath)
	var header := HBoxContainer.new()
	box.add_child(header)
	var content := VBoxContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", INDENT)
	margin.add_child(content)
	box.add_child(margin)
	var open: bool = expand_all or _open.get(key, present and depth <= 1 and _size(value) <= 8)
	var fold := _button(("v " if open else "> ") + label, _tooltip(spec))
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.custom_minimum_size.x = LABEL_WIDTH
	header.add_child(fold)
	if extra != null:
		header.add_child(extra)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	if spec.type == "list" or spec.type == "points":
		var add := _button("+", "Add an item")
		add.pressed.connect(_add_list_item.bind(fpath, spec, value))
		header.add_child(add)
	rows[key] = _meta(header, spec.type, present, null)
	if not present:
		header.modulate = ABSENT
	_add_reset(header, fpath, present, spec.required)
	var build := func() -> void:
		_build_contents(content, fpath, spec, value, present, parent, depth)
	margin.visible = open
	if open:
		build.call()
	fold.pressed.connect(func() -> void:
		var now := not margin.visible
		_open[key] = now
		margin.visible = now
		fold.text = ("v " if now else "> ") + label
		if now and content.get_child_count() == 0:
			build.call())

func _build_contents(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int) -> void:
	spec = _picked(spec, parent)
	match spec.type:
		"variant":
			_build_variant(box, fpath, spec, value, present, parent, depth)
		"dict":
			_build_dict(box, fpath, spec, value, present, depth, "")
		"map":
			_build_map(box, fpath, spec, value, present, depth)
		"list":
			_build_list(box, fpath, spec, value, present, parent, depth)
		"points":
			_build_points(box, fpath, value, present)

func _build_dict(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		depth: int, skip: String) -> void:
	var d: Dictionary = value if value is Dictionary else {}
	for k: String in spec.fields:
		if k != skip:
			_add_field(box, fpath + [k], spec.fields[k], d.get(k), present and d.has(k), d, depth + 1, k)
	for k: Variant in d:
		if not spec.fields.has(k) and str(k) != skip:
			_add_raw(box, fpath + [k], d[k], true, str(k), "Not in the schema: kept as it is", false)

func _build_variant(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int) -> void:
	var names := schema.variant_names(spec)
	var current := str(value.get(spec.tag, "")) if value is Dictionary else ""
	var tag_spec := FieldSpec.choice(Array(names), null, spec.help).req()
	var row := _row(box, fpath + [spec.tag], spec.tag, tag_spec, present, null)
	var opt := OptionButton.new()
	_fill_options(opt, names, current, not present)
	opt.item_selected.connect(func(i: int) -> void:
		var picked := opt.get_item_text(i)
		if picked != current and names.has(picked):
			_commit(fpath, EditorDefaults.variant_value(spec, schema, picked, value), null, true))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	row.set_meta("widget", opt)
	var resolved := schema.resolve(spec, value, parent if parent is Dictionary else {})
	_build_dict(box, fpath, resolved, value, present, depth, spec.tag)

func _build_map(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool, depth: int) -> void:
	var d: Dictionary = value if value is Dictionary else {}
	for k: Variant in d:
		_add_field(box, fpath + [k], spec.values, d[k], present, d, depth + 1, str(k))
	var ctx := _context_for(fpath)
	var add_row := HBoxContainer.new()
	box.add_child(add_row)
	var choices: PackedStringArray = []
	if spec.keys_from != "":
		for c: String in schema.choices_for(spec.keys_from, ctx):
			if not d.has(c):
				choices.append(c)
	var key_input: Control
	if not choices.is_empty():
		var opt := OptionButton.new()
		var all_materials := true
		for c: String in choices:
			all_materials = all_materials and GroundMap.MATERIALS.has(c)
		for c: String in choices:
			opt.add_item(c)
			if all_materials:
				opt.set_item_icon(opt.item_count - 1, GroundSwatches.icon(c))
		key_input = opt
	else:
		var le := LineEdit.new()
		le.placeholder_text = "new key"
		key_input = le
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(key_input)
	var add := _button("Add key", "Add an entry")
	add.pressed.connect(func() -> void:
		var k := (key_input as OptionButton).get_item_text((key_input as OptionButton).selected) \
				if key_input is OptionButton else (key_input as LineEdit).text.strip_edges()
		if k != "" and not d.has(k):
			_commit(fpath + [k], EditorDefaults.value_for(spec.values, schema, ctx), null, true))
	add_row.add_child(add)
	add_row.set_meta("add_key", key_input)
	add_row.set_meta("add", add)
	rows[key_of(fpath) + "/+"] = add_row

func _build_list(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int) -> void:
	var list: Array = value if value is Array else []
	for i: int in list.size():
		var item_path := fpath + [i]
		var buttons: Array[Control] = [
			_list_button("^", "Move up", func() -> void: _move(item_path, i - 1), i > 0),
			_list_button("v", "Move down", func() -> void: _move(item_path, i + 1), i < list.size() - 1),
			_list_button("x", "Remove", func() -> void: _remove(item_path), true),
		]
		_add_field(box, item_path, spec.item, list[i], true, list, depth + 1, _item_label(i, list[i]))
		var row := row_at(item_path)
		for b: Control in buttons:
			row.add_child(b)
	if depth == 0:
		var add := _button("+ Add", "Add an item")
		add.pressed.connect(_add_list_item.bind(fpath, spec, value))
		box.add_child(add)
		rows[key_of(fpath) + "/+"] = add

func _build_points(box: Container, fpath: Array, value: Variant, present: bool) -> void:
	var pts: Array = value if value is Array else []
	for i: int in pts.size():
		var p := fpath + [i]
		var row := _row(box, p, "#%d" % i, FieldSpec.vec2(), present, null)
		var w := _vector_widget(p, FieldSpec.vec2(), pts[i], true, row)
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(w)
		row.set_meta("widget", w)
		row.add_child(_list_button("x", "Remove the point", func() -> void: _remove(p), pts.size() > 1))

func _add_list_item(fpath: Array, spec: FieldSpec, value: Variant) -> void:
	var list: Array = value if value is Array else []
	var item: Variant
	if spec.type == "points":
		var last: Variant = list[-1] if not list.is_empty() else [0, 0]
		item = FieldValues.tidy([float(last[0]) + 20.0, float(last[1])]) if last is Array and last.size() >= 2 else [0, 0]
	else:
		item = EditorDefaults.value_for(spec.item, schema, _context_for(fpath))
	_own_edit = true
	doc.insert_at(fpath + [list.size()], item)
	_own_edit = false
	var key := key_of(fpath)
	_open[key] = true
	_open[key_of(fpath + [list.size()])] = true
	rebuild()

func _list_button(text: String, tip: String, action: Callable, enabled: bool) -> Button:
	var b := _button(text, tip)
	b.disabled = not enabled
	b.pressed.connect(action)
	return b

## An any_of field: a selector of its forms (e.g. one speed or a schedule),
## then the field in the chosen form.
func _add_any_of(box: Container, fpath: Array, spec: FieldSpec, value: Variant, present: bool,
		parent: Variant, depth: int, label: String) -> void:
	var alts := _flat_alternatives(spec)
	var names: PackedStringArray = []
	var current := -1
	for i: int in alts.size():
		var alt := alts[i]
		names.append(_alt_name(alt))
		if present and current < 0 and alt.matches(value):
			current = i
	var opt := OptionButton.new()
	opt.tooltip_text = spec.help
	if current < 0:
		opt.add_item("(default)")
	for n: String in names:
		opt.add_item(n)
	opt.select(0 if current < 0 else current)
	opt.item_selected.connect(func(i: int) -> void:
		var index := i - (1 if current < 0 else 0)
		if index >= 0 and index != current:
			_commit(fpath, EditorDefaults.value_for(alts[index], schema, _context_for(fpath)), null, true))
	if current < 0:
		var row := _row(box, fpath, label, spec, present, opt)
		row.set_meta("widget", opt)
		_add_reset(row, fpath, present, spec.required)
		return
	_add_field(box, fpath, alts[current], value, present, parent, depth, label, opt)
	row_at(fpath).set_meta("form", opt)

## An any_of's alternatives, with nested any_ofs spread out.
static func _flat_alternatives(spec: FieldSpec) -> Array[FieldSpec]:
	var out: Array[FieldSpec] = []
	for alt: FieldSpec in spec.alternatives:
		if alt.type == "any_of":
			out.append_array(_flat_alternatives(alt))
		else:
			out.append(alt)
	return out

static func _alt_name(alt: FieldSpec) -> String:
	match alt.type:
		"int", "float":
			return "number"
		"list":
			return "list"
		"dict":
			return alt.help if alt.help != "" and alt.help.length() < 40 else "settings"
	return alt.help if alt.help != "" and alt.help.length() < 40 else alt.type

static func _item_label(i: int, v: Variant) -> String:
	var s := "#%d" % i
	if v is Dictionary:
		for k: String in ["type", "shape", "species", "material", "name", "mode", "text"]:
			if v.has(k) and v[k] is String and v[k] != "":
				s += " " + (v[k] as String).left(24)
				break
		if v.has("t"):
			s += " t=" + FieldValues.format_number(v["t"])
	return s

static func _size(v: Variant) -> int:
	if v is Dictionary or v is Array:
		return v.size()
	return 0

# --- scalar widgets -----------------------------------------------------------------

func _int_widget(fpath: Array, spec: FieldSpec, shown: Variant, present: bool, row: Control) -> Control:
	var sb := SpinBox.new()
	sb.min_value = spec.min_value if is_finite(spec.min_value) else -1e9
	sb.max_value = spec.max_value if is_finite(spec.max_value) else 1e9
	sb.step = 1
	sb.rounded = true
	sb.value = float(shown) if shown is float or shown is int else 0.0
	# Lambdas capture locals by value: keep what changes in a dictionary.
	var state := {"old": shown if present else null}
	sb.value_changed.connect(func(v: float) -> void:
		if state["old"] == null or int(v) != int(state["old"]):
			state["old"] = int(v)
			_commit(fpath, int(v), row))
	return sb

func _float_widget(fpath: Array, spec: FieldSpec, shown: Variant, present: bool, row: Control) -> Control:
	var le := LineEdit.new()
	le.text = FieldValues.format_number(shown)
	le.placeholder_text = "unset"
	var state := {"old": shown if present else null, "slider": null}
	var commit := func(text: String) -> void:
		var v: Variant = FieldValues.parse_number(text, spec)
		if v == null:
			le.text = FieldValues.format_number(state["old"] if state["old"] != null else shown)
			return
		if state["old"] != null and is_equal_approx(float(v), float(state["old"])):
			return
		if state["old"] == null and text.strip_edges() == FieldValues.format_number(shown):
			return
		state["old"] = v
		le.text = FieldValues.format_number(v)
		if state["slider"] != null:
			(state["slider"] as HSlider).set_value_no_signal(float(v))
		_commit(fpath, FieldValues.tidy(v) if spec.type == "int" else v, row)
	le.text_submitted.connect(commit)
	le.focus_exited.connect(func() -> void: commit.call(le.text))
	if not (is_finite(spec.min_value) and is_finite(spec.max_value)):
		return le
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	state["slider"] = slider
	slider.min_value = spec.min_value
	slider.max_value = spec.max_value
	slider.step = 0.0
	slider.value = float(shown) if shown is float or shown is int else spec.min_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dragging := {"on": false}
	slider.drag_started.connect(func() -> void: dragging["on"] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging["on"] = false
		commit.call(FieldValues.format_number(snappedf(slider.value, 0.0001))))
	slider.value_changed.connect(func(v: float) -> void:
		le.text = FieldValues.format_number(snappedf(v, 0.0001))
		if not dragging["on"]:
			commit.call(le.text))
	le.custom_minimum_size.x = 70
	box.add_child(slider)
	box.add_child(le)
	box.set_meta("line", le)
	box.set_meta("slider", slider)
	return box

func _bool_widget(fpath: Array, shown: Variant, row: Control) -> Control:
	var cb := CheckBox.new()
	cb.button_pressed = shown == true
	cb.toggled.connect(func(on: bool) -> void: _commit(fpath, on, row))
	return cb

func _string_widget(fpath: Array, shown: Variant, present: bool, row: Control, key: String) -> Control:
	var text := str(shown) if shown != null else ""
	var state := {"old": text if present else null}
	var commit := func(t: String) -> void:
		if t == (state["old"] if state["old"] != null else text) and (state["old"] != null or t == text):
			return
		state["old"] = t
		_commit(fpath, t, row)
	if key in ["text", "description"] or text.contains("\n"):
		var te := TextEdit.new()
		te.text = text
		te.custom_minimum_size = Vector2(0, 64)
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.focus_exited.connect(func() -> void: commit.call(te.text))
		return te
	var le := LineEdit.new()
	le.text = text
	le.text_submitted.connect(commit)
	le.focus_exited.connect(func() -> void: commit.call(le.text))
	return le

func _enum_widget(fpath: Array, spec: FieldSpec, value: Variant, present: bool) -> Control:
	var choices: PackedStringArray = spec.choices
	if spec.choices_from != "":
		choices = schema.choices_for(spec.choices_from, _context_for(fpath))
	var current: String = str(value) if present and value != null else (str(spec.default) if spec.default != null else "")
	var opt := OptionButton.new()
	_fill_options(opt, choices, current, not present and (spec.default == null or str(spec.default) == ""))
	opt.item_selected.connect(func(i: int) -> void:
		var picked := opt.get_item_text(i)
		if picked == "(unset)":
			if present:
				_remove(fpath)
			return
		if not present or picked != current:
			_commit(fpath, picked, null, true))
	return opt

## Fills `opt` with `choices`, selecting `current` (added if unknown); an
## "(unset)" first item if `unset`.
static func _fill_options(opt: OptionButton, choices: PackedStringArray, current: String, unset: bool) -> void:
	if unset:
		opt.add_item("(unset)")
	var swatches := GroundSwatches.is_material_choice(choices)
	for c: String in choices:
		opt.add_item(c)
		if swatches:
			opt.set_item_icon(opt.item_count - 1, GroundSwatches.icon(c))
	if current != "" and not choices.has(current):
		opt.add_item(current)
	for i: int in opt.item_count:
		if opt.get_item_text(i) == current and not unset:
			opt.select(i)
			return
	opt.select(0)

func _vector_widget(fpath: Array, spec: FieldSpec, shown: Variant, present: bool, row: Control) -> Control:
	var count := 4 if spec.type == "rect" else 2
	var box := HBoxContainer.new()
	var values := FieldValues.components(shown, count)
	var num := FieldSpec.integer() if spec.type == "size" else FieldSpec.number()
	var edits: Array[LineEdit] = []
	var names: Array = ["x", "y", "w", "h"] if count == 4 else (["w", "h"] if spec.type == "size" else ["x", "y"])
	var state := {"old": FieldValues.tidy(values) if present else null}
	for i: int in count:
		var le := LineEdit.new()
		le.text = FieldValues.format_number(values[i])
		le.tooltip_text = names[i]
		le.placeholder_text = names[i]
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.custom_minimum_size.x = 56
		box.add_child(le)
		edits.append(le)
	var commit := func(_t: String = "") -> void:
		var out: Array = []
		for le: LineEdit in edits:
			var v: Variant = FieldValues.parse_number(le.text, num)
			if v == null:
				return
			out.append(v)
		out = FieldValues.tidy(out)
		if out == (state["old"] if state["old"] != null else FieldValues.tidy(values)) and (state["old"] != null or not present and out == FieldValues.tidy(values)):
			return
		state["old"] = out
		_commit(fpath, out, row)
	for le: LineEdit in edits:
		le.text_submitted.connect(commit)
		le.focus_exited.connect(commit)
	box.set_meta("edits", edits)
	if spec.type == "size" and fpath == ["output", "size"]:
		var presets := OptionButton.new()
		presets.add_item("custom")
		var keys: Array = OutputFrame.PRESETS.keys()
		for k: String in keys:
			var s: Vector2i = OutputFrame.PRESETS[k]
			presets.add_item("%s %dx%d" % [k, s.x, s.y])
			if values[0] == s.x and values[1] == s.y:
				presets.select(presets.item_count - 1)
		presets.item_selected.connect(func(i: int) -> void:
			if i > 0:
				var s: Vector2i = OutputFrame.PRESETS[keys[i - 1]]
				_commit(fpath, [s.x, s.y], null, true))
		box.add_child(presets)
		box.set_meta("presets", presets)
	return box

func _color_widget(fpath: Array, spec: FieldSpec, value: Variant, present: bool, row: Control) -> Control:
	var like: Variant = value if present else spec.default
	var state := {"old": FieldValues.from_color(FieldValues.to_color(like), like if like != null else "") if present else null}
	var btn := ColorPickerButton.new()
	btn.color = FieldValues.to_color(like)
	btn.custom_minimum_size = Vector2(60, 0)
	btn.popup_closed.connect(func() -> void:
		var v: Variant = FieldValues.from_color(btn.color, like if like != null else "")
		if v != state["old"]:
			state["old"] = v
			_commit(fpath, v, row))
	return btn

func _raw_widget(fpath: Array, value: Variant, present: bool, row: Control) -> Control:
	var te := TextEdit.new()
	te.text = FieldValues.to_json_text(value) if present else ""
	te.custom_minimum_size = Vector2(0, 32 if not (value is Dictionary or value is Array) else 80)
	te.scroll_fit_content_height = true
	te.add_theme_font_override("font", SystemFont.new())
	var state := {"old": te.text}
	te.focus_exited.connect(func() -> void:
		if te.text == state["old"]:
			return
		var parsed := FieldValues.parse_json_text(te.text)
		te.modulate = Color.WHITE if parsed[0] else INVALID
		if parsed[0]:
			state["old"] = te.text
			_commit(fpath, parsed[1], row))
	return te

# --- commands -----------------------------------------------------------------------

## Sets `fpath` to `value` through the doc. `row` (a field that wasn't set)
## turns from greyed to set; `restructure` rebuilds the form (types, species,
## lists changed).
func _commit(fpath: Array, value: Variant, row: Control = null, restructure: bool = false) -> void:
	_own_edit = true
	doc.set_at(fpath, value)
	_own_edit = false
	if restructure:
		rebuild()
	elif row != null and is_instance_valid(row) and not row.get_meta("present", true):
		row.set_meta("present", true)
		row.modulate = Color.WHITE
		var reset: Control = row.get_meta("reset", null)
		if reset != null:
			reset.visible = true

func _remove(fpath: Array) -> void:
	_own_edit = true
	doc.remove_at(fpath)
	_own_edit = false
	rebuild()

func _move(fpath: Array, to: int) -> void:
	_own_edit = true
	doc.move_item(fpath, to)
	_own_edit = false
	rebuild()

## The nearest enclosing dictionary with a "species" (for castes, channels and
## params choices), else the one holding `fpath`.
func _context_for(fpath: Array) -> Dictionary:
	for n: int in range(fpath.size(), -1, -1):
		var v: Variant = doc.get_at(fpath.slice(0, n))
		if v is Dictionary and v.has("species"):
			return v
	var parent: Variant = doc.get_at(fpath.slice(0, -1))
	return parent if parent is Dictionary else {}

# --- helpers ------------------------------------------------------------------------

static func _button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b

static func _note(box: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = ABSENT
	box.add_child(l)
