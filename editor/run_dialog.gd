class_name RunDialog
extends ConfirmationDialog
## The Run options dialog of the scenario editor: seed, start time, layout,
## frame size and overlays of an interactive player run. Fills and reads the
## LaunchCommands.RUN_DEFAULTS settings.

## Emitted on Run with read().
signal run_requested(settings: Dictionary)

const SEED_MODES := ["scenario", "fixed", "random"]
const LAYOUTS := ["", "normal", "split", "nest"]

## Widgets by RUN_DEFAULTS key.
var fields: Dictionary = {}

func _init() -> void:
	title = "Run options"
	get_ok_button().text = "Run"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	add_child(grid)

	var mode := OptionButton.new()
	for text: String in ["Scenario's seed", "Fixed seed", "Random seed"]:
		mode.add_item(text)
	_row(grid, "Seed", "seed_mode", mode)
	var seed := _spin(0, 2147483647, 1)
	_row(grid, "Fixed seed", "seed", seed)
	_row(grid, "Start at (s)", "at", _spin(0.0, 36000.0, 0.1))
	var playhead := CheckBox.new()
	playhead.text = "From playhead"
	_row(grid, "", "from_playhead", playhead)

	var layout := OptionButton.new()
	for text: String in ["Scenario's layout", "Surface", "Split", "Nest"]:
		layout.add_item(text)
	_row(grid, "Layout", "layout", layout)

	var size := OptionButton.new()
	RecordDialog.fill_size_options(size, OutputFrame.DEFAULT_SIZE)
	var custom := LineEdit.new()
	custom.placeholder_text = "WxH, e.g. 1920x1080"
	custom.custom_minimum_size.x = 140
	size.item_selected.connect(func(_i: int) -> void:
		custom.editable = size.selected == size.item_count - 1)
	var size_box := HBoxContainer.new()
	size_box.add_child(size)
	size_box.add_child(custom)
	fields["size"] = size
	fields["size_custom"] = custom
	_label(grid, "Window size")
	grid.add_child(size_box)

	for entry: Array in [["captions", "Captions"], ["safe", "Safe zones"], ["pheromones", "Pheromones"],
			["debug", "Debug overlay"], ["tuning", "Tuning panel"]]:
		var box := CheckBox.new()
		box.text = entry[1]
		_row(grid, "", entry[0], box)

	mode.item_selected.connect(func(_i: int) -> void: _update_enabled())
	playhead.toggled.connect(func(_on: bool) -> void: _update_enabled())
	confirmed.connect(func() -> void: run_requested.emit(read()))
	_update_enabled()

func _spin(min_v: float, max_v: float, step_v: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = min_v
	box.max_value = max_v
	box.step = step_v
	return box

func _label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)

func _row(grid: GridContainer, label: String, key: String, widget: Control) -> void:
	_label(grid, label)
	grid.add_child(widget)
	fields[key] = widget

func _update_enabled() -> void:
	fields["seed"].editable = fields["seed_mode"].selected == SEED_MODES.find("fixed")
	fields["at"].editable = not fields["from_playhead"].button_pressed

## Fills the widgets from `settings` (missing keys take RUN_DEFAULTS), shows
## the playhead time and pops up. `doc_size` is the scenario's output size.
func open(settings: Dictionary, doc_size: Vector2i, playhead: float) -> void:
	var s := LaunchCommands.with_defaults(settings, LaunchCommands.RUN_DEFAULTS)
	fields["seed_mode"].select(maxi(SEED_MODES.find(str(s["seed_mode"])), 0))
	fields["seed"].value = int(s["seed"])
	fields["at"].value = float(s["at"])
	fields["from_playhead"].button_pressed = bool(s["from_playhead"])
	fields["from_playhead"].text = "From playhead (%s s)" % LaunchCommands.num(playhead)
	fields["layout"].select(maxi(LAYOUTS.find(str(s["layout"])), 0))
	RecordDialog.fill_size_options(fields["size"], doc_size)
	RecordDialog.select_size(fields["size"], fields["size_custom"], str(s["size"]))
	for key: String in ["captions", "safe", "pheromones", "debug", "tuning"]:
		fields[key].button_pressed = bool(s[key])
	_update_enabled()
	if is_inside_tree():
		popup_centered()

## The RUN_DEFAULTS-shaped settings from the widgets.
func read() -> Dictionary:
	return {
		"seed_mode": SEED_MODES[fields["seed_mode"].selected],
		"seed": int(fields["seed"].value),
		"at": float(fields["at"].value),
		"from_playhead": bool(fields["from_playhead"].button_pressed),
		"layout": LAYOUTS[fields["layout"].selected],
		"size": RecordDialog.size_from(fields["size"], fields["size_custom"]),
		"captions": bool(fields["captions"].button_pressed),
		"safe": bool(fields["safe"].button_pressed),
		"pheromones": bool(fields["pheromones"].button_pressed),
		"debug": bool(fields["debug"].button_pressed),
		"tuning": bool(fields["tuning"].button_pressed),
	}
