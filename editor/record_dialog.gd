class_name RecordDialog
extends AcceptDialog
## The Record dialog of the scenario editor: the settings of a recording
## (format, frame size, seed, range, captions, output) with a summary of what
## would be written, and, once a RecordJob runs, its progress and log. Two pages
## in one dialog; only one is visible.
##
## Fills and reads the LaunchCommands.RECORD_DEFAULTS settings; the caller
## (the editor) plans and starts the job on record_requested.

## Emitted on Record when the settings make a valid plan. `set_output` asks for
## the chosen frame size to be written to the scenario's output.size.
signal record_requested(settings: Dictionary, set_output: bool)

const MAX_LOG_LINES := 2000
const CUSTOM := "custom"

## Widgets by RECORD_DEFAULTS key (plus `set_output`).
var fields: Dictionary = {}
var summary: Label
var status: Label
var progress: ProgressBar
var log: TextEdit
var cancel_button: Button
var result: Label
var open_folder_button: Button
var play_button: Button
var new_button: Button

var scenario_path := ""
var data: Dictionary = {}
var project_dir := ""
var job: RecordJob

var _settings_page: VBoxContainer
var _progress_page: VBoxContainer
var _cancel_dialog: Button
var _doc_size := OutputFrame.DEFAULT_SIZE
var _filling := false

## Fills `option` with the size choices: "Scenario's (WxH)" (value "", the
## document's size), the OutputFrame presets (value "WxH") and "Custom".
static func fill_size_options(option: OptionButton, doc_size: Vector2i) -> void:
	option.clear()
	option.add_item("Scenario's (%s)" % LaunchCommands.size_label(doc_size))
	option.set_item_metadata(0, "")
	for preset_name: String in OutputFrame.PRESETS:
		var s: Vector2i = OutputFrame.PRESETS[preset_name]
		option.add_item("%s %s" % [preset_name, LaunchCommands.size_label(s)])
		option.set_item_metadata(option.item_count - 1, LaunchCommands.size_label(s))
	option.add_item("Custom")
	option.set_item_metadata(option.item_count - 1, CUSTOM)

## The settings value of the size widget ("" = the document's size).
static func size_from(option: OptionButton, custom: LineEdit) -> String:
	var value := str(option.get_item_metadata(option.selected))
	return custom.text.strip_edges() if value == CUSTOM else value

## Selects the item for a settings value and enables the custom field for Custom.
static func select_size(option: OptionButton, custom: LineEdit, value: String) -> void:
	value = value.strip_edges()
	var index := option.item_count - 1
	if value == "":
		index = 0
	else:
		if OutputFrame.PRESETS.has(value):
			value = LaunchCommands.size_label(OutputFrame.PRESETS[value])
		for i in range(1, option.item_count - 1):
			if str(option.get_item_metadata(i)) == value:
				index = i
				break
	option.select(index)
	if index == option.item_count - 1:
		custom.text = value
	custom.editable = index == option.item_count - 1

func _init() -> void:
	title = "Record"
	dialog_hide_on_ok = false
	min_size = Vector2i(560, 0)
	get_ok_button().text = "Record"
	_cancel_dialog = add_cancel_button("Cancel")
	var root := VBoxContainer.new()
	add_child(root)
	_build_settings(root)
	_build_progress(root)
	_progress_page.visible = false
	confirmed.connect(_on_confirmed)
	set_process(true)

func _build_settings(root: VBoxContainer) -> void:
	_settings_page = VBoxContainer.new()
	root.add_child(_settings_page)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_settings_page.add_child(grid)

	var format := OptionButton.new()
	format.add_item("PNG (final, lossless)")
	format.set_item_metadata(0, "png")
	format.add_item("AVI / MJPEG (fast draft)")
	format.set_item_metadata(1, "avi")
	_row(grid, "Format", "format", format)
	_row(grid, "MJPEG quality", "mjpeg_quality", _spin(0.0, 1.0, 0.05))

	var size := OptionButton.new()
	fill_size_options(size, _doc_size)
	var custom := LineEdit.new()
	custom.placeholder_text = "WxH, e.g. 1920x1080"
	custom.custom_minimum_size.x = 140
	custom.text_changed.connect(func(_t: String) -> void: _changed())
	size.item_selected.connect(func(_i: int) -> void:
		fields["size_custom"].editable = size.selected == size.item_count - 1
		_changed())
	var size_box := HBoxContainer.new()
	size_box.add_child(size)
	size_box.add_child(custom)
	fields["size"] = size
	fields["size_custom"] = custom
	_add_label(grid, "Frame size")
	grid.add_child(size_box)

	var set_output := CheckBox.new()
	set_output.text = "Also set as the scenario's output size"
	fields["set_output"] = set_output
	set_output.toggled.connect(func(_on: bool) -> void: _changed())
	_add_label(grid, "")
	grid.add_child(set_output)

	var seed := _spin(-1, 2147483647, 1)
	seed.tooltip_text = "-1: the scenario's seed"
	_row(grid, "Seed", "seed", seed)
	_row(grid, "Start (s)", "start", _spin(0.0, 36000.0, 0.1))
	var whole := CheckBox.new()
	whole.text = "To the end"
	_row(grid, "", "whole", whole)
	_row(grid, "End (s)", "end", _spin(0.0, 36000.0, 0.1))
	var captions := CheckBox.new()
	captions.text = "Captions"
	_row(grid, "", "captions", captions)

	var dir_box := HBoxContainer.new()
	var out_dir := LineEdit.new()
	out_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_dir.text_changed.connect(func(_t: String) -> void: _changed())
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(_browse)
	dir_box.add_child(out_dir)
	dir_box.add_child(browse)
	dir_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields["out_dir"] = out_dir
	_add_label(grid, "Output folder")
	grid.add_child(dir_box)

	var file_name := LineEdit.new()
	file_name.placeholder_text = "automatic: <scenario>_seed<N>_..."
	file_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_name.text_changed.connect(func(_t: String) -> void: _changed())
	_row(grid, "File name", "file_name", file_name)
	var keep := CheckBox.new()
	keep.text = "Keep the captured frames"
	_row(grid, "", "keep_frames", keep)

	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	summary.custom_minimum_size.x = 520
	_settings_page.add_child(summary)

