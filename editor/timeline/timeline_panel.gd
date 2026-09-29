class_name TimelinePanel
extends VBoxContainer
## The editor's timeline (M16g, bottom panel): a video-time ruler with a row
## per TimelineModel track (camera keyframes, the ticks_per_frame curve with
## its time jumps, layout modes, captions, fades, grade, story marker windows
## and the sim-time events, converted to video time with the speed schedule
## so everything shares one ruler), a playhead, and the play transport.
##
## Click an item to select it (the outline and inspector follow), drag it to
## change its time ("t"; an event's sim time follows the video time it is
## dropped at), drag a span's right edge to change its "until". Double click
## an empty place on a row to add an item there (camera keys take the static
## preview's view, as "Key here" does). Delete removes the selected item. A
## drag writes the document once, on release. Times snap to 0.1 s (Shift:
## to video frames). Click or drag on the ruler to move the playhead (and
## seek the play preview). Wheel zooms the ruler about the cursor, middle
## drag pans it.
##
## Play runs the document in EditorPlay from the playhead; Stop returns to the
## static preview. Editing the document while playing stops play (the editor
## does that on doc.changed).

signal select_requested(path: Variant)
## Play started (true) or the run was dropped (false): the editor swaps the
## static preview and the play view.
signal play_view(on: bool)

const GUTTER := 130.0
const RULER_H := 22.0
const ROW_H := 22.0
const HANDLE_PX := 6.0
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const SELECT := Color(1.0, 0.85, 0.2)
const TRACK_COLORS := {
	"camera": Color(0.45, 0.75, 1.0), "camera_surface": Color(0.45, 0.75, 1.0),
	"camera_nest": Color(0.6, 0.6, 1.0), "speed": Color(0.5, 0.9, 0.5), "layout": Color(0.8, 0.6, 1.0),
	"captions": Color(1.0, 0.85, 0.6), "fades": Color(0.7, 0.7, 0.7), "grade": Color(1.0, 0.6, 0.4),
	"story_marker": Color(1.0, 0.5, 0.7), "events": Color(0.4, 0.9, 0.9),
}

var doc: ScenarioDoc
var config: SimConfig = preload("res://sim/default_config.tres")
var play: EditorPlay
var map: TimelineModel.TimeMap
var tracks: Array[Dictionary] = []
## Video time of the playhead.
var playhead := 0.0
## Selected document path (the editor's selection).
var selected: Variant = null
## Returns the extra keys of a new camera keyframe at video time t (the static
## preview's view); set by the editor.
var key_here: Callable
## Ruler: pixels per video second and the time at the left edge.
var pps := 10.0
var view_start := 0.0

var canvas: Control
var play_button: Button
var stop_button: Button
var speed_menu: OptionButton
var time_label: Label
var seek_bar: ProgressBar
var key_button: Button

## The drag in progress: {track, index, part, grab (mouse t - item t), item, value}.
var _drag: Dictionary = {}
var _scrubbing := false
var _panning := false
var _fitted := true

func _init() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	play_button = _button(bar, "Play", "Play the document from the playhead (Space with the timeline focused)")
	play_button.pressed.connect(toggle_play)
	stop_button = _button(bar, "Stop", "Back to the static preview")
	stop_button.pressed.connect(stop)
	speed_menu = OptionButton.new()
	speed_menu.focus_mode = Control.FOCUS_NONE
	for s: float in SPEEDS:
		speed_menu.add_item(("%sx" % s).replace(".0x", "x"))
	speed_menu.select(SPEEDS.find(1.0))
	speed_menu.item_selected.connect(func(i: int) -> void:
		if play != null:
			play.speed = SPEEDS[i])
	bar.add_child(speed_menu)
	time_label = Label.new()
	time_label.custom_minimum_size = Vector2(150, 0)
	bar.add_child(time_label)
	seek_bar = ProgressBar.new()
	seek_bar.custom_minimum_size = Vector2(160, 0)
	seek_bar.max_value = 1.0
	seek_bar.show_percentage = false
	seek_bar.visible = false
	bar.add_child(seek_bar)
	key_button = _button(bar, "Key here", "Add a camera keyframe at the playhead framing the static preview's view")
	key_button.pressed.connect(func() -> void: add_at(_camera_track_id(), playhead))
	var fit := _button(bar, "Fit", "Fit the ruler to the video's duration")
	fit.pressed.connect(func() -> void:
		_fitted = true
		fit_view())
	canvas = Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.focus_mode = Control.FOCUS_CLICK
	canvas.clip_contents = true
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)
	canvas.resized.connect(func() -> void:
		if _fitted:
			fit_view())
	add_child(canvas)

