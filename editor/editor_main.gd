class_name ScenarioEditor
extends Control
## The scenario editor (scenes/editor.tscn): opens a scenario JSON as a
## ScenarioDoc, shows it as an outline (left), a static preview built by the
## real loader and renderers (centre, EditorPreview) and the selected item
## (right, ScenarioInspector: every option as a form) and saves it back with
## ScenarioJson. "Add..." above the outline adds an item of the selected
## row's section (all sections on the Scenario row) at the view centre.
##
##   godot --path . res://scenes/editor.tscn [-- --scenario=<name or path> | --new] [--screenshot=<path>]
##       [--select=scenery/1] [--materials] [--play=<video s>] [--dialog=run|record|record_now]
##   tools/editor.sh [--scenario=...]
## Without --scenario= it reopens the last file (--new: a new document).
##
## File menu: New (a minimal template), Open, Open Recent (kept in
## user://editor_settings.cfg), Save, Save As, Revert, Quit; unsaved changes
## are confirmed before New, Open, Revert and closing the window.
## Edit menu: Undo / Redo (doc commands). View: fit world, fit output frame.
## Canvas editing (CanvasEditor, drawn by GizmoLayer): click selects the
## smallest item there, drag moves it or the selected item's handles, Alt-click
## inserts a point, Delete / Ctrl+D (preview focused) delete / duplicate; the
## tool bar over the preview has the place tools, grid snap and the ground
## materials overlay. Wheel zooms, middle or right drag pans. Outline rows of
## list items can be dragged to reorder them (OutlineDrag; e.g. ground
## regions' paint order).
## Timeline (TimelinePanel, bottom): camera keys, speed, layout modes,
## captions, fades, grade, story marker and events on one video-time ruler;
## Play runs the document in EditorPlay (a real ScenarioPlayer) in place of
## the static preview until Stop or the next edit.
## Run menu (M16h): Run (F5) starts the interactive player (main.tscn) as a
## separate process on a temporary copy of the document (so unsaved edits run),
## with the options of Run options...; Stop run kills it. Record... (Ctrl+R)
## records the document with RecordJob (the same GDScript pipeline as
## tools/record.gd) in the background, with progress, Cancel, Open folder and
## Play. The last settings are remembered per scenario (LaunchSettings).
## Validation (M16i): ScenarioValidator runs after every preview build; the
## Problems list under the inspector, outline colours and preview outlines
## show the issues, and Save, Run and Record with errors ask first. The panel
## split positions are remembered ("layout" in the settings file).

const WINDOW_SIZE := Vector2i(1600, 900)
const SCENARIO_DIR := "res://scenarios"
## How near (view pixels) a click must be to a handle or shape.
const HANDLE_TOLERANCE := 8.0

enum FileItem { NEW, OPEN, SAVE, SAVE_AS, REVERT, QUIT }
enum EditItem { UNDO, REDO }
enum ViewItem { FIT_WORLD, FIT_FRAME }
enum RunItem { RUN, STOP, OPTIONS, RECORD }

## Editor settings (recent files); tests point it elsewhere before _ready.
var settings_path := "user://editor_settings.cfg"
## Arguments as on the command line after "--" (tests set them before _ready).
var args: Dictionary = {}
## Sizes the window and takes over closing it (off in tests).
var manage_window := true
var doc: ScenarioDoc
var schema: ScenarioSchema
var registry: Registry
var recent := EditorRecent.new()
var preview: EditorPreview
## What clicks, drags and keys in the preview do (M16e).
var canvas := CanvasEditor.new()
var gizmos: GizmoLayer
## Place tool buttons by tool id, and the grid snap toggle.
var tool_buttons: Dictionary = {}
var snap_toggle: CheckBox
## Shows the ground materials overlay (GizmoLayer.show_materials).
var materials_toggle: CheckBox
var outline: Tree
var outline_drag: OutlineDrag
## "Add ..." actions for the selected outline row (EditorDefaults.add_actions).
var add_menu: MenuButton
var inspector: ScenarioInspector
## The play preview (shown instead of the static one while a run exists) and
## the timeline under everything (M16g).
var play: EditorPlay
var timeline: TimelinePanel
var details_title: Label
var status: Label
## Outline rows (EditorOutline.build) of the current document.
var rows: Array[Dictionary] = []
## Path of the selected outline row (null: nothing selected).
var selected: Variant = null

