extends TestCase
## M16g: the editor's timeline panel (TimelinePanel: select, drag, resize, add,
## delete, playhead) and play preview (EditorPlay: runs as a recording does,
## seeks forward and back), and both inside the editor scene.

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root

func _data() -> Dictionary:
	return {"duration": 20, "colonies": [], "food": [],
		"ticks_per_frame": [{"t": 0, "tpf": 1}, {"t": 10, "tpf": 2}],
		"camera": [{"t": 0, "pos": [540, 960], "zoom": 1}],
		"render": {"captions": [{"t": 2, "until": 6, "text": "Hello"}]},
		"events": [{"t": 30, "type": "rain", "duration": 6}]}

## A panel on `data`, 1000 px wide, fitted to the duration.
func _panel(data: Dictionary) -> TimelinePanel:
	var panel := TimelinePanel.new()
	_root().add_child(panel)
	panel.setup(ScenarioDoc.new(data), EditorPlay.new())
	panel.canvas.size = Vector2(1000, 260)
	panel.fit_view()
	return panel

func _free(panel: TimelinePanel) -> void:
	panel.play.free()
	panel.queue_free()

func _row_y(panel: TimelinePanel, id: String) -> float:
	for r in panel.tracks.size():
		if panel.tracks[r]["id"] == id:
			return TimelinePanel.RULER_H + (r + 0.5) * TimelinePanel.ROW_H
	return -1.0

func test_panel_tracks_and_ruler() -> void:
	var panel := _panel(_data())
	check_eq(panel.tracks.size(), 8, "tracks")
	check_eq(panel.row_of(5.0), -1, "ruler")
	check_eq(panel.row_of(_row_y(panel, "captions")), 3, "captions row")
	check(absf(panel.t_of(panel.x_of(7.3)) - 7.3) < 1e-4, "x <-> t")
	# The rain at sim 30 s is at video 10 s (tpf ramps 1 -> 2 over 10 s: 15 frames' ticks per s... 30 s).
	var ev: Dictionary = panel.track("events")["items"][0]
	check(absf(float(ev["t"]) - 10.0) < 1e-3, "event at video 10: %s" % ev["t"])
	check(panel.press(Vector2(panel.x_of(5.0), 5.0)), "ruler press")
	panel.release(Vector2(panel.x_of(5.0), 5.0))
	check(absf(panel.playhead - 5.0) < 1e-6, "playhead %s" % panel.playhead)
	_free(panel)

func test_panel_drag_caption_one_undo_step() -> void:
	var panel := _panel(_data())
	var picked: Array = []
	panel.select_requested.connect(func(p: Variant) -> void: picked.append(p))
	var y := _row_y(panel, "captions")
	check(panel.press(Vector2(panel.x_of(4.0), y)), "pressed")
	check_eq(picked.back(), ["render", "captions", 0], "selected")
	panel.motion(Vector2(panel.x_of(5.5), y))
	check_eq(panel.doc.get_at(["render", "captions", 0, "t"]), 2, "not written while dragging")
	panel.release(Vector2(panel.x_of(7.0), y))
	check_eq(panel.doc.get_at(["render", "captions", 0]), {"t": 5, "until": 9, "text": "Hello"}, "moved, same length")
	panel.doc.undo()
	check_eq(panel.doc.get_at(["render", "captions", 0]), {"t": 2, "until": 6, "text": "Hello"}, "one undo step")
	_free(panel)

func test_panel_resize_span() -> void:
	var panel := _panel(_data())
	var y := _row_y(panel, "captions")
	panel.press(Vector2(panel.x_of(6.0), y))
	panel.release(Vector2(panel.x_of(12.0), y))
	check_eq(panel.doc.get_at(["render", "captions", 0, "until"]), 12, "until dragged")
	check_eq(panel.doc.get_at(["render", "captions", 0, "t"]), 2, "t kept")
	_free(panel)

func test_panel_drag_event_in_video_time() -> void:
	var panel := _panel(_data())
	var y := _row_y(panel, "events")
	panel.press(Vector2(panel.x_of(10.0), y))
	panel.release(Vector2(panel.x_of(5.0), y))
	# Video 5 s at tpf 1 -> 1.5: 2 * (5 + 0.25 * 25 / 10) = 11.25 sim s.
	var t := float(panel.doc.get_at(["events", 0, "t"]))
	check(absf(t - panel.map.sim_time_at(5.0)) < 0.011, "event sim t %s" % t)
	_free(panel)