static func _button(bar: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	bar.add_child(b)
	return b

func setup(scenario_doc: ScenarioDoc, editor_play: EditorPlay) -> void:
	doc = scenario_doc
	doc.changed.connect(func(_path: Array) -> void: refresh())
	if play != editor_play:
		play = editor_play
		play.time_changed.connect(_on_play_time)
		play.seek_done.connect(_update_transport)
		play.stopped.connect(func() -> void:
			_update_transport()
			play_view.emit(false))
	playhead = 0.0
	_fitted = true
	refresh()

## Rebuilds the tracks from the document (after every change).
func refresh() -> void:
	if doc == null:
		return
	map = TimelineModel.time_map(doc.data, config)
	tracks = TimelineModel.tracks(doc.data, map)
	custom_minimum_size.y = 34.0 + RULER_H + ROW_H * tracks.size() + 4.0
	if _fitted:
		fit_view()
	_update_transport()
	canvas.queue_redraw()

func duration() -> float:
	return map.duration if map != null else 20.0

func fit_view() -> void:
	var w := maxf(canvas.size.x - GUTTER - 16.0, 50.0)
	pps = w / maxf(duration(), 1.0)
	view_start = 0.0
	canvas.queue_redraw()

# --- coordinates ----------------------------------------------------------------------

func x_of(t: float) -> float:
	return GUTTER + (t - view_start) * pps

func t_of(x: float) -> float:
	return view_start + (x - GUTTER) / pps

## Track index of a canvas y (-1: the ruler, -2: below the tracks).
func row_of(y: float) -> int:
	if y < RULER_H:
		return -1
	var r := int((y - RULER_H) / ROW_H)
	return r if r < tracks.size() else -2

func _row_top(r: int) -> float:
	return RULER_H + r * ROW_H

## Item paths per track id, for tests and the editor.
func track(id: String) -> Dictionary:
	for tr: Dictionary in tracks:
		if tr["id"] == id:
			return tr
	return {}

# --- transport ------------------------------------------------------------------------

func toggle_play() -> void:
	if play == null:
		return
	if play.playing:
		play.pause()
	else:
		if not play.active():
			# (A new run reports time 0: keep where to start.)
			var start := playhead if playhead < duration() - 1e-3 else 0.0
			if not play.load_data(doc.data):
				return
			play_view.emit(true)
			play.seek(start)
		elif play.video_time() >= play.player.duration - 1e-3:
			play.seek(0.0)
		play.play()
	_update_transport()

func stop() -> void:
	if play != null:
		play.stop()
	_update_transport()

## Moves the playhead (and seeks the play preview if it is running).
func set_playhead(t: float, seek_play: bool = true) -> void:
	playhead = clampf(t, 0.0, duration())
	if seek_play and play != null and play.active():
		play.seek(playhead)
	_update_transport()
	canvas.queue_redraw()

func _on_play_time(t: float) -> void:
	playhead = t
	if play.player != null and x_of(t) > canvas.size.x - 20.0 and not _fitted:
		view_start = t - (canvas.size.x - GUTTER) * 0.2 / pps
	_update_transport()
	canvas.queue_redraw()

func _update_transport() -> void:
	var active := play != null and play.active()
	play_button.text = "Pause" if active and play.playing else "Play"
	stop_button.disabled = not active
	seek_bar.visible = active and play.seeking()
	if seek_bar.visible:
		seek_bar.value = play.seek_progress()
	var sim_t := map.sim_time_at(playhead) if map != null else 0.0
	time_label.text = "%.2f / %.0f s  (sim %.0f s)" % [playhead, duration(), sim_t]

func _process(_delta: float) -> void:
	if play != null and play.seeking():
		seek_bar.visible = true
		seek_bar.value = play.seek_progress()

# --- edits ----------------------------------------------------------------------------

func _camera_track_id() -> String:
	return "camera" if not track("camera").is_empty() else "camera_surface"

## Adds an item of track `id` at video time t and selects it. Returns its path.
func add_at(id: String, t: float) -> Array:
	var extra: Dictionary = {}
	if id.begins_with("camera") and key_here.is_valid():
		extra = key_here.call(t)
		extra.erase("t")
	var r := TimelineModel.new_item(id, doc.data, t, map, extra)
	if r.is_empty():
		return []
	var path: Array = r["path"]
	var label := "Add %s" % track(id).get("label", id)
	var at: Array
	if r["insert"]:
		at = CanvasEditor.insert_new(doc, path, r["value"], label)
	else:
		doc.set_at(path, r["value"], label)
		at = path + [(r["value"] as Array).size() - 1]
	select_requested.emit(at)
	return at

func delete_selected() -> bool:
	if selected == null or _item_of(selected).is_empty():
		return false
	doc.remove_at(selected, "Delete")
	select_requested.emit(null)
	return true

## The timeline item {track, index} for a document path, or {}.
func _item_of(path: Variant) -> Dictionary:
	if not path is Array:
		return {}
	for r in tracks.size():
		var items: Array = tracks[r]["items"]
		for i in items.size():
			if items[i]["path"] == path:
				return {"track": r, "index": i}
	return {}

func _snap(t: float, fine: bool) -> float:
	return TimelineModel.snap_time(t, 1.0 / ScenarioPlayer.VIDEO_FPS if fine else 0.1)

## Mouse press at canvas point `at`. Returns true if it did something.
func press(at: Vector2, double: bool = false, shift: bool = false) -> bool:
	var r := row_of(at.y)
	if r == -1:
		_scrubbing = true
		set_playhead(_snap(t_of(at.x), shift), false)
		return true
	if r < 0 or at.x < GUTTER:
		return false
	var tr := tracks[r]
	var hit := TimelineModel.hit(tr, t_of(at.x), HANDLE_PX / pps)
	if hit.is_empty():
		if double:
			add_at(tr["id"], _snap(t_of(at.x), shift))
			return true
		select_requested.emit(null)
		return true
	var item: Dictionary = tr["items"][hit["index"]]
	select_requested.emit(item["path"])
	var grab := t_of(at.x) - (float(item["until"]) if hit["part"] == "until" else float(item["t"]))
	_drag = {"track": r, "index": hit["index"], "part": hit["part"], "grab": grab,
			"path": item["path"], "value": null}
	return true

func motion(at: Vector2, shift: bool = false) -> void:
	if _scrubbing:
		set_playhead(_snap(t_of(at.x), shift), false)
		return
	if _drag.is_empty():
		return
	var t := _snap(t_of(at.x) - float(_drag["grab"]), shift)
	var path: Array = _drag["path"]
	_drag["value"] = TimelineModel.resized(doc.data, path, t) if _drag["part"] == "until" \
			else TimelineModel.moved(doc.data, path, t, map)
	_drag["t"] = t
	canvas.queue_redraw()

func release(at: Vector2, shift: bool = false) -> void:
	if _scrubbing:
		_scrubbing = false
		set_playhead(_snap(t_of(at.x), shift))
		return
	if _drag.is_empty():
		return
	motion(at, shift)
	var value: Variant = _drag["value"]
	var path: Array = _drag["path"]
	_drag = {}
	if value is Dictionary and not (value as Dictionary).is_empty() and not EditorPreview.same(value, doc.get_at(path)):
		doc.set_at(path, value, "Change time")
	canvas.queue_redraw()

func _on_canvas_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					press(mb.position, mb.double_click, mb.shift_pressed)
				else:
					release(mb.position, mb.shift_pressed)
				canvas.accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var keep := t_of(mb.position.x)
					pps = clampf(pps * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.5, 2000.0)
					view_start = maxf(keep - (mb.position.x - GUTTER) / pps, -1.0)
					_fitted = false
					canvas.queue_redraw()
				canvas.accept_event()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				canvas.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _panning:
			view_start = maxf(view_start - mm.relative.x / pps, -1.0)
			_fitted = false
			canvas.queue_redraw()
		else:
			motion(mm.position, mm.shift_pressed)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				if delete_selected():
					canvas.accept_event()
			KEY_SPACE:
				toggle_play()
				canvas.accept_event()

# --- drawing --------------------------------------------------------------------------

func _draw_canvas() -> void:
	if map == null:
		return
	var font := ThemeDB.fallback_font
	var w := canvas.size.x
	var h := RULER_H + ROW_H * tracks.size()
	canvas.draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.1, 0.12))
	# Past the end of the video.
	var end_x := x_of(duration())
	if end_x < w:
		canvas.draw_rect(Rect2(maxf(end_x, GUTTER), 0, w - maxf(end_x, GUTTER), h), Color(0, 0, 0, 0.35))
	# Ruler.
	var step := TimelineModel.tick_step(pps)
	var t := ceilf(maxf(view_start, 0.0) / step) * step
	while x_of(t) < w:
		var x := x_of(t)
		canvas.draw_line(Vector2(x, RULER_H - 6), Vector2(x, h), Color(1, 1, 1, 0.07))
		canvas.draw_line(Vector2(x, RULER_H - 6), Vector2(x, RULER_H), Color(1, 1, 1, 0.5))
		canvas.draw_string(font, Vector2(x + 3, RULER_H - 8), _time_text(t, step), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(1, 1, 1, 0.7))
		t += step
	for r in tracks.size():
		_draw_track(r, font)
	# Gutter over anything scrolled left.
	canvas.draw_rect(Rect2(0, 0, GUTTER, h), Color(0.14, 0.14, 0.16))
	for r in tracks.size():
		canvas.draw_string(font, Vector2(8, _row_top(r) + ROW_H - 7), tracks[r]["label"], HORIZONTAL_ALIGNMENT_LEFT,
				GUTTER - 12, 12, Color(0.85, 0.85, 0.85))
	canvas.draw_line(Vector2(GUTTER, 0), Vector2(GUTTER, h), Color(1, 1, 1, 0.2))
	canvas.draw_line(Vector2(0, RULER_H), Vector2(w, RULER_H), Color(1, 1, 1, 0.2))
	var px := x_of(playhead)
	if px >= GUTTER:
		canvas.draw_line(Vector2(px, 0), Vector2(px, h), Color(1.0, 0.3, 0.3), 2.0)