var _file_menu: PopupMenu
var _recent_menu: PopupMenu
var _edit_menu: PopupMenu
var _file_dialog: FileDialog
## True while the file dialog picks a file to save to (else one to open).
var _saving_as := false
var _confirm: ConfirmationDialog
var _message: AcceptDialog
## What to do after the unsaved-changes prompt is answered (Save or Discard).
var _after_confirm: Callable
var _screenshot_path := ""
var _screenshot_frames := -1
var _building_outline := false
var _add_actions: Array[Dictionary] = []

## Run and record (M16h). Temporary copies of the document go under runs_dir
## (run/ and record/, so a new run never rewrites the file a recording is
## starting from). project_dir and godot_path are what launched processes get
## (tests point them elsewhere); launch_process starts a process and returns
## its pid (tests replace it).
var runs_dir := "user://editor_runs"
var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
var godot_path := ""
var launch_process: Callable = func(exe: String, run_args: PackedStringArray) -> int:
	return OS.create_process(exe, run_args)
var run_dialog: RunDialog
var record_dialog: RecordDialog
## The interactive run's process id (-1: none) and the recording (null: none yet).
var run_pid := -1
var record_job: RecordJob
var _run_menu: PopupMenu
var _quit_confirm: ConfirmationDialog

## M16i: the document's validation issues (ScenarioValidator), redone after
## every preview build, listed under the inspector and marked in the outline
## and the preview.
var issues: Array[Dictionary] = []
var problems: ItemList
var problems_title: Label
## Asks before saving, running or recording a document with errors.
var _warn: ConfirmationDialog
var _after_warn: Callable
## The split containers whose offsets are remembered ("layout" section).
var _splits: Dictionary = {}

func _ready() -> void:
	if args.is_empty():
		args = _parse_args()
	if manage_window:
		_setup_window()
		get_tree().auto_accept_quit = false
	registry = Registry.create_default()
	CoreRenderers.register(registry)
	schema = ScenarioSchema.new(registry)
	recent.load_from(settings_path)
	_build_ui()
	preview.registry = registry

	var scenario := str(args.get("scenario", ""))
	if scenario != "":
		_open(ScenarioLoader.path_for(scenario))
	elif not args.has("new") and not recent.files.is_empty() and FileAccess.file_exists(recent.files[0]):
		# Carries on with the last file (--new starts a new document).
		_open(recent.files[0])
	else:
		_new_doc()
	_screenshot_path = str(args.get("screenshot", ""))
	if _screenshot_path != "":
		_screenshot_frames = 5
		var select := str(args.get("select", ""))
		if select != "":
			_select_path(_parse_path(select))
	if args.has("materials"):
		materials_toggle.button_pressed = true
	if args.has("play"):
		# Play preview paused at a video time (for screenshots).
		timeline.set_playhead(float(args["play"]), false)
		timeline.toggle_play()
		timeline.toggle_play()
	match str(args.get("dialog", "")):
		# For screenshots: the Run options, the Record settings, or a 3 s AVI
		# draft recording (the screenshot waits for its first second).
		"run":
			_on_run_menu(RunItem.OPTIONS)
		"record":
			open_record()
		"record_now":
			start_recording({"format": "avi", "end": 3.0})
			record_dialog.popup_centered()

