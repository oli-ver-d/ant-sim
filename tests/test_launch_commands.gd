extends TestCase
## Editor launch commands (LaunchCommands): the player and recording command
## lines must match tools/record.sh and tools/encode.sh.

const PROJ := "C:/proj"
const SCEN := "C:/tmp/editor_runs/basic_forage.json"
const STAMP := "20260929_120000"

func _plan(settings: Dictionary, data: Dictionary = {"seed": 7, "duration": 30}) -> Dictionary:
	return LaunchCommands.record_plan(settings, SCEN, data, PROJ, STAMP)

func _strs(a: Array) -> PackedStringArray:
	return PackedStringArray(a)

func test_with_defaults() -> void:
	var s := LaunchCommands.with_defaults({"seed": 5.0, "at": 3, "bogus": 1, "debug": true},
			LaunchCommands.RUN_DEFAULTS)
	check(not s.has("bogus"), "unknown key dropped")
	check_eq(typeof(s["seed"]), TYPE_INT, "float -> int for seed")
	check_eq(s["seed"], 5, "seed value")
	check_eq(typeof(s["at"]), TYPE_FLOAT, "int -> float for at")
	check_eq(s["at"], 3.0, "at value")
	check_eq(s["debug"], true, "bool kept")
	check_eq(s["layout"], "", "missing key takes the default")

func test_run_args_defaults() -> void:
	check_eq(LaunchCommands.run_args({}, SCEN, PROJ),
			_strs(["--path", PROJ, "res://scenes/main.tscn", "--", "--scenario=" + SCEN]), "only the base args")

func test_run_args_all_options() -> void:
	var s := {"seed_mode": "fixed", "seed": 42, "at": 12.5, "layout": "split", "size": "1920x1080",
		"captions": false, "safe": true, "pheromones": false, "debug": true, "tuning": true}
	check_eq(LaunchCommands.run_args(s, SCEN, PROJ),
			_strs(["--path", PROJ, "res://scenes/main.tscn", "--", "--scenario=" + SCEN, "--seed=42",
			"--at=12.5", "--layout=split", "--size=1920x1080", "--captions=0", "--safe=1",
			"--pheromones=0", "--debug=1", "--tuning=1"]), "every option")

func test_run_args_seed_modes() -> void:
	var fixed := LaunchCommands.run_args({"seed_mode": "fixed", "seed": 9}, SCEN, PROJ, 0.0, 77)
	check(fixed.has("--seed=9"), "fixed uses settings.seed")
	var rnd := LaunchCommands.run_args({"seed_mode": "random", "seed": 9}, SCEN, PROJ, 0.0, 77)
	check(rnd.has("--seed=77") and not rnd.has("--seed=9"), "random uses the given seed")
	var scen := LaunchCommands.run_args({"seed_mode": "scenario", "seed": 9}, SCEN, PROJ, 0.0, 77)
	check_eq(scen.size(), 5, "scenario mode adds no seed")

func test_run_args_at() -> void:
	var a := LaunchCommands.run_args({"at": 4.0, "from_playhead": false}, SCEN, PROJ, 8.25)
	check(a.has("--at=4"), "at used when not from the playhead")
	var b := LaunchCommands.run_args({"at": 4.0, "from_playhead": true}, SCEN, PROJ, 8.25)
	check(b.has("--at=8.25") and not b.has("--at=4"), "playhead wins")
	var c := LaunchCommands.run_args({"at": 0.0}, SCEN, PROJ, 8.25)
	check_eq(c.size(), 5, "at 0 omitted")
	var d := LaunchCommands.run_args({"from_playhead": true}, SCEN, PROJ, 0.0)
	check_eq(d.size(), 5, "playhead 0 omitted")

func test_record_plan_defaults() -> void:
	var p := _plan({})
	check(p["ok"], "ok: " + str(p["error"]))
	var name := "basic_forage_seed7_" + STAMP
	check_eq(p["name"], name, "name")
	check_eq(p["frame_size"], Vector2i(1080, 1920), "frame size")
	check_eq(p["seed"], 7, "seed from the scenario")
	check_eq(p["out_dir"], "C:/proj/renders", "out_dir")
	check_eq(p["out_path"], "C:/proj/renders/" + name + ".mp4", "out_path")
	check_eq(p["capture_dir"], "C:/proj/renders/capture_" + name, "capture_dir")
	check_eq(p["capture"], "C:/proj/renders/capture_" + name + "/frame.png", "capture")
	check_eq(p["override_cfg"], "[display]\n\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n\n[editor]\n\nmovie_writer/mjpeg_quality=1.0\n", "override.cfg")
	check_eq(p["record_args"], _strs(["--path", PROJ, "--write-movie", p["capture"], "--fixed-fps", "60",
			"res://scenes/record.tscn", "--", "--scenario=" + SCEN, "--seed=-1", "--size=1080x1920",
			"--progress=10"]), "record_args")
	check_eq(p["encode_args"], _strs(["-hide_banner", "-loglevel", "warning", "-y", "-progress", "pipe:1",
			"-nostats", "-framerate", "60", "-i", p["capture_dir"] + "/frame%08d.png", "-vf", "format=yuv420p",
			"-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-color_range", "tv",
			"-movflags", "+faststart", "-an", p["out_path"]]), "encode_args (png)")
	check_eq(p["expected_frames"], 1800, "30 s at 60 fps")
	check_eq(p["keep_frames"], false, "keep_frames")
	check_eq(p["format"], "png", "format")

