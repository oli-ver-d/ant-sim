class_name TuningPanel
extends PanelContainer
## Interactive tuning panel (main scene only, so it never appears in
## recordings). Toggle with T.
##
## - Colony selector: which colony (and so which species) to tune, and whose
##   food types right-click places.
## - Food type selector for right-click.
## - Live sliders for SimConfig (except STRUCTURAL settings) and for the
##   selected species' numeric tunables and pheromone channels. Changes apply
##   at once: every colony's params are rebuilt (Simulation.refresh_params()).
##   Scenario per-colony overrides still win over these.
## - Save writes SimConfig and the species back to their .tres files; Reset
##   restores the values the panel started with.

const WIDTH := 500.0
const FONT_SIZE := 22
## Channel properties that get sliders.
const CHANNEL_PROPS: PackedStringArray = ["half_life", "diffusion", "cap", "reinforce"]

var sim: Simulation
var registry: Registry
## Selected colony index.
var colony_id: int = 0
## Food source type id placed by right-click.
var food_type: String = ""

var _colony_select: OptionButton
var _food_select: OptionButton
var _rows: VBoxContainer
var _status: Label
## Original values for Reset: [object, key, value] (object: SimConfig,
## tunables Dictionary or PheromoneChannelDef).
var _originals: Array[Array] = []

func setup(simulation: Simulation, reg: Registry) -> void:
	sim = simulation
	registry = reg
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.05, 0.86)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_label("Tuning  (T hides)", FONT_SIZE + 4))
	box.add_child(_label("Colony (tune / place food for)", FONT_SIZE))
	_colony_select = _option(box)
	for colony in sim.colonies:
		_colony_select.add_item("%s #%d" % [colony.species.display_name, colony.id])
	_colony_select.item_selected.connect(_on_colony_selected)
	box.add_child(_label("Right-click places", FONT_SIZE))
	_food_select = _option(box)
	_food_select.item_selected.connect(func(k: int) -> void: food_type = _food_select.get_item_text(k))

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var save := Button.new()
	save.text = "Save to .tres"
	save.add_theme_font_size_override("font_size", FONT_SIZE)
	save.pressed.connect(_save)
	buttons.add_child(save)
	var reset := Button.new()
	reset.text = "Reset"
	reset.add_theme_font_size_override("font_size", FONT_SIZE)
	reset.pressed.connect(_reset)
	buttons.add_child(reset)
	_status = _label("", FONT_SIZE - 2)
	box.add_child(_status)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	box.add_child(_rows)
	_on_colony_selected(0)

## Rebuilds the food selector and sliders for the selected colony.
func _on_colony_selected(k: int) -> void:
	colony_id = k
	var species := sim.colonies[k].species
	_food_select.clear()
	for t in species.food_source_types:
		if registry.food_source_types.has(t):
			_food_select.add_item(t)
	food_type = _food_select.get_item_text(0) if _food_select.item_count > 0 else ""

	for child in _rows.get_children():
		child.queue_free()
	_rows.add_child(_label("Global (SimConfig)", FONT_SIZE + 2))
	for prop in sim.config.get_property_list():
		var key: String = prop["name"]
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or SimConfig.STRUCTURAL.has(key):
			continue
		var value: Variant = sim.config.get(key)
		if value is float or value is int:
			_add_slider(key, value, sim.config, key)
	_rows.add_child(_label("%s tunables" % species.display_name, FONT_SIZE + 2))
	for key: Variant in species.tunables:
		var value: Variant = species.tunables[key]
		if value is float or value is int:
			_add_slider(str(key), value, species.tunables, key)
	for ch in species.channels:
		_rows.add_child(_label("Channel \"%s\"" % ch.name, FONT_SIZE + 2))
		for prop_name in CHANNEL_PROPS:
			_add_slider(prop_name, ch.get(prop_name), ch, prop_name)

## One labelled slider editing target[key] (a Resource property or a
## Dictionary entry). Range: 0 to 4x the starting value.
func _add_slider(title: String, value: Variant, target: Variant, key: Variant) -> void:
	var is_int := value is int
	var v := float(value)
	_remember(target, key, value)
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	row.add_child(head)
	var name_label := _label(title, FONT_SIZE - 2)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := _label(_fmt(v, is_int), FONT_SIZE - 2)
	head.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = maxf(absf(v) * 4.0, 10.0) if is_int else (absf(v) * 4.0 if v != 0.0 else 1.0)
	if title == "diffusion" or title.ends_with("_fraction"):
		slider.max_value = 1.0
	slider.step = 1.0 if is_int else slider.max_value / 500.0
	slider.value = v
	slider.custom_minimum_size = Vector2(0, 26)
	slider.value_changed.connect(func(nv: float) -> void:
		var out: Variant = int(nv) if is_int else nv
		_write(target, key, out)
		value_label.text = _fmt(nv, is_int)
		sim.refresh_params())
	row.add_child(slider)
	_rows.add_child(row)

func _save() -> void:
	var errors: PackedStringArray = []
	var species := sim.colonies[colony_id].species
	for res: Resource in [sim.config, species]:
		if res.resource_path == "":
			continue
		var err := ResourceSaver.save(res, res.resource_path)
		if err != OK:
			errors.append("%s (error %d)" % [res.resource_path, err])
	_status.text = "Saved config and %s" % species.display_name if errors.is_empty() else "Failed: " + ", ".join(errors)

func _reset() -> void:
	for entry in _originals:
		_write(entry[0], entry[1], entry[2])
	sim.refresh_params()
	_on_colony_selected(colony_id)
	_status.text = "Reset to the starting values"

func _remember(target: Variant, key: Variant, value: Variant) -> void:
	for entry in _originals:
		if is_same(entry[0], target) and entry[1] == key:
			return
	_originals.append([target, key, value])

static func _write(target: Variant, key: Variant, value: Variant) -> void:
	if target is Dictionary:
		(target as Dictionary)[key] = value
	else:
		(target as Object).set(key, value)

static func _fmt(v: float, is_int: bool) -> String:
	return str(int(v)) if is_int else String.num(v, 4)

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l

func _option(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", FONT_SIZE)
	parent.add_child(o)
	return o