func _build_progress(root: VBoxContainer) -> void:
	_progress_page = VBoxContainer.new()
	root.add_child(_progress_page)
	status = Label.new()
	_progress_page.add_child(status)
	progress = ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.step = 0.0
	progress.custom_minimum_size = Vector2(520, 20)
	_progress_page.add_child(progress)
	log = TextEdit.new()
	log.editable = false
	log.custom_minimum_size = Vector2(520, 220)
	_progress_page.add_child(log)
	result = Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	result.custom_minimum_size.x = 520
	result.visible = false
	_progress_page.add_child(result)
	var buttons := HBoxContainer.new()
	_progress_page.add_child(buttons)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func() -> void:
		if job != null:
			job.cancel())
	buttons.add_child(cancel_button)
	open_folder_button = Button.new()
	open_folder_button.text = "Open folder"
	open_folder_button.visible = false
	open_folder_button.pressed.connect(func() -> void:
		if job != null:
			OS.shell_show_in_file_manager(str(job.plan.get("out_path", ""))))
	buttons.add_child(open_folder_button)
	play_button = Button.new()
	play_button.text = "Play"
	play_button.visible = false
	play_button.pressed.connect(func() -> void:
		if job != null:
			OS.shell_open(str(job.plan.get("out_path", ""))))
	buttons.add_child(play_button)
	new_button = Button.new()
	new_button.text = "New recording"
	new_button.visible = false
	new_button.pressed.connect(_show_settings)
	buttons.add_child(new_button)

func _spin(min_v: float, max_v: float, step_v: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = min_v
	box.max_value = max_v
	box.step = step_v
	box.allow_greater = false
	box.value_changed.connect(func(_v: float) -> void: _changed())
	return box

func _add_label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)

func _row(grid: GridContainer, label: String, key: String, widget: Control) -> void:
	_add_label(grid, label)
	grid.add_child(widget)
	fields[key] = widget
	if widget is OptionButton:
		(widget as OptionButton).item_selected.connect(func(_i: int) -> void: _changed())
	elif widget is CheckBox:
		(widget as CheckBox).toggled.connect(func(_on: bool) -> void: _changed())

func _browse() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Output folder"
	var current := str(fields["out_dir"].text)
	if current != "":
		dialog.current_dir = current if current.is_absolute_path() else project_dir.path_join(current)
	dialog.dir_selected.connect(func(dir: String) -> void:
		fields["out_dir"].text = dir
		_changed())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)

## Fills the widgets from `settings`, shows the settings page and pops up.
## `data` is the scenario's data: its output.size is the "document size".
func open(settings: Dictionary, path: String, scenario_data: Dictionary, project: String) -> void:
	scenario_path = path
	data = scenario_data
	project_dir = project
	_doc_size = OutputFrame.from_scenario(data).size
	var s := LaunchCommands.with_defaults(settings, LaunchCommands.RECORD_DEFAULTS)
	_filling = true
	var format: OptionButton = fields["format"]
	format.select(1 if str(s["format"]) == "avi" else 0)
	fields["mjpeg_quality"].value = float(s["mjpeg_quality"])
	fill_size_options(fields["size"], _doc_size)
	select_size(fields["size"], fields["size_custom"], str(s["size"]))
	fields["set_output"].button_pressed = false
	fields["seed"].value = int(s["seed"])
	fields["start"].value = float(s["start"])
	var end := float(s["end"])
	fields["whole"].button_pressed = end < 0.0
	fields["end"].value = float(data.get("duration", 20.0)) if end < 0.0 else end
	fields["captions"].button_pressed = bool(s["captions"])
	fields["out_dir"].text = str(s["out_dir"])
	fields["file_name"].text = str(s["file_name"])
	fields["keep_frames"].button_pressed = bool(s["keep_frames"])
	_filling = false
	_show_settings()
	_popup()

