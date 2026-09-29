extends TestCase
## M16c: the scenario editor scene and its static preview (EditorPreview):
## the output frame's place in the world, fitting, the debounced rebuild,
## and the editor opening, editing, saving and reverting documents headless.
## The outline model is tested in test_editor_outline.gd.

const EDITOR := preload("res://scenes/editor.tscn")
const TEMP_DIR := "user://test_editor"

var _world := Vector2(1080, 1920)

func test_fit_zoom() -> void:
	check_eq(EditorPreview.fit_zoom(Rect2(0, 0, 1080, 1920), Vector2(540, 960)), 0.5, "whole world in half size")
	check_eq(EditorPreview.fit_zoom(Rect2(0, 0, 100, 100), Vector2(400, 200)), 2.0, "limited by height")
	check_eq(EditorPreview.fit_zoom(Rect2(0, 0, 100, 100), Vector2(220, 220), 10.0), 2.0, "margin")
	check_eq(EditorPreview.fit_zoom(Rect2(), Vector2(200, 200)), 1.0, "empty rect")

func test_frame_rect_default_is_the_world() -> void:
	var r := EditorPreview.frame_world_rect({}, OutputFrame.new(), _world)
	check_eq(r, Rect2(0, 0, 1080, 1920), "no camera: default frame over the world at zoom 1")

func test_frame_rect_first_keyframe() -> void:
	var data := {"camera": [{"t": 5, "pos": [0, 0], "zoom": 4}, {"t": 0, "pos": [300, 400], "zoom": 2}]}
	var r := EditorPreview.frame_world_rect(data, OutputFrame.new(), _world)
	check_eq(r, Rect2(300 - 270, 400 - 480, 540, 960), "earliest keyframe's pos, frame / zoom")

func test_frame_rect_follow_and_tracks() -> void:
	var data := {"camera": {"surface": [{"t": 0, "follow": {"near": [500, 600]}, "zoom": 1}], "nest": []}}
	var r := EditorPreview.frame_world_rect(data, OutputFrame.new(Vector2i(1920, 1080)), _world)
	check_eq(r, Rect2(500 - 960, 600 - 540, 1920, 1080), "surface track, follow near, landscape frame")

func test_frame_rect_fit_shows_world() -> void:
	var data := {"camera": [{"t": 0, "fit": "excavation"}]}
	var r := EditorPreview.frame_world_rect(data, OutputFrame.new(Vector2i(1080, 1080)), _world)
	check(r.encloses(Rect2(Vector2.ZERO, _world).grow(-1)), "fit keyframe frames the whole world")

func test_preview_builds_and_debounces() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var preview := EditorPreview.new()
	preview.size = Vector2(800, 600)
	tree.root.add_child(preview)
	var data := ScenarioJson.load_file(ScenarioLoader.path_for("basic_forage"))
	preview.show_data(data, true)
	check(preview.sim != null and preview.view != null, "built")
	check(preview.status.begins_with("Built in"), "status: " + preview.status)
	check_eq(preview.sim.tick_count, 0, "not stepped")
	var first := preview.sim
	preview.show_data(data)
	check(preview.rebuild_pending(), "rebuild waits")
	check(preview.sim == first, "not rebuilt yet")
	preview._process(EditorPreview.REBUILD_DELAY + 0.01)
	check(not preview.rebuild_pending() and preview.sim != first, "rebuilt after the delay")
	preview.fit_world()
	check(absf(preview.camera.zoom.x - EditorPreview.fit_zoom(Rect2(Vector2.ZERO, _world), preview.size, 24.0)) < 1e-4,
			"fit world zoom")
	preview.size = Vector2(1600, 1200)
	check(absf(preview.camera.zoom.x - EditorPreview.fit_zoom(Rect2(Vector2.ZERO, _world), preview.size, 24.0)) < 1e-4,
			"refitted after a resize")
	var local := Vector2(123, 45)
	var before := preview.to_world(local)
	preview.zoom_about(local, 2.0)
	check(preview.to_world(local).distance_to(before) < 1e-3, "zoom keeps the point under the cursor")
	preview.free()

## A directory of this test's own (tests run in parallel processes).
func _dir() -> String:
	var dir := TEMP_DIR.path_join(current_test.get_slice("::", 1))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

