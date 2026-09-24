extends Node
## Recording entry point, meant to run under Movie Maker:
##
##   godot --path . --write-movie out/frame.png --fixed-fps 60 res://scenes/record.tscn \
##         -- --scenario=<name> [--seed=<n>] [--duration=<s>] [--layout=split|normal|nest] [--at=<s>]
##
## --at fast-forwards to that video time before the first frame (for drafts
## and stills of a later moment).
##
## --stills=10,35,70 records stills instead of a video: for each video time,
## fast-forwarded to between frames, three frames: the scenario's own layout,
## the nest's underground full screen (the scenario's nest camera, e.g. the
## whole nest), and a close-up of the nest at the latest digging face
## (--close_zoom, default 5). Movie Maker writes one PNG per frame, in that
## order (the mapping is printed).
##
## tools/record.sh does this and encodes the result. Movie Maker records at the
## window size fixed at startup, so record.sh also writes a temporary
## override.cfg that sets the window to 1080x1920 (Godot renders the full
## frame even if the screen is smaller).
##
## No UI is shown. Each rendered frame advances exactly one video frame, so a
## recording is identical however long frames take. Quits after the duration.

var player: ScenarioPlayer
var _frames_total: int
var _frame := 0
var _stills: PackedFloat32Array = []
var _close_zoom := 5.0
var _layout_arg := ""

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]

	var scenario: String = args.get("scenario", "chaos_to_highway")
	player = ScenarioPlayer.new()
	add_child(player)
	_layout_arg = str(args.get("layout", ""))
	player.setup(scenario, int(args.get("seed", -1)), 0, null, _layout_arg)
	if args.has("stills"):
		for s: String in str(args["stills"]).split(","):
			_stills.append(float(s))
		_close_zoom = float(args.get("close_zoom", _close_zoom))
		_frames_total = _stills.size() * 3
		print("Stills of %s at %s: %d frames (per time: layout, nest, close-up)" % [scenario, _stills, _frames_total])
		return
	var at := float(args.get("at", 0.0))
	while player.video_time < at - 1e-6:
		player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	var duration := float(args.get("duration", player.duration - at))
	_frames_total = roundi(duration * ScenarioPlayer.VIDEO_FPS)
	print("Recording %s: %d frames (%.1f s), seed %d, viewport %s" % [scenario, _frames_total, duration,
			player.sim.rng.seed, get_viewport().get_visible_rect().size])

func _process(_delta: float) -> void:
	if not _stills.is_empty():
		_still_frame()
		return
	player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	_frame += 1
	if _frame % 300 == 0:
		print("  frame %d / %d  (sim %.0f s, %d ants)" % [_frame, _frames_total, player.sim.time(), player.sim.ant_count])
	if _frame >= _frames_total:
		get_tree().quit()

## Sets up the next still (see --stills); this frame is then rendered.
func _still_frame() -> void:
	if _frame >= _frames_total:
		get_tree().quit()
		return
	@warning_ignore("integer_division")
	var k := _frame / 3
	var view := _frame % 3
	if view == 0:
		if player.nest_camera != null:
			player.nest_camera.mode = CameraDirector.Mode.SCRIPT
		while player.video_time < _stills[k] - 1e-6:
			player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
		player.set_mode(_layout_arg if _layout_arg != "" else _scheduled_mode())
	elif view == 1:
		player.set_mode("nest")
		if player.nest_camera != null:
			player.nest_camera.update_camera(player.video_time, 0.0)
	else:
		player.set_mode("nest")
		var world := player.sim.layers[player.nest_view.layer].world if player.nest_view != null else null
		if world != null and player.nest_camera != null:
			var at := world.dug_rect.get_center()
			if not world.dig_log.is_empty():
				at = world.cell_center(world.dig_log[world.dig_log.size() - 1])
			player.nest_camera.mode = CameraDirector.Mode.MANUAL
			player.nest_camera.zoom = Vector2.ONE * _close_zoom
			player.nest_camera.position = at
	print("  frame %d: t=%.1f s (sim %.0f s, %d ants) %s" % [_frame, _stills[k], player.sim.time(),
			player.sim.colonies[0].total_population() if not player.sim.colonies.is_empty() else 0,
			["layout", "nest", "close-up"][view]])
	_frame += 1

## The layout the scenario's schedule has at the current video time.
func _scheduled_mode() -> String:
	var layout: Dictionary = player.data.get("render", {}).get("layout", {})
	var want := str(layout.get("mode", "normal")) if not layout.is_empty() else "normal"
	for m: Dictionary in layout.get("modes", []):
		if float(m["t"]) <= player.video_time + 1e-6:
			want = str(m["mode"])
	return want