func _setup_window() -> void:
	var window := get_window()
	# The project's scenes are laid out in a portrait frame; the editor uses
	# the window's own pixels.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
		var want := Vector2i(mini(WINDOW_SIZE.x, screen.size.x), mini(WINDOW_SIZE.y, screen.size.y))
		window.size = want
		window.position = screen.position + (screen.size - want) / 2
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var menus := MenuBar.new()
	bar.add_child(menus)
	_file_menu = PopupMenu.new()
	_file_menu.name = "File"
	_file_menu.add_item("New", FileItem.NEW, KEY_MASK_CTRL | KEY_N)
	_file_menu.add_item("Open...", FileItem.OPEN, KEY_MASK_CTRL | KEY_O)
	_recent_menu = PopupMenu.new()
	_recent_menu.name = "Recent"
	_recent_menu.index_pressed.connect(_on_recent)
	_file_menu.add_submenu_node_item("Open Recent", _recent_menu)
	_file_menu.add_item("Save", FileItem.SAVE, KEY_MASK_CTRL | KEY_S)
	_file_menu.add_item("Save As...", FileItem.SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	_file_menu.add_item("Revert", FileItem.REVERT)
	_file_menu.add_separator()
	_file_menu.add_item("Quit", FileItem.QUIT, KEY_MASK_CTRL | KEY_Q)
	_file_menu.id_pressed.connect(_on_file_menu)
	menus.add_child(_file_menu)
	_edit_menu = PopupMenu.new()
	_edit_menu.name = "Edit"
	_edit_menu.add_item("Undo", EditItem.UNDO, KEY_MASK_CTRL | KEY_Z)
	_edit_menu.add_item("Redo", EditItem.REDO, KEY_MASK_CTRL | KEY_Y)
	_edit_menu.id_pressed.connect(_on_edit_menu)
	menus.add_child(_edit_menu)
	var view_menu := PopupMenu.new()
	view_menu.name = "View"
	view_menu.add_item("Fit world", ViewItem.FIT_WORLD, KEY_HOME)
	view_menu.add_item("Fit output frame", ViewItem.FIT_FRAME, KEY_F)
	view_menu.id_pressed.connect(func(id: int) -> void:
		if id == ViewItem.FIT_WORLD:
			preview.fit_world()
		else:
			preview.fit_frame())
	menus.add_child(view_menu)
	_run_menu = PopupMenu.new()
	_run_menu.name = "Run"
	_run_menu.add_item("Run", RunItem.RUN, KEY_F5)
	_run_menu.add_item("Stop run", RunItem.STOP, KEY_MASK_SHIFT | KEY_F5)
	_run_menu.add_item("Run options...", RunItem.OPTIONS)
	_run_menu.add_separator()
	_run_menu.add_item("Record...", RunItem.RECORD, KEY_MASK_CTRL | KEY_R)
	_run_menu.id_pressed.connect(_on_run_menu)
	menus.add_child(_run_menu)
	for label: String in ["Fit world", "Fit frame"]:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(preview_fit.bind(label == "Fit world"))
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	for item: Array in [["Run", RunItem.RUN], ["Stop", RunItem.STOP], ["Run options", RunItem.OPTIONS],
			["Record...", RunItem.RECORD]]:
		var b := Button.new()
		b.text = item[0]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_run_menu.bind(item[1]))
		bar.add_child(b)

	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vsplit)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsplit.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	split.add_child(left)
	add_menu = MenuButton.new()
	add_menu.text = "Add..."
	add_menu.flat = false
	add_menu.about_to_popup.connect(_fill_add_menu)
	add_menu.get_popup().index_pressed.connect(func(i: int) -> void: add_item(_add_actions[i]))
	left.add_child(add_menu)
	outline = Tree.new()
	outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline.hide_root = true
	outline.item_selected.connect(_on_outline_selected)
	left.add_child(outline)
	outline_drag = OutlineDrag.new(self)

	var right := HSplitContainer.new()
	split.add_child(right)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(centre)
	centre.add_child(_build_tool_bar())
	# The static preview and the play view share the space (one is shown).
	var stage := MarginContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(stage)
	preview = EditorPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.status_changed.connect(func(_t: String) -> void:
		validate()
		_update_status())
	preview.gui_input.connect(_on_preview_input)
	stage.add_child(preview)
	play = EditorPlay.new()
	play.visible = false
	stage.add_child(play)
	gizmos = GizmoLayer.new()
	gizmos.preview = preview
	gizmos.canvas = canvas
	preview.add_layer(gizmos)
	canvas.redraw_requested.connect(gizmos.queue_redraw)
	canvas.select_requested.connect(_on_canvas_select)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(420, 0)
	right.add_child(side)
	details_title = Label.new()
	side.add_child(details_title)
	inspector = ScenarioInspector.new()
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(inspector)
	problems_title = Label.new()
	side.add_child(problems_title)
	problems = ItemList.new()
	problems.custom_minimum_size = Vector2(0, 110)
	problems.item_selected.connect(func(i: int) -> void:
		_select_path(issues[int(problems.get_item_metadata(i))]["path"]))
	side.add_child(problems)

	timeline = TimelinePanel.new()
	timeline.select_requested.connect(_on_canvas_select)
	timeline.play_view.connect(_show_play)
	timeline.key_here = func(t: float) -> Dictionary:
		return TimelineModel.camera_key_here(preview.camera.position, preview.size / preview.camera.zoom.x,
				preview.frame.size_f(), t)
	vsplit.add_child(timeline)
	_splits = {"timeline": vsplit, "outline": split, "inspector": right}
	_restore_layout()

	status = Label.new()
	status.clip_text = true
	root.add_child(status)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json ; Scenario JSON"])
	_file_dialog.size = Vector2i(900, 600)
	_file_dialog.file_selected.connect(_on_file_chosen)
	add_child(_file_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Unsaved changes"
	_confirm.ok_button_text = "Save"
	_confirm.add_button("Discard", true, "discard")
	_confirm.confirmed.connect(func() -> void:
		if _save():
			_run_after_confirm())
	_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_confirm.hide()
			_run_after_confirm())
	add_child(_confirm)
	_message = AcceptDialog.new()
	add_child(_message)
	run_dialog = RunDialog.new()
	run_dialog.run_requested.connect(func(s: Dictionary) -> void:
		LaunchSettings.save_for(settings_path, "run", doc.file_path, s)
		run())
	add_child(run_dialog)
	record_dialog = RecordDialog.new()
	record_dialog.record_requested.connect(start_recording)
	add_child(record_dialog)
	_quit_confirm = ConfirmationDialog.new()
	_quit_confirm.title = "Recording"
	_quit_confirm.dialog_text = "A recording is running. Cancel it and quit?"
	_quit_confirm.confirmed.connect(func() -> void:
		record_job.cancel()
		_quit())
	add_child(_quit_confirm)
	_warn = ConfirmationDialog.new()
	_warn.title = "Problems in the scenario"
	_warn.confirmed.connect(func() -> void:
		var action := _after_warn
		_after_warn = Callable()
		if action.is_valid():
			action.call())
	add_child(_warn)
	_refresh_recent()