## The RECORD_DEFAULTS-shaped settings from the widgets.
func read() -> Dictionary:
	return {
		"format": str(fields["format"].get_item_metadata(fields["format"].selected)),
		"mjpeg_quality": float(fields["mjpeg_quality"].value),
		"size": size_from(fields["size"], fields["size_custom"]),
		"seed": int(fields["seed"].value),
		"start": float(fields["start"].value),
		"end": -1.0 if fields["whole"].button_pressed else float(fields["end"].value),
		"captions": bool(fields["captions"].button_pressed),
		"out_dir": str(fields["out_dir"].text),
		"file_name": str(fields["file_name"].text),
		"keep_frames": bool(fields["keep_frames"].button_pressed),
	}

## True when "also set as the scenario's output size" is checked and enabled.
func set_output_requested() -> bool:
	return fields["set_output"].button_pressed and not fields["set_output"].disabled

func _popup() -> void:
	if is_inside_tree():
		popup_centered()

func _current_size() -> Vector2i:
	var text := size_from(fields["size"], fields["size_custom"])
	return _doc_size if text == "" else OutputFrame.parse_size(text)

func _plan() -> Dictionary:
	return LaunchCommands.record_plan(read(), scenario_path, data, project_dir, "<time>")

func _changed() -> void:
	if _filling:
		return
	_refresh()

## Enabling of dependent widgets and the summary.
func _refresh() -> void:
	fields["mjpeg_quality"].editable = str(fields["format"].get_item_metadata(fields["format"].selected)) == "avi"
	fields["end"].editable = not fields["whole"].button_pressed
	fields["set_output"].disabled = _current_size() == _doc_size
	if fields["set_output"].disabled:
		fields["set_output"].button_pressed = false
	var plan := _plan()
	if plan["ok"]:
		var frames: int = plan["expected_frames"]
		var size: Vector2i = plan["frame_size"]
		summary.text = "%s, %d frames (%s s) -> %s" % [LaunchCommands.size_label(size), frames,
				LaunchCommands.num(float(frames) / LaunchCommands.RECORD_FPS), plan["out_path"]]
		summary.remove_theme_color_override("font_color")
	else:
		summary.text = str(plan["error"])
		summary.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

func _on_confirmed() -> void:
	if _progress_page.visible:
		hide()
		return
	_refresh()
	if not _plan()["ok"]:
		return
	hide()
	record_requested.emit(read(), set_output_requested())

func _show_settings() -> void:
	_disconnect_job()
	job = null
	_settings_page.visible = true
	_progress_page.visible = false
	get_ok_button().visible = true
	get_ok_button().text = "Record"
	_cancel_dialog.visible = true
	title = "Record"
	_refresh()
	reset_size()

## Switches to the progress page for `job` (the job keeps running when the
## dialog is closed; call this again to show it).
func show_job(new_job: RecordJob) -> void:
	_disconnect_job()
	job = new_job
	job.output.connect(_on_output)
	job.finished.connect(_on_finished)
	title = "Recording"
	_settings_page.visible = false
	_progress_page.visible = true
	_cancel_dialog.visible = false
	log.text = ""
	result.visible = false
	open_folder_button.visible = false
	play_button.visible = false
	new_button.visible = false
	for line in job.log_lines:
		_append(line)
	if job.is_running() or job.stage == RecordJob.Stage.IDLE:
		cancel_button.visible = true
		get_ok_button().visible = false
	else:
		_show_result(job.stage == RecordJob.Stage.DONE, job.message)
	_update_progress()
	reset_size()
	_popup()

func _disconnect_job() -> void:
	if job == null:
		return
	if job.output.is_connected(_on_output):
		job.output.disconnect(_on_output)
	if job.finished.is_connected(_on_finished):
		job.finished.disconnect(_on_finished)

func _update_progress() -> void:
	if job == null:
		return
	status.text = job.status_text()
	progress.value = job.fraction()

func _process(_delta: float) -> void:
	if visible and _progress_page.visible:
		_update_progress()

func _on_output(line: String) -> void:
	_append(line)

func _append(line: String) -> void:
	var last := log.get_line_count() - 1
	if last == 0 and log.get_line(0) == "":
		log.set_line(0, line)
	else:
		log.insert_text("\n" + line, last, log.get_line(last).length())
	while log.get_line_count() > MAX_LOG_LINES:
		log.remove_line_at(0, false)
	log.scroll_vertical = log.get_line_count()

func _on_finished(ok: bool, message: String) -> void:
	_show_result(ok, message)
	_update_progress()

func _show_result(ok: bool, message: String) -> void:
	cancel_button.visible = false
	result.text = message
	result.visible = true
	open_folder_button.visible = ok
	play_button.visible = ok
	new_button.visible = true
	get_ok_button().visible = true
	get_ok_button().text = "Close"
