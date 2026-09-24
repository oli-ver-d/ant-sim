extends Node
## Recording entry point, meant to run under Movie Maker:
##
##   godot --path . --write-movie out/frame.png --fixed-fps 60 res://scenes/record.tscn \
##         -- --scenario=<name> [--seed=<n>] [--duration=<s>] [--layout=split|normal|nest] [--at=<s>]
##
## --at fast-forwards to that video time before the first frame (for drafts
## and stills of a later moment).
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

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]

	var scenario: String = args.get("scenario", "chaos_to_highway")
	player = ScenarioPlayer.new()
	add_child(player)
	player.setup(scenario, int(args.get("seed", -1)), 0, null, str(args.get("layout", "")))
	var at := float(args.get("at", 0.0))
	while player.video_time < at - 1e-6:
		player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	var duration := float(args.get("duration", player.duration - at))
	_frames_total = roundi(duration * ScenarioPlayer.VIDEO_FPS)
	print("Recording %s: %d frames (%.1f s), seed %d, viewport %s" % [scenario, _frames_total, duration,
			player.sim.rng.seed, get_viewport().get_visible_rect().size])

func _process(_delta: float) -> void:
	player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	_frame += 1
	if _frame % 300 == 0:
		print("  frame %d / %d  (sim %.0f s, %d ants)" % [_frame, _frames_total, player.sim.time(), player.sim.ant_count])
	if _frame >= _frames_total:
		get_tree().quit()