## Select plus a toggle button per place tool (CanvasEditor.TOOLS), and grid snap.
func _build_tool_bar() -> Control:
	var bar := HFlowContainer.new()
	var group := ButtonGroup.new()
	for t: Array in CanvasEditor.TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Select, move and edit handles" if t[0] == "select" else _tool_help(t[3])
		b.button_pressed = t[0] == "select"
		b.pressed.connect(func() -> void:
			canvas.set_tool(t[0])
			preview.grab_focus())
		tool_buttons[t[0]] = b
		bar.add_child(b)
	snap_toggle = CheckBox.new()
	snap_toggle.text = "Snap %d" % roundi(canvas.grid)
	snap_toggle.focus_mode = Control.FOCUS_NONE
	snap_toggle.toggled.connect(func(on: bool) -> void: canvas.snap = on)
	bar.add_child(snap_toggle)
	materials_toggle = CheckBox.new()
	materials_toggle.text = "Materials"
	materials_toggle.tooltip_text = "Show the ground's materials as flat colours"
	materials_toggle.focus_mode = Control.FOCUS_NONE
	materials_toggle.toggled.connect(func(on: bool) -> void: gizmos.show_materials = on)
	bar.add_child(materials_toggle)
	return bar

static func _tool_help(how: String) -> String:
	match how:
		"circle":
			return "Click to place, or drag to set the radius"
		"rect":
			return "Click to place, or drag a rectangle"
		"polyline", "polygon":
			return "Click each point; Enter or double click finishes, Esc cancels"
	return "Click to place"

func _sync_tool_buttons() -> void:
	for id: String in tool_buttons:
		(tool_buttons[id] as Button).set_pressed_no_signal(id == canvas.tool)

func _on_canvas_select(path: Variant) -> void:
	if path == null:
		selected = null
		_rebuild_outline()
		_show_selection()
	else:
		_select_path(path)
	_sync_tool_buttons()

func preview_fit(world: bool) -> void:
	if world:
		preview.fit_world()
	else:
		preview.fit_frame()

func _process(_delta: float) -> void:
	if record_job != null and record_job.is_running():
		record_job.poll()
		_update_status()
	if run_pid > 0 and not OS.is_process_running(run_pid):
		run_pid = -1
		_update_status()
	if _screenshot_frames < 0 or preview.rebuild_pending() or play.seeking():
		return
	if record_job != null and record_job.stage == RecordJob.Stage.RECORDING and record_job.frames_done < 60:
		return
	_screenshot_frames -= 1
	if _screenshot_frames < 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("Saved screenshot %s (%dx%d)" % [_screenshot_path, img.get_width(), img.get_height()])
		if record_job != null:
			record_job.cancel()
		get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_then(_quit)

## Quits, asking first whether to cancel a running recording (the interactive
## run is a separate program and keeps running).
func _quit() -> void:
	if record_job != null and record_job.is_running():
		_quit_confirm.popup_centered()
		return
	get_tree().quit()

# --- documents ------------------------------------------------------------------

## A new document from a minimal template: one colony of the first species.
func _new_doc() -> void:
	var species: Array = registry.species.keys()
	species.sort()
	var data := {"name": "untitled", "description": "", "seed": 1, "duration": 20,
			"colonies": [{"species": species[0] if not species.is_empty() else "", "nest": [540, 1500]}],
			"food": [], "obstacles": []}
	_set_doc(ScenarioDoc.new(data, schema))

