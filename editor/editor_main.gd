class_name ScenarioEditor
extends Control
## The scenario editor (scenes/editor.tscn): opens a scenario JSON as a
## ScenarioDoc, shows it as an outline (left), a static preview built by the
## real loader and renderers (centre, EditorPreview) and the selected item
## (right; the full inspector comes in M16d), and saves it back with
## ScenarioJson.
##
##   godot --path . res://scenes/editor.tscn [-- --scenario=<name or path>] [--screenshot=<path>]
##   tools/editor.sh [--scenario=...]
##
## File menu: New (a minimal template), Open, Open Recent (kept in
## user://editor_settings.cfg), Save, Save As, Revert, Quit; unsaved changes
## are confirmed before New, Open, Revert and closing the window.
## Edit menu: Undo / Redo (doc commands). View: fit world, fit output frame.
## Clicking in the preview selects the smallest item there; wheel zooms,
## middle or right drag pans.

const WINDOW_SIZE := Vector2i(1600, 900)
const SCENARIO_DIR := "res://scenarios"

enum FileItem { NEW, OPEN, SAVE, SAVE_AS, REVERT, QUIT }
enum EditItem { UNDO, REDO }
enum ViewItem { FIT_WORLD, FIT_FRAME }

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
var outline: Tree
var details: TextEdit
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
	else:
		_new_doc()
	_screenshot_path = str(args.get("screenshot", ""))
	if _screenshot_path != "":
		_screenshot_frames = 5
		var select := str(args.get("select", ""))
		if select != "":
			_select_path(_parse_path(select))

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
	for label: String in ["Fit world", "Fit frame"]:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(preview_fit.bind(label == "Fit world"))
		bar.add_child(b)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	outline = Tree.new()
	outline.custom_minimum_size = Vector2(300, 0)
	outline.hide_root = true
	outline.item_selected.connect(_on_outline_selected)
	split.add_child(outline)

	var right := HSplitContainer.new()
	split.add_child(right)
	preview = EditorPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.status_changed.connect(func(_t: String) -> void: _update_status())
	preview.gui_input.connect(_on_preview_input)
	right.add_child(preview)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	right.add_child(side)
	details_title = Label.new()
	side.add_child(details_title)
	details = TextEdit.new()
	details.editable = false
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_override("font", SystemFont.new())
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	side.add_child(details)

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
	_refresh_recent()

func preview_fit(world: bool) -> void:
	if world:
		preview.fit_world()
	else:
		preview.fit_frame()

func _process(_delta: float) -> void:
	if _screenshot_frames < 0 or preview.rebuild_pending():
		return
	_screenshot_frames -= 1
	if _screenshot_frames < 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("Saved screenshot %s (%dx%d)" % [_screenshot_path, img.get_width(), img.get_height()])
		get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_then(func() -> void: get_tree().quit())

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

func _on_doc_changed(_path: Array) -> void:
	_rebuild_outline()
	_show_selection()
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
			_save()
		FileItem.SAVE_AS:
			_ask_file(true)
		FileItem.REVERT:
			if doc.file_path != "":
				_confirm_then(_open.bind(doc.file_path))
		FileItem.QUIT:
			_confirm_then(func() -> void: get_tree().quit())

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
	if selected == null or not (doc.has_at(selected) or (selected as Array).is_empty()):
		preview.selection = Rect2()
		details_title.text = "Nothing selected"
		details.text = ""
		return
	var path: Array = selected
	var i := EditorOutline.row_for(rows, path)
	details_title.text = rows[i]["label"] if i >= 0 else "/".join(path)
	preview.selection = EditorOutline.item_bounds(doc.data, path)
	var value: Variant = doc.get_at(path)
	if path.is_empty():
		# The scenario's own settings, not the whole file.
		var general := {}
		for k: String in doc.data:
			if not doc.data[k] is Dictionary and not doc.data[k] is Array:
				general[k] = doc.data[k]
		value = general
	details.text = ScenarioJson.stringify(value) if value is Dictionary else ScenarioJson.inline(value)

## Left click in the preview selects the smallest item whose bounds contain it.
func _on_preview_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var at := preview.to_world(mb.position)
	var best: Variant = null
	var best_area := INF
	for row: Dictionary in rows:
		if int(row["depth"]) == 0:
			continue
		var r := EditorOutline.item_bounds(doc.data, row["path"])
		if r.has_area() and r.has_point(at) and r.get_area() < best_area:
			best_area = r.get_area()
			best = row["path"]
	if best != null:
		_select_path(best)

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
	return out

## "colonies/0" -> ["colonies", 0] (--select= for screenshots).
static func _parse_path(text: String) -> Array:
	var out: Array = []
	for part: String in text.split("/", false):
		out.append(int(part) if part.is_valid_int() else part)
	return out