func test_record_plan_avi_full() -> void:
	var p := _plan({"format": "avi", "mjpeg_quality": 0.9, "size": "1920x1080", "seed": 3, "start": 2.5,
			"end": 12.5, "captions": false, "out_dir": "D:/videos", "file_name": "final", "keep_frames": true})
	check(p["ok"], "ok: " + str(p["error"]))
	var name := "basic_forage_seed3_1920x1080_nocaptions_from2.5_" + STAMP
	check_eq(p["name"], name, "name")
	check_eq(p["out_path"], "D:/videos/final.mp4", "file_name gets .mp4")
	check_eq(p["capture_dir"], "D:/videos/capture_" + name, "capture_dir")
	check_eq(p["capture"], "D:/videos/capture_" + name + "/capture.avi", "capture")
	check(String(p["override_cfg"]).contains("width_override=1920\n") and String(p["override_cfg"]).ends_with("mjpeg_quality=0.9\n"), "override.cfg")
	check_eq(p["record_args"], _strs(["--path", PROJ, "--write-movie", p["capture"], "--fixed-fps", "60",
			"res://scenes/record.tscn", "--", "--scenario=" + SCEN, "--seed=3", "--size=1920x1080",
			"--duration=10", "--at=2.5", "--captions=0", "--progress=10"]), "record_args")
	check_eq(p["encode_args"], _strs(["-hide_banner", "-loglevel", "warning", "-y", "-progress", "pipe:1",
			"-nostats", "-i", p["capture"], "-vf", "scale=in_range=pc:out_range=tv,format=yuv420p",
			"-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-color_range", "tv",
			"-movflags", "+faststart", "-an", "D:/videos/final.mp4"]), "encode_args (avi)")
	check_eq(p["expected_frames"], 600, "10 s")
	check_eq(p["keep_frames"], true, "keep_frames")
	check_eq(_plan({"file_name": "x.MP4"})["out_path"], "C:/proj/renders/x.MP4", "existing .mp4 kept")
	check_eq(_plan({"mjpeg_quality": 0.75})["override_cfg"].ends_with("=0.75\n"), true, "quality 0.75")

func test_record_plan_scenario_size() -> void:
	var p := _plan({}, {"seed": 1, "output": {"size": [1920, 1080]}})
	check_eq(p["frame_size"], Vector2i(1920, 1080), "scenario output.size")
	check(String(p["name"]).contains("_1920x1080_"), "size in the name")
	var q := _plan({}, {"seed": 1, "output": {"size": [1080, 1920]}})
	check(not String(q["name"]).contains("1080x1920"), "portrait size not in the name")
	check_eq(q["expected_frames"], 1200, "default duration 20 s")
	check_eq(_plan({"start": 5.0})["expected_frames"], 1500, "start reduces the frames")

func test_record_plan_errors() -> void:
	var odd := _plan({"size": "1081x1920"})
	check(not odd["ok"], "odd size rejected")
	check_eq(odd["error"], "Frame size must be even and 64-8192, e.g. 1920x1080 (got '1081x1920')", "size message")
	var fmt := _plan({"format": "gif"})
	check(not fmt["ok"], "bad format rejected")
	check_eq(fmt["error"], "Format must be png or avi (got 'gif')", "format message")
	var end := _plan({"start": 5.0, "end": 5.0})
	check(not end["ok"] and end["error"] == "End must be after start", "end <= start")
	check(not _plan({"mjpeg_quality": 1.5})["ok"], "quality 1.5 rejected")
	check(not _plan({"size": "abc"})["ok"], "unparsable size rejected")

func test_relative_and_absolute_out_dir() -> void:
	check_eq(_plan({"out_dir": "../out/./x"})["out_dir"], "C:/out/x", "relative simplified")
	check_eq(_plan({"out_dir": "/tmp/v"})["out_dir"], "/tmp/v", "unix absolute")
	check_eq(_plan({"out_dir": "user://renders"})["out_dir"], "user://renders", "user:// kept")

func test_num() -> void:
	check_eq(LaunchCommands.num(12.5), "12.5", "12.5")
	check_eq(LaunchCommands.num(3.0), "3", "3.0")
	check_eq(LaunchCommands.num(0.0), "0", "0")
	check_eq(LaunchCommands.num(0.125), "0.125", "3 decimals")
	check_eq(LaunchCommands.num(1.23456), "1.235", "rounded")
	check_eq(LaunchCommands.num(2.10), "2.1", "trailing zero trimmed")

func test_stamp() -> void:
	check_eq(LaunchCommands.stamp({"year": 2026, "month": 3, "day": 9, "hour": 4, "minute": 5, "second": 6}),
			"20260309_040506", "zero padded")

func test_scenario_name() -> void:
	check_eq(LaunchCommands.scenario_name("C:/x/y/basic_forage.json"), "basic_forage", "windows path")
	check_eq(LaunchCommands.scenario_name("res://scenarios/maze.json"), "maze", "res path")
	check_eq(LaunchCommands.scenario_name(""), "untitled", "empty")

func test_size_label() -> void:
	check_eq(LaunchCommands.size_label(Vector2i(1920, 1080)), "1920x1080", "label")