func _open(path: String) -> void:
	if not FileAccess.file_exists(path):
		_show_message("Can't open %s: no such file" % path)
		return
	var data := ScenarioJson.load_file(path)
	if data.is_empty():
		_show_message("Can't open %s: not a scenario JSON object" % path)
		return
	var d := ScenarioDoc.new(data, schema)
	d.file_path = path
	_set_doc(d)
	_remember(path)

func _set_doc(d: ScenarioDoc) -> void:
	doc = d
	doc.changed.connect(_on_doc_changed)
	selected = null
	canvas.doc = doc
	canvas.schema = schema
	canvas.set_tool("select")
	canvas.set_selection(null)
	_sync_tool_buttons()
	inspector.setup(doc, schema)
	play.stop()
	timeline.setup(doc, play)
	_rebuild_outline()
	_show_selection()
	preview.show_data(doc.data, true)
	preview.fit_world()
	_update_title()

## Saves (Save As if the document has no file yet). True if saved.
func _save() -> bool:
	if doc.file_path == "":
		_ask_file(true)
		return false
	return _save_to(doc.file_path)

func _save_to(path: String) -> bool:
	var err := doc.save(path)
	if err != OK:
		_show_message("Can't save %s: %s" % [path, error_string(err)])
		return false
	_remember(path)
	_update_title()
	return true

## Puts `path` first in the recent files.
func _remember(path: String) -> void:
	recent.add(path)
	recent.save_to(settings_path)
	_refresh_recent()

func _on_doc_changed(path: Array) -> void:
	_rebuild_outline()
	if selected != null and not (doc.has_at(selected) or (selected as Array).is_empty()):
		# The selected item was removed (or undone away).
		selected = null
		_show_selection()
	else:
		_update_selection_bounds()
		inspector.on_doc_changed(path)
	canvas.set_selection(selected)
	# Editing stops play: back to the static preview.
	play.stop()
	timeline.selected = selected
	preview.show_data(doc.data)
	# changed() comes before UndoRedo counts the action (is_dirty() is still
	# the old answer), so the title waits for the end of the frame.
	_update_title.call_deferred()

## Runs `action` now, or after the user saves or discards unsaved changes.
func _confirm_then(action: Callable) -> void:
	if doc == null or not doc.is_dirty():
		action.call()
		return
	_after_confirm = action
	_confirm.dialog_text = "Save changes to %s?" % _doc_name()
	_confirm.popup_centered()

func _run_after_confirm() -> void:
	var action := _after_confirm
	_after_confirm = Callable()
	if action.is_valid():
		action.call()

func _ask_file(save: bool) -> void:
	_saving_as = save
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Save scenario as" if save else "Open scenario"
	var dir := doc.file_path.get_base_dir() if doc != null and doc.file_path != "" else SCENARIO_DIR
	_file_dialog.current_dir = ProjectSettings.globalize_path(dir)
	if save:
		_file_dialog.current_file = str(doc.data.get("name", "untitled")) + ".json" if doc.file_path == "" \
				else doc.file_path.get_file()
	_file_dialog.popup_centered()

func _on_file_chosen(path: String) -> void:
	path = _localize(path)
	if _saving_as:
		if _save_to(path):
			_run_after_confirm()
	else:
		_open(path)

## A path inside the project as res://, others unchanged.
static func _localize(path: String) -> String:
	var local := ProjectSettings.localize_path(path)
	return local if local.begins_with("res://") else path

# --- menus ----------------------------------------------------------------------

func _on_file_menu(id: int) -> void:
	match id:
		FileItem.NEW:
			_confirm_then(_new_doc)
		FileItem.OPEN:
			_confirm_then(_ask_file.bind(false))
		FileItem.SAVE:
			_check_then("Save", _save)
		FileItem.SAVE_AS:
			_check_then("Save", _ask_file.bind(true))
		FileItem.REVERT:
			if doc.file_path != "":
				_confirm_then(_open.bind(doc.file_path))
		FileItem.QUIT:
			_confirm_then(_quit)

func _on_edit_menu(id: int) -> void:
	if id == EditItem.UNDO:
		doc.undo()
	else:
		doc.redo()
	_update_title()

func _refresh_recent() -> void:
	_recent_menu.clear()
	for p: String in recent.files:
		_recent_menu.add_item(p)
	if recent.files.is_empty():
		_recent_menu.add_item("(none)")
		_recent_menu.set_item_disabled(0, true)

func _on_recent(index: int) -> void:
	if index < recent.files.size():
		_confirm_then(_open.bind(recent.files[index]))

# --- outline and selection ------------------------------------------------------------

