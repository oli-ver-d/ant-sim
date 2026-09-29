class_name LaunchCommands
extends RefCounted
## The command lines the scenario editor uses to launch the interactive player
## and the recording pipeline. A GDScript version of tools/record.sh and
## tools/encode.sh (same arguments, file names and override.cfg), so the editor
## records exactly what the scripts do. Pure functions: no files, no processes.

## Options of the interactive player run (Run menu).
const RUN_DEFAULTS := {"seed_mode": "scenario", "seed": 1, "at": 0.0, "from_playhead": false,
	"layout": "", "size": "", "captions": true, "safe": false, "pheromones": true, "debug": false, "tuning": false}
## Options of a recording. seed -1 and end -1 mean the scenario's seed and duration.
const RECORD_DEFAULTS := {"format": "png", "mjpeg_quality": 1.0, "size": "", "seed": -1, "start": 0.0, "end": -1.0,
	"captions": true, "out_dir": "renders", "file_name": "", "keep_frames": false}
## Makes ffmpeg report progress on stdout (key=value lines) instead of a stats line.
const FFMPEG_PROGRESS := ["-progress", "pipe:1", "-nostats"]
const RECORD_FPS := 60

## A copy of `defaults` overlaid with the keys of `settings` that exist in
## `defaults`. Numbers are converted to the default's type (JSON and
## ConfigFile give floats for ints).
static func with_defaults(settings: Dictionary, defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	for key: Variant in defaults:
		if not settings.has(key):
			continue
		var value: Variant = settings[key]
		var want: int = typeof(defaults[key])
		if want == TYPE_INT and typeof(value) == TYPE_FLOAT:
			value = int(value)
		elif want == TYPE_FLOAT and typeof(value) == TYPE_INT:
			value = float(value)
		out[key] = value
	return out

## Arguments for the Godot executable that runs the interactive player.
static func run_args(settings: Dictionary, scenario_path: String, project_dir: String,
		playhead: float = 0.0, random_seed: int = 0) -> PackedStringArray:
	var s := with_defaults(settings, RUN_DEFAULTS)
	var args := PackedStringArray(["--path", project_dir, "res://scenes/main.tscn", "--",
			"--scenario=" + scenario_path])
	match str(s["seed_mode"]):
		"fixed":
			args.append("--seed=" + str(s["seed"]))
		"random":
			args.append("--seed=" + str(random_seed))
	var at: float = playhead if s["from_playhead"] else float(s["at"])
	if at > 0.0:
		args.append("--at=" + num(at))
	if str(s["layout"]) != "":
		args.append("--layout=" + str(s["layout"]))
	if str(s["size"]) != "":
		args.append("--size=" + str(s["size"]))
	if not s["captions"]:
		args.append("--captions=0")
	if s["safe"]:
		args.append("--safe=1")
	if not s["pheromones"]:
		args.append("--pheromones=0")
	if s["debug"]:
		args.append("--debug=1")
	if s["tuning"]:
		args.append("--tuning=1")
	return args

## "1920x1080".
static func size_label(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]

## "YYYYMMDD_HHMMSS" from a Time.get_datetime_dict_from_system() dictionary.
static func stamp(dt: Dictionary) -> String:
	return "%04d%02d%02d_%02d%02d%02d" % [int(dt.get("year", 0)), int(dt.get("month", 0)),
			int(dt.get("day", 0)), int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0))]

## The scenario file's name without folder and extension ("untitled" if none).
static func scenario_name(path: String) -> String:
	var base := path.get_file().get_basename()
	return base if base != "" else "untitled"

## A number for a command line: whole numbers without ".0", others with up to
## 3 decimals and no trailing zeros (12.5 -> "12.5", 3.0 -> "3").
static func num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	var text := "%.3f" % x
	text = text.rstrip("0")
	return text.rstrip(".")

## The MJPEG quality as record.sh writes it: "1.0", "0.9", "0.75".
static func _quality_text(q: float) -> String:
	var text := num(q)
	return text + ".0" if not text.contains(".") else text

static func _is_absolute(path: String) -> bool:
	return path.begins_with("/") or path.begins_with("res://") or path.begins_with("user://") \
			or (path.length() >= 2 and path[1] == ":")

