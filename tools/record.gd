extends SceneTree
## Records a scenario to an H.264 MP4: the recording pipeline in GDScript, so
## it runs anywhere Godot and ffmpeg do (tools/record.sh is a thin wrapper, and
## the scenario editor's Record dialog runs the same RecordJob).
##
##   godot --headless --path . -s res://tools/record.gd -- <scenario> [seed] [seconds] [options]
##
## <scenario> is a name in scenarios/ or a path to a .json file (relative
## paths are relative to the project folder). seed -1 (default) uses the
## scenario's; seconds limits the length (default: the scenario's duration).
## Options:
##   --format=png|avi     png (default): lossless frames, for finals; avi: MJPEG
##                        drafts, ~7x faster
##   --quality=<0..1>     MJPEG quality for avi (default 1.0)
##   --size=<W>x<H>       output frame size (default: the scenario's output.size)
##   --captions=0         without the scenario's captions
##   --start=<s>          start at this video time (seconds then counts from it)
##   --out_dir=<dir>      default renders/
##   --out=<file.mp4>     file name in out_dir, or an absolute path (default <scenario>_seed<N>[_WxH]
##                        [_nocaptions][_from<s>]_<YYYYMMDD_HHMMSS>.mp4)
##   --keep_frames=1      keep the capture folder
##   --ffmpeg=<path>      ffmpeg executable (default: ffmpeg on PATH)
##
## Movie Maker needs a window (the recorder is a normal, non-headless Godot
## child process); this script itself can run headless.

var job: RecordJob

func _initialize() -> void:
	var positional: PackedStringArray = []
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
		else:
			positional.append(arg)
	if positional.is_empty():
		printerr("usage: godot --headless --path . -s res://tools/record.gd -- <scenario> [seed] [seconds] [options]")
		quit(1)
		return
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var scenario := positional[0]
	if scenario.ends_with(".json") and scenario.is_relative_path() and not scenario.begins_with("res://"):
		scenario = project.path_join(scenario)
	var data := ScenarioLoader.load_data(scenario)
	if data.is_empty():
		quit(1)
		return
	var start := float(opts.get("start", 0.0))
	var settings := {
		"format": opts.get("format", "png"),
		"mjpeg_quality": float(opts.get("quality", 1.0)),
		"size": opts.get("size", ""),
		"seed": int(positional[1]) if positional.size() > 1 else -1,
		"start": start,
		"end": start + float(positional[2]) if positional.size() > 2 and positional[2] != "" else -1.0,
		"captions": opts.get("captions", "1") != "0",
		"out_dir": opts.get("out_dir", "renders"),
		"file_name": opts.get("out", ""),
		"keep_frames": opts.get("keep_frames", "0") != "0",
	}
	var plan := LaunchCommands.record_plan(settings, scenario, data, project,
			LaunchCommands.stamp(Time.get_datetime_dict_from_system()))
	job = RecordJob.new()
	job.output.connect(func(line: String) -> void: print(line))
	if not job.start(plan, project, "", str(opts.get("ffmpeg", "ffmpeg"))):
		quit(1)

var _last_shown := -1

func _process(_delta: float) -> bool:
	if job == null:
		return false
	job.poll()
	@warning_ignore("integer_division")
	var shown := job.frames_encoded / 300
	if job.stage == RecordJob.Stage.ENCODING and shown != _last_shown:
		_last_shown = shown
		print("  encoded %d / %d" % [job.frames_encoded, job.frames_total])
	if job.is_running():
		OS.delay_msec(20)
		return false
	quit(0 if job.stage == RecordJob.Stage.DONE else 1)
	return true