func _rebuild_outline() -> void:
	_building_outline = true
	rows = EditorOutline.build(doc.data)
	outline.clear()
	var root := outline.create_item()
	var parents: Array[TreeItem] = [root]
	var select_row := EditorOutline.row_for(rows, selected) if selected != null else -1
	for i: int in rows.size():
		var row := rows[i]
		var depth: int = row["depth"]
		parents.resize(depth + 1)
		var item := outline.create_item(parents[depth])
		item.set_text(0, row["label"])
		item.set_metadata(0, i)
		parents.append(item)
		if i == select_row:
			item.select(0)
	_building_outline = false
	_mark_outline()

func _on_outline_selected() -> void:
	if _building_outline:
		return
	var item := outline.get_selected()
	if item == null:
		return
	selected = rows[int(item.get_metadata(0))]["path"]
	_show_selection()

## Selects the outline row for `path` (the deepest row containing it).
func _select_path(path: Array) -> void:
	var i := EditorOutline.row_for(rows, path)
	selected = rows[i]["path"] if i >= 0 else null
	_rebuild_outline()
	_show_selection()

func _show_selection() -> void:
	_update_selection_bounds()
	inspector.show_path(selected)
	canvas.set_selection(selected)
	timeline.selected = selected
	timeline.canvas.queue_redraw()

## Shows the play view (true) or the static preview.
func _show_play(on: bool) -> void:
	play.visible = on
	preview.visible = not on

## The inspector's title and the preview's selection outline.
func _update_selection_bounds() -> void:
	var i := EditorOutline.row_for(rows, selected) if selected != null else -1
	# An absent section the outline lists (World, Output, Ground) is still a selection.
	var listed: bool = i >= 0 and rows[i]["path"] == selected
	if selected == null or not (doc.has_at(selected) or (selected as Array).is_empty() or listed):
		preview.selection = Rect2()
		details_title.text = "Nothing selected"
		return
	var path: Array = selected
	details_title.text = rows[i]["label"] if i >= 0 else "/".join(path)
	var ip: Variant = CanvasEditor.item_of(doc.data, path)
	preview.selection = GizmoGeometry.item_bounds(doc.data, ip) if ip != null else Rect2()

# --- adding items -----------------------------------------------------------------

func _fill_add_menu() -> void:
	_add_actions = EditorDefaults.add_actions(doc.data, selected if selected != null else [])
	var popup := add_menu.get_popup()
	popup.clear()
	for a: Dictionary in _add_actions:
		popup.add_item(a["label"])

## Runs an "Add ..." action (EditorDefaults.add_actions): appends a new item at
## the centre of the preview's view and selects it.
func add_item(action: Dictionary) -> void:
	var item: Variant = EditorDefaults.new_item(action["id"], doc.data, schema, preview.to_world(preview.size / 2.0))
	if item == null:
		return
	_select_path(CanvasEditor.insert_new(doc, action["list"], item, action["label"]))

## Handle tolerance in world units.
func _tolerance() -> float:
	return HANDLE_TOLERANCE / preview.camera.zoom.x

## Left button and mouse motion go to the canvas editor, and (with the preview
## focused) Delete, Ctrl+D, Enter and Esc.
func _on_preview_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var at := preview.to_world(mb.position)
		if mb.pressed:
			canvas.press(at, _tolerance(), mb.alt_pressed, mb.double_click)
		else:
			canvas.release(at, _tolerance())
		_sync_tool_buttons()
		preview.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		canvas.motion(preview.to_world(mm.position), _tolerance())
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var handled := true
	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			handled = canvas.delete_selected()
		KEY_D:
			handled = key.ctrl_pressed and canvas.duplicate_selected()
		KEY_ENTER, KEY_KP_ENTER:
			handled = canvas.finish_poly()
			_sync_tool_buttons()
		KEY_ESCAPE:
			# Drops what is being placed, or else the place tool.
			if canvas.poly_points.is_empty() and canvas.span.is_empty():
				canvas.set_tool("select")
			canvas.cancel()
			_sync_tool_buttons()
		_:
			handled = false
	if handled:
		preview.accept_event()

# --- run and record ---------------------------------------------------------------

func _on_run_menu(id: int) -> void:
	match id:
		RunItem.RUN:
			_check_then("Run", run)
		RunItem.STOP:
			stop_run()
		RunItem.OPTIONS:
			run_dialog.open(LaunchSettings.load_for(settings_path, "run", doc.file_path, LaunchCommands.RUN_DEFAULTS),
					OutputFrame.from_scenario(doc.data).size, timeline.playhead)
		RunItem.RECORD:
			if record_job != null and record_job.is_running():
				open_record()
			else:
				_check_then("Record", open_record)