static func _time_text(t: float, step: float) -> String:
	if t >= 60.0 and step >= 1.0:
		return "%d:%02d" % [int(t) / 60, int(t) % 60]
	return ("%.1f" % t) if step < 1.0 else ("%d" % roundi(t))

func _draw_track(r: int, font: Font) -> void:
	var tr := tracks[r]
	var top := _row_top(r)
	var col: Color = TRACK_COLORS.get(tr["id"], Color.WHITE)
	canvas.draw_line(Vector2(GUTTER, top + ROW_H), Vector2(canvas.size.x, top + ROW_H), Color(1, 1, 1, 0.06))
	if tr["id"] == "speed":
		_draw_speed(top, col)
	var items: Array = tr["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		var t := float(item["t"])
		var until := float(item["until"])
		var dragged: bool = not _drag.is_empty() and _drag["track"] == r and _drag["index"] == i and _drag["value"] != null
		if dragged:
			if _drag["part"] == "until":
				until = float(_drag["t"])
			else:
				# A span keeps its length.
				until += float(_drag["t"]) - t
				t = float(_drag["t"])
		var sel: bool = item["path"] == selected
		var label := str(item["label"])
		if not is_finite(t):
			# An event the speed schedule never reaches.
			canvas.draw_string(font, Vector2(canvas.size.x - 90, top + ROW_H - 7), "never: " + label,
					HORIZONTAL_ALIGNMENT_LEFT, 88, 11, Color(1, 0.4, 0.4))
			continue
		if tr["kind"] == "spans":
			var rect := Rect2(x_of(t), top + 3, maxf(x_of(until) - x_of(t), 3.0), ROW_H - 6)
			var fill := col
			fill.a = 0.45
			canvas.draw_rect(rect, fill)
			canvas.draw_rect(rect, SELECT if sel else col, false, 2.0 if sel else 1.0)
			canvas.draw_string(font, rect.position + Vector2(4, ROW_H - 10), label, HORIZONTAL_ALIGNMENT_LEFT,
					maxf(rect.size.x - 6, 1), 11, Color(1, 1, 1, 0.9))
		else:
			var c := Vector2(x_of(t), top + ROW_H * 0.5)
			var d := 5.0
			var diamond := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
			canvas.draw_colored_polygon(diamond, SELECT if sel else col)
			# The label up to the next item (none when there's no room).
			var room := 140.0
			for j in items.size():
				var dt := float(items[j]["t"]) - t
				if j != i and (dt > 0.0 or (dt == 0.0 and j > i)):
					room = minf(room, dt * pps - 14.0)
			if tr["id"] != "speed" and room >= 24.0:
				canvas.draw_string(font, c + Vector2(8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, room, 11, Color(1, 1, 1, 0.75))

## The ticks-per-frame curve (scaled to the row) and time jumps.
func _draw_speed(top: float, col: Color) -> void:
	var hi := 0.5
	for p: Vector2 in map.points:
		hi = maxf(hi, p.y)
	var pts := PackedVector2Array()
	var x := GUTTER
	while x <= canvas.size.x:
		var tpf := map.tpf_at(t_of(x))
		pts.append(Vector2(x, top + ROW_H - 3 - (ROW_H - 6) * tpf / hi))
		x += 3.0
	if pts.size() > 1:
		var line := col
		line.a = 0.6
		canvas.draw_polyline(pts, line, 1.5)
	for j: Vector2 in map.jumps:
		var jx := x_of(j.x)
		canvas.draw_line(Vector2(jx, top + 2), Vector2(jx, top + ROW_H - 2), Color(1.0, 0.6, 0.2), 2.0)
		canvas.draw_string(ThemeDB.fallback_font, Vector2(jx + 3, top + 11), "+%ds" % roundi(j.y),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.6, 0.2))