## Everything needed to record a scenario: {"ok", "error"} and, when ok, the
## paths, the Godot and ffmpeg arguments, the override.cfg text and the expected
## frame count. `data` is the scenario's data; `stamp_text` comes from stamp().
static func record_plan(settings: Dictionary, scenario_path: String, data: Dictionary,
		project_dir: String, stamp_text: String) -> Dictionary:
	var s := with_defaults(settings, RECORD_DEFAULTS)
	var fail := func(message: String) -> Dictionary:
		return {"ok": false, "error": message}
	var format := str(s["format"])
	if format != "png" and format != "avi":
		return fail.call("Format must be png or avi (got '%s')" % format)
	var frame_size: Vector2i
	if str(s["size"]) != "":
		frame_size = OutputFrame.parse_size(str(s["size"]))
		if not OutputFrame.valid_size(frame_size):
			return fail.call("Frame size must be even and 64-8192, e.g. 1920x1080 (got '%s')" % str(s["size"]))
	else:
		frame_size = OutputFrame.from_scenario(data).size
	var start: float = s["start"]
	var end: float = s["end"]
	if end >= 0.0 and end <= start:
		return fail.call("End must be after start")
	var quality: float = s["mjpeg_quality"]
	if quality < 0.0 or quality > 1.0:
		return fail.call("MJPEG quality must be between 0 and 1 (got %s)" % num(quality))

	var seed_value: int = s["seed"] if int(s["seed"]) >= 0 else int(data.get("seed", 1))
	var name := "%s_seed%d" % [scenario_name(scenario_path), seed_value]
	if frame_size != OutputFrame.DEFAULT_SIZE:
		name += "_" + size_label(frame_size)
	if not s["captions"]:
		name += "_nocaptions"
	if start > 0.0:
		name += "_from" + num(start)
	name += "_" + stamp_text

	var out_dir := str(s["out_dir"])
	if not _is_absolute(out_dir):
		out_dir = project_dir.path_join(out_dir)
	out_dir = out_dir.simplify_path()
	var file_name := str(s["file_name"])
	if file_name == "":
		file_name = name
	if file_name.get_extension().to_lower() != "mp4":
		file_name += ".mp4"
	# An absolute file name is used as it is (its folder must exist).
	var out_path := file_name.simplify_path() if _is_absolute(file_name) else out_dir.path_join(file_name)
	var capture_dir := out_dir.path_join("capture_" + name)
	var capture := capture_dir.path_join("capture.avi" if format == "avi" else "frame.png")

	var override_cfg := "[display]\n\nwindow/size/window_width_override=%d\nwindow/size/window_height_override=%d\n\n[editor]\n\nmovie_writer/mjpeg_quality=%s\n" \
			% [frame_size.x, frame_size.y, _quality_text(quality)]

	var record_args := PackedStringArray(["--path", project_dir, "--write-movie", capture,
			"--fixed-fps", str(RECORD_FPS), "res://scenes/record.tscn", "--",
			"--scenario=" + scenario_path, "--seed=" + str(int(s["seed"])), "--size=" + size_label(frame_size)])
	if end >= 0.0:
		record_args.append("--duration=" + num(end - start))
	if start > 0.0:
		record_args.append("--at=" + num(start))
	if not s["captions"]:
		record_args.append("--captions=0")
	record_args.append("--progress=10")

	var source: Array
	var filter: String
	if format == "avi":
		source = ["-i", capture]
		filter = "scale=in_range=pc:out_range=tv,format=yuv420p"
	else:
		source = ["-framerate", str(RECORD_FPS), "-i", capture_dir + "/frame%08d.png"]
		filter = "format=yuv420p"
	var encode_args := PackedStringArray(["-hide_banner", "-loglevel", "warning", "-y"])
	encode_args.append_array(PackedStringArray(FFMPEG_PROGRESS))
	encode_args.append_array(PackedStringArray(source))
	encode_args.append_array(PackedStringArray(["-vf", filter, "-c:v", "libx264", "-preset", "slow",
			"-crf", "18", "-pix_fmt", "yuv420p", "-color_range", "tv", "-movflags", "+faststart",
			"-an", out_path]))

	var seconds: float = (end - start) if end >= 0.0 else float(data.get("duration", 20.0)) - start
	return {"ok": true, "error": "", "frame_size": frame_size, "format": format, "seed": seed_value,
		"name": name, "out_dir": out_dir, "out_path": out_path, "capture_dir": capture_dir,
		"capture": capture, "override_cfg": override_cfg, "record_args": record_args,
		"encode_args": encode_args, "keep_frames": bool(s["keep_frames"]),
		"expected_frames": maxi(roundi(seconds * RECORD_FPS), 0)}
