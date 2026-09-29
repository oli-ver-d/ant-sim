class_name EditorPlay
extends Control
## The editor's play preview (M16g): the document played by a real
## ScenarioPlayer (setup_data, exactly as main.tscn and record.tscn play it) in
## a SubViewport the size of the document's output frame, shown scaled to fit
## this control. It never touches the static preview's sim (EditorPreview may
## patch that one in place).
##
## Video time advances in whole 1/60 s frames, as in a recording, so what is
## shown at a time is what a recording shows there. `speed` is the playback
## rate of video time (0.25-8x). seek(t) fast-forwards (going back rebuilds
## the run first), a slice of work per frame so the editor stays responsive,
## with `seek_progress()` for a progress bar. Long founding runs take a while
## to reach late times; that is expected (there are no sim snapshots).

signal time_changed(t: float)
## A seek finished (or was dropped by stop()).
signal seek_done
signal stopped

const FRAME := 1.0 / ScenarioPlayer.VIDEO_FPS
## Most milliseconds of fast-forwarding per editor frame while seeking.
const SEEK_BUDGET_MS := 40
## Most video frames played per editor frame (a slow scenario at 8x lags
## instead of stalling the editor).
const MAX_STEPS := 16

var player: ScenarioPlayer
var playing := false
## Playback rate of video time.
var speed := 1.0
## Video time a seek is heading for (-1: not seeking).
var seek_to := -1.0
## The data the running player was built from (a deep copy).
var data: Dictionary = {}

var _viewport: SubViewport
var _screen: TextureRect
var _owed := 0.0
var _seek_from := 0.0

func _init() -> void:
	clip_contents = true
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_screen = TextureRect.new()
	_screen.texture = _viewport.get_texture()
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

## True while a player exists (playing, paused or seeking).
func active() -> bool:
	return player != null

func video_time() -> float:
	return player.video_time if player != null else 0.0

## Builds a new run of `scenario` at video time 0 (paused). Returns false if it
## can't be built.
func load_data(scenario: Dictionary) -> bool:
	_free_player()
	data = scenario.duplicate(true)
	if not data.get("colonies", []) is Array or not data.get("food", []) is Array:
		return false
	player = ScenarioPlayer.new()
	player.setup_data(data)
	_viewport.size = player.frame.size
	_viewport.add_child(player)
	# Cameras and presentation read the viewport; frame 0 as main.gd shows it.
	player.advance(0.0)
	time_changed.emit(0.0)
	return true

func play() -> void:
	if player != null:
		playing = true
		_owed = 0.0

func pause() -> void:
	playing = false

## Goes to video time `t` (clamped to 0..duration): forward from here, or
## from a fresh build when `t` is behind the current time.
func seek(t: float) -> void:
	if player == null:
		return
	t = clampf(t, 0.0, player.duration)
	if t < player.video_time - 1e-6:
		var was_playing := playing
		load_data(data)
		playing = was_playing
	_seek_from = player.video_time
	seek_to = t
	if t <= player.video_time + 1e-6:
		_finish_seek()

func seeking() -> bool:
	return seek_to >= 0.0

## 0..1 through the current seek (1 when not seeking).
func seek_progress() -> float:
	if seek_to < 0.0 or player == null or seek_to <= _seek_from:
		return 1.0
	return clampf((player.video_time - _seek_from) / (seek_to - _seek_from), 0.0, 1.0)

## Drops the run (back to the static preview).
func stop() -> void:
	var had := player != null
	_free_player()
	if had:
		stopped.emit()

func _free_player() -> void:
	playing = false
	if seek_to >= 0.0:
		seek_to = -1.0
		seek_done.emit()
	if player != null:
		player.queue_free()
		player = null

## Runs whole video frames until `t` (or the budget runs out); true if there.
func step_until(t: float, budget_ms: int = SEEK_BUDGET_MS) -> bool:
	var start := Time.get_ticks_msec()
	while player.video_time < t - 1e-6:
		player.advance(FRAME)
		if Time.get_ticks_msec() - start >= budget_ms:
			break
	return player.video_time >= t - 1e-6

func _finish_seek() -> void:
	seek_to = -1.0
	_owed = 0.0
	time_changed.emit(player.video_time)
	seek_done.emit()

func _process(delta: float) -> void:
	if player == null:
		return
	if seek_to >= 0.0:
		if step_until(seek_to):
			_finish_seek()
		else:
			time_changed.emit(player.video_time)
		return
	if not playing:
		return
	_owed += delta * speed
	var steps := 0
	while _owed >= FRAME - 1e-9 and steps < MAX_STEPS and player.video_time < player.duration - 1e-6:
		player.advance(FRAME)
		_owed -= FRAME
		steps += 1
	if steps == MAX_STEPS:
		_owed = 0.0
	if player.video_time >= player.duration - 1e-6:
		playing = false
	if steps > 0:
		time_changed.emit(player.video_time)