## The name of the document's temporary copies, and so of its recordings: the
## file's name, else the scenario's "name", else "untitled".
func run_name() -> String:
	if doc.file_path != "":
		return LaunchCommands.scenario_name(doc.file_path)
	var n := str(doc.data.get("name", "")).validate_filename().replace(" ", "_")
	return n if n != "" else "untitled"

## Writes the document as it is now to runs_dir/<kind>/<name>.json and returns
## that file's absolute path ("" if it can't be written). The saved file is not
## touched.
func write_run_copy(kind: String) -> String:
	var dir := ProjectSettings.globalize_path(runs_dir.path_join(kind))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(run_name() + ".json")
	var err := ScenarioJson.save_file(path, doc.data)
	if err != OK:
		_show_message("Can't write %s: %s" % [path, error_string(err)])
		return ""
	return path

## Starts the interactive player (main.tscn) on the document with the Run
## options, stopping the previous run.
func run() -> void:
	var path := write_run_copy("run")
	if path == "":
		return
	stop_run()
	var s := LaunchSettings.load_for(settings_path, "run", doc.file_path, LaunchCommands.RUN_DEFAULTS)
	var exe := godot_path if godot_path != "" else OS.get_executable_path()
	var pid: int = launch_process.call(exe, LaunchCommands.run_args(s, path, project_dir, timeline.playhead,
			randi() % 1000000))
	if pid <= 0:
		_show_message("Can't start %s" % exe)
		return
	run_pid = pid
	_update_status()

func stop_run() -> void:
	if run_pid > 0 and OS.is_process_running(run_pid):
		OS.kill(run_pid)
	run_pid = -1
	_update_status()

## Shows the recording in progress, or the Record settings.
func open_record() -> void:
	if record_job != null and record_job.is_running():
		record_dialog.show_job(record_job)
		record_dialog.popup_centered()
		return
	record_dialog.open(LaunchSettings.load_for(settings_path, "record", doc.file_path, LaunchCommands.RECORD_DEFAULTS),
			write_run_copy("record"), doc.data, project_dir)

## Records the document with `settings` (RecordDialog). `set_output` first makes
## the chosen frame size the scenario's output size (an undoable edit).
## Returns the job (it may have failed to start; see its stage and message), or
## null if the document couldn't be written.
func start_recording(settings: Dictionary, set_output: bool = false) -> RecordJob:
	if record_job != null and record_job.is_running():
		_show_message("A recording is already running")
		return record_job
	LaunchSettings.save_for(settings_path, "record", doc.file_path, settings)
	var s := settings.duplicate()
	if set_output and str(s.get("size", "")) != "":
		var size := OutputFrame.parse_size(str(s["size"]))
		doc.set_at(["output", "size"], [size.x, size.y])
		s["size"] = ""
	var path := write_run_copy("record")
	if path == "":
		return null
	var job := RecordJob.new()
	record_job = job
	job.start(LaunchCommands.record_plan(s, path, doc.data, project_dir,
			LaunchCommands.stamp(Time.get_datetime_dict_from_system())), project_dir, godot_path)
	record_dialog.show_job(job)
	_update_status()
	return job

# --- validation -------------------------------------------------------------------

const ISSUE_COLORS := {ScenarioValidator.ERROR: Color(1.0, 0.42, 0.42), ScenarioValidator.WARNING: Color(1.0, 0.75, 0.3)}

## Validates the document (with the preview's sim for the scene checks) and
## shows the result: the problems list, outline colours and preview marks.
func validate() -> void:
	if doc == null:
		return
	issues = ScenarioValidator.validate(doc.data, schema, preview.sim)
	# Errors first, then in document order.
	var ordered: Array[Dictionary] = []
	for sev: String in [ScenarioValidator.ERROR, ScenarioValidator.WARNING]:
		ordered.append_array(issues.filter(func(i: Dictionary) -> bool: return i["severity"] == sev))
	issues = ordered
	problems.clear()
	for k: int in issues.size():
		var i: Dictionary = issues[k]
		var n := problems.add_item(ScenarioValidator.format(i).strip_edges())
		problems.set_item_metadata(n, k)
		problems.set_item_custom_fg_color(n, ISSUE_COLORS[i["severity"]])
		problems.set_item_tooltip(n, i["message"])
	problems_title.text = "Problems: " + (ScenarioValidator.summary(issues) if not issues.is_empty() else "none")
	_mark_outline()
	_mark_preview()