func test_panel_add_and_delete() -> void:
	var panel := _panel(_data())
	var picked: Array = []
	panel.select_requested.connect(func(p: Variant) -> void: picked.append(p))
	var y := _row_y(panel, "captions")
	panel.press(Vector2(panel.x_of(15.0), y), true)
	check_eq((panel.doc.get_at(["render", "captions"]) as Array).size(), 2, "caption added")
	check_eq(picked.back(), ["render", "captions", 1], "new one selected")
	check_eq(panel.doc.get_at(["render", "captions", 1, "t"]), 15, "at the click")
	# A list that doesn't exist yet (fades) and the camera key from key_here.
	panel.press(Vector2(panel.x_of(3.0), _row_y(panel, "fades")), true)
	check_eq(panel.doc.get_at(["render", "fades"]), [{"t": 3, "to": 1}], "fades created")
	panel.key_here = func(t: float) -> Dictionary: return {"t": t, "pos": [100, 200], "zoom": 2}
	panel.add_at("camera", 8.0)
	check_eq(panel.doc.get_at(["camera", 1]), {"t": 8, "pos": [100, 200], "zoom": 2}, "key here")
	panel.selected = ["render", "captions", 1]
	check(panel.delete_selected(), "deleted")
	check_eq((panel.doc.get_at(["render", "captions"]) as Array).size(), 1, "caption removed")
	panel.selected = ["colonies"]
	check(not panel.delete_selected(), "not a timeline item")
	_free(panel)

# --- play preview ------------------------------------------------------------------------

func _forage() -> Dictionary:
	var data := ScenarioLoader.load_data("basic_forage")
	data["warmup"] = 0
	return data

func test_play_matches_a_recording_run() -> void:
	var play := EditorPlay.new()
	_root().add_child(play)
	check(play.load_data(_forage()), "loaded")
	play.seek(1.0)
	while play.seeking():
		play._process(0.016)
	check(absf(play.video_time() - 1.0) < 1e-6, "at 1 s: %s" % play.video_time())
	var ref := ScenarioPlayer.new()
	_root().add_child(ref)
	ref.setup_data(_forage())
	for f in 60:
		ref.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	check_eq(play.player.sim.state_hash(), ref.sim.state_hash(), "same run as frame-by-frame")
	check_eq(play.player.sim.tick_count, ref.sim.tick_count, "same ticks")
	# Back: a fresh build fast-forwarded.
	var first := play.player
	play.seek(0.5)
	check(play.player != first, "rebuilt")
	while play.seeking():
		play._process(0.016)
	check(absf(play.video_time() - 0.5) < 1e-6, "at 0.5 s")
	# Playing advances whole frames at `speed`.
	play.speed = 2.0
	play.play()
	play._process(0.1)
	check(absf(play.video_time() - 0.7) < 1.0 / 60.0 + 1e-6, "played 0.2 s: %s" % play.video_time())
	play.stop()
	check(not play.active(), "stopped")
	ref.queue_free()
	play.queue_free()

# --- in the editor ----------------------------------------------------------------------

func test_editor_timeline_play_and_edit_stops() -> void:
	var editor := ScenarioEditor.new()
	editor.manage_window = false
	editor.settings_path = "user://test_timeline_settings.cfg"
	editor.args = {"scenario": "basic_forage"}
	_root().add_child(editor)
	check(not editor.timeline.tracks.is_empty(), "timeline tracks")
	editor.timeline.toggle_play()
	check(editor.play.active() and editor.play.visible and not editor.preview.visible, "play view shown")
	editor.play._process(0.05)
	editor.doc.set_at(["duration"], 30)
	check(not editor.play.active(), "edit stops play")
	check(editor.preview.visible and not editor.play.visible, "static preview back")
	check_eq(editor.timeline.duration(), 30.0, "timeline refreshed")
	# Select a timeline item: the outline has a row for it.
	var at := editor.timeline.add_at("captions", 1.0)
	check_eq(editor.selected, at, "caption selected: %s" % [editor.selected])
	editor.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_timeline_settings.cfg"))