func _editor(scenario: String) -> ScenarioEditor:
	var ed: ScenarioEditor = EDITOR.instantiate()
	ed.manage_window = false
	ed.settings_path = _dir().path_join("settings.cfg")
	if scenario != "":
		ed.args = {"scenario": scenario}
	(Engine.get_main_loop() as SceneTree).root.add_child(ed)
	return ed

func _cleanup(ed: ScenarioEditor) -> void:
	ed.free()
	var dir := _dir()
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func test_editor_opens_a_scenario() -> void:
	var ed := _editor("basic_forage")
	check_eq(ed.doc.file_path, "res://scenarios/basic_forage.json", "file path")
	check(not ed.doc.is_dirty(), "clean after open")
	check(ed.preview.sim != null, "preview built")
	check(ed.rows.size() > 4, "outline rows")
	check_eq(ed.outline.get_root().get_child_count(), EditorOutline.build(ed.doc.data).filter(
			func(r: Dictionary) -> bool: return r["depth"] == 0).size(), "a tree item per section")
	check_eq(ed.recent.files[0], "res://scenarios/basic_forage.json", "remembered as recent")
	_cleanup(ed)

func test_editor_new_document_builds() -> void:
	var ed := _editor("")
	check_eq(ed.doc.file_path, "", "not saved")
	check_eq((ed.doc.data["colonies"] as Array).size(), 1, "template colony")
	check(ed.preview.sim != null and ed.preview.sim.colonies.size() == 1, "template builds")
	_cleanup(ed)

func test_editor_select_and_click() -> void:
	var ed := _editor("basic_forage")
	ed._select_path(["food", 1, "amount"])
	check_eq(ed.selected, ["food", 1], "deep path selects its item")
	check(ed.preview.selection.has_point(Vector2(820, 800)), "selection outline around the food")
	check(ed.details.text.contains("food_pile"), "details show the item")
	# A click at the nest selects the colony.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ed.preview.camera.position = Vector2(540, 1500)
	click.position = ed.preview.size / 2.0
	ed._on_preview_input(click)
	check_eq(ed.selected, ["colonies", 0], "click on the nest")
	_cleanup(ed)

func test_editor_edit_save_revert() -> void:
	var src := ScenarioLoader.path_for("basic_forage")
	var path := _dir().path_join("edited.json")
	var copy := FileAccess.open(path, FileAccess.WRITE)
	copy.store_string(FileAccess.get_file_as_string(src))
	copy.close()
	var ed := _editor(path)
	var original := FileAccess.get_file_as_string(path)
	# Open -> save unchanged gives the same bytes.
	check(ed._save(), "saved")
	check_eq(FileAccess.get_file_as_string(path), original, "unedited save is byte-identical")
	ed.doc.set_at(["food", 0, "amount"], 123)
	check(ed.doc.is_dirty(), "dirty after an edit")
	check(ed.preview.rebuild_pending(), "edit schedules a rebuild")
	ed._update_title()  # deferred in the app
	check(ed.status.text.contains("modified"), "status shows modified")
	check(ed._save(), "saved again")
	check(not ed.doc.is_dirty(), "clean after save")
	check_eq(int(ScenarioJson.load_file(path)["food"][0]["amount"]), 123, "edit saved")
	ed.doc.set_at(["food", 0, "amount"], 7)
	# Revert (confirmed as "discard") reloads the file.
	ed._confirm_then(ed._open.bind(path))
	ed._confirm.custom_action.emit(&"discard")
	check(not ed.doc.is_dirty(), "reverted")
	check_eq(int(ed.doc.get_at(["food", 0, "amount"])), 123, "value from the file")
	# Undo/redo through the Edit menu.
	ed.doc.set_at(["seed"], 9)
	ed._on_edit_menu(ScenarioEditor.EditItem.UNDO)
	check_eq(int(ed.doc.data["seed"]), 1, "undo")
	ed._on_edit_menu(ScenarioEditor.EditItem.REDO)
	check_eq(int(ed.doc.data["seed"]), 9, "redo")
	_cleanup(ed)

func test_editor_open_missing_keeps_document() -> void:
	var ed := _editor("basic_forage")
	var before: ScenarioDoc = ed.doc
	ed._open("res://scenarios/does_not_exist.json")
	check(ed.doc == before, "document kept")
	_cleanup(ed)