## Colours the outline rows holding issues (and their sections), with the
## messages as the row's tooltip.
func _mark_outline() -> void:
	if outline.get_root() == null:
		return
	var items := {}
	var stack: Array[TreeItem] = [outline.get_root()]
	while not stack.is_empty():
		var t: TreeItem = stack.pop_back()
		for c: TreeItem in t.get_children():
			items[int(c.get_metadata(0))] = c
			stack.append(c)
	var worst := {}
	var tips := {}
	for i: Dictionary in issues:
		var r := EditorOutline.row_for(rows, i["path"])
		if r < 0 or not items.has(r):
			continue
		tips[r] = (tips.get(r, "") + "\n" if tips.has(r) else "") + str(i["message"])
		var t: TreeItem = items[r]
		while t != null and t != outline.get_root():
			var row := int(t.get_metadata(0))
			if worst.get(row, "") != ScenarioValidator.ERROR:
				worst[row] = i["severity"]
			t = t.get_parent()
	for r: int in items:
		var t: TreeItem = items[r]
		if worst.has(r):
			t.set_custom_color(0, ISSUE_COLORS[worst[r]])
		else:
			t.clear_custom_color(0)
		t.set_tooltip_text(0, tips.get(r, ""))

## Outlines the items with issues in the preview.
func _mark_preview() -> void:
	var by_item := {}
	for i: Dictionary in issues:
		var ip: Variant = CanvasEditor.item_of(doc.data, i["path"])
		if ip == null:
			continue
		if by_item.get(ip, "") != ScenarioValidator.ERROR:
			by_item[ip] = i["severity"]
	var marks: Array = []
	for ip: Array in by_item:
		var r := GizmoGeometry.item_bounds(doc.data, ip)
		if r.has_area():
			marks.append([r, ISSUE_COLORS[by_item[ip]]])
	preview.issue_marks = marks

## Runs `action` now, or after the user confirms it despite errors.
func _check_then(verb: String, action: Callable) -> void:
	validate()
	var errors := issues.filter(func(i: Dictionary) -> bool: return i["severity"] == ScenarioValidator.ERROR)
	if errors.is_empty():
		action.call()
		return
	var lines: PackedStringArray = []
	for i: Dictionary in errors.slice(0, 6):
		lines.append(ScenarioValidator.format(i).strip_edges())
	if errors.size() > 6:
		lines.append("... and %d more" % (errors.size() - 6))
	_after_warn = action
	_warn.dialog_text = "The scenario has %s:\n\n%s\n\n%s anyway?" % [ScenarioValidator.summary(issues),
			"\n".join(lines), verb]
	_warn.ok_button_text = verb + " anyway"
	_warn.popup_centered()

# --- layout ---------------------------------------------------------------------

## Split offsets from the "layout" section of the settings file; each split
## saves its offset when dragged.
func _restore_layout() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(settings_path) == OK
	for key: String in _splits:
		var s: SplitContainer = _splits[key]
		if loaded and cfg.has_section_key("layout", key):
			s.split_offset = int(cfg.get_value("layout", key))
		s.dragged.connect(func(_offset: int) -> void: _save_layout())

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # a missing file just starts empty
	for key: String in _splits:
		cfg.set_value("layout", key, (_splits[key] as SplitContainer).split_offset)
	cfg.save(settings_path)

# --- status ---------------------------------------------------------------------

func _doc_name() -> String:
	return doc.file_path.get_file() if doc.file_path != "" else "untitled (not saved)"

func _update_title() -> void:
	if manage_window:
		get_window().title = "Scenario editor - %s%s" % [_doc_name(), " *" if doc.is_dirty() else ""]
	_update_status()

func _update_status() -> void:
	if doc == null:
		return
	status.text = "  %s%s   |   %s" % [doc.file_path if doc.file_path != "" else "not saved",
			" (modified)" if doc.is_dirty() else "", preview.status]
	if run_pid > 0:
		status.text += "   |   Running (pid %d)" % run_pid
	if record_job != null and record_job.stage != RecordJob.Stage.IDLE:
		var text := record_job.status_text()
		if record_job.is_running() and record_job.frames_total > 0:
			text += " (%d%%)" % roundi(record_job.fraction() * 100.0)
		status.text += "   |   " + text

func _show_message(text: String) -> void:
	push_warning(text)
	_message.dialog_text = text
	_message.popup_centered()

# --- arguments ------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif a.begins_with("--"):
			out[a.substr(2)] = ""
	return out

## "colonies/0" -> ["colonies", 0] (--select= for screenshots).
static func _parse_path(text: String) -> Array:
	var out: Array = []
	for part: String in text.split("/", false):
		out.append(int(part) if part.is_valid_int() else part)
	return out
