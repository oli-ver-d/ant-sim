extends TestCase
## M16h: running and recording from the editor. A scenario given as a path to
## a temporary copy runs exactly like the scenario by name; the per-scenario
## settings store; RecordJob's failure paths (no process is ever started
## here, except in the long end-to-end test); the editor's Run and Record
## wiring with a fake process launcher. The command lines themselves are in
## test_launch_commands.gd, the dialogs in test_launch_dialogs.gd.

const EDITOR := preload("res://scenes/editor.tscn")
const TEMP_DIR := "user://test_launch"
## Never a Windows process id (those are multiples of 4).
const FAKE_PID := 1073741823

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root

## An absolute directory of this test's own (tests run in parallel processes).
func _dir() -> String:
	var dir := ProjectSettings.globalize_path(TEMP_DIR.path_join(current_test.get_slice("::", 1)))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

func _cleanup() -> void:
	RecordJob.remove_tree(_dir())

## A copy of a shipped scenario written by the editor's writer to `path`.
func _copy(scenario: String, path: String) -> void:
	ScenarioJson.save_file(path, ScenarioJson.load_file(ScenarioLoader.path_for(scenario)))

func _hash_after(data: Dictionary, ticks: int) -> String:
	var sim := ScenarioLoader.build(data, _registry, _config)
	for t in ticks:
		sim.step()
	return sim.state_hash()

# --- a scenario by path -------------------------------------------------------------------

func test_path_to_a_copy_loads_like_the_name() -> void:
	var abs_path := _dir().path_join("basic_forage.json")
	_copy("basic_forage", abs_path)
	check(abs_path.is_absolute_path() and not abs_path.begins_with("user://"), "absolute: " + abs_path)
	check_eq(ScenarioLoader.path_for(abs_path), abs_path, "path_for keeps a .json path")
	var by_name := _hash_after(ScenarioLoader.load_data("basic_forage"), 20)
	check_eq(_hash_after(ScenarioLoader.load_data(abs_path), 20), by_name, "absolute path: same run")
	var user_path := TEMP_DIR.path_join(current_test.get_slice("::", 1)).path_join("basic_forage.json")
	check_eq(_hash_after(ScenarioLoader.load_data(user_path), 20), by_name, "user:// path: same run")
	_cleanup()

func test_player_runs_a_path_like_the_name() -> void:
	var abs_path := _dir().path_join("leafcutter_life.json")
	_copy("leafcutter_life", abs_path)
	var a := ScenarioPlayer.new()
	_root().add_child(a)
	a.setup("leafcutter_life")
	var b := ScenarioPlayer.new()
	_root().add_child(b)
	b.setup(abs_path)
	for f in 30:
		a.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
		b.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
	check_eq(b.sim.state_hash(), a.sim.state_hash(), "same state hash after 30 frames")
	check_eq(b.frame.size, a.frame.size, "same output frame")
	a.free()
	b.free()
	_cleanup()

# --- settings --------------------------------------------------------------------------

func test_settings_per_scenario() -> void:
	var cfg := _dir().path_join("settings.cfg")
	var recent := EditorRecent.new()
	recent.add("res://scenarios/maze.json")
	recent.save_to(cfg)
	check_eq(LaunchSettings.load_for(cfg, "run", "a.json", LaunchCommands.RUN_DEFAULTS),
			LaunchCommands.RUN_DEFAULTS, "defaults when nothing is kept")
	var run := LaunchCommands.RUN_DEFAULTS.duplicate()
	run["seed_mode"] = "fixed"
	run["seed"] = 42
	run["layout"] = "split"
	check_eq(LaunchSettings.save_for(cfg, "run", "a.json", run), OK, "saved")
	var rec := LaunchCommands.RECORD_DEFAULTS.duplicate()
	rec["format"] = "avi"
	LaunchSettings.save_for(cfg, "record", "", rec)
	check_eq(LaunchSettings.load_for(cfg, "run", "a.json", LaunchCommands.RUN_DEFAULTS), run, "run settings back")
	check_eq(LaunchSettings.load_for(cfg, "run", "b.json", LaunchCommands.RUN_DEFAULTS),
			LaunchCommands.RUN_DEFAULTS, "another scenario has its own")
	check_eq(LaunchSettings.load_for(cfg, "record", "", LaunchCommands.RECORD_DEFAULTS), rec,
			"record settings of an unsaved document")
	recent.load_from(cfg)
	check_eq(recent.files, PackedStringArray(["res://scenarios/maze.json"]), "recent files kept")
	_cleanup()

# --- RecordJob, without processes -------------------------------------------------------

func _plan(project: String) -> Dictionary:
	var data := ScenarioLoader.load_data("basic_forage")
	return LaunchCommands.record_plan({"format": "avi", "end": 1.0}, project.path_join("basic_forage.json"),
			data, project, "20260101_000000")

func test_job_rejects_a_bad_plan() -> void:
	var job := RecordJob.new()
	var ended: Array = []
	job.finished.connect(func(ok: bool, message: String) -> void: ended.append([ok, message]))
	var plan := LaunchCommands.record_plan({"size": "1081x1920"}, "x.json", {}, _dir(), "t")
	check(not job.start(plan, _dir(), "no_such_godot"), "not started")
	check_eq(job.stage, RecordJob.Stage.FAILED, "failed")
	check(job.message.begins_with("Frame size"), "the plan's error: " + job.message)
	check_eq(ended.size(), 1, "finished once")
	check(not ended[0][0], "not ok")
	_cleanup()

func test_job_refuses_an_existing_override_cfg() -> void:
	var project := _dir()
	var cfg := project.path_join("override.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("[display]\n")
	f.close()
	var job := RecordJob.new()
	check(not job.start(_plan(project), project, "no_such_godot"), "not started")
	check(job.message.contains("override.cfg"), job.message)
	check_eq(FileAccess.get_file_as_string(cfg), "[display]\n", "someone else's override.cfg left alone")
	_cleanup()

func test_job_cleans_up_when_godot_is_missing() -> void:
	var project := _dir()
	var plan := _plan(project)
	var job := RecordJob.new()
	check(not job.start(plan, project, project.path_join("no_such_godot.exe")), "not started")
	check_eq(job.stage, RecordJob.Stage.FAILED, "failed")
	check(job.message.begins_with("Can't start Godot"), job.message)
	check(not FileAccess.file_exists(project.path_join("override.cfg")), "override.cfg removed")
	check(job.log_lines.size() >= 2, "logged")
	job.cancel()  # not running: nothing happens
	check_eq(job.stage, RecordJob.Stage.FAILED, "cancel after the end is a no-op")
	check(DirAccess.dir_exists_absolute(plan["capture_dir"]), "capture folder made before starting")
	RecordJob.remove_tree(plan["capture_dir"])
	check(not DirAccess.dir_exists_absolute(plan["capture_dir"]), "remove_tree")
	_cleanup()

func test_job_progress_from_output_lines() -> void:
	var project := _dir()
	var job := RecordJob.new()
	job.plan = _plan(project)
	job.stage = RecordJob.Stage.RECORDING
	job._on_line("Recording basic_forage: 120 frames (2.0 s), seed 1, viewport (1080, 1920)")
	check_eq(job.frames_total, 120, "total from the recorder")
	job._on_line("  frame 30 / 120  (sim 1 s, 320 ants)")
	check_eq(job.frames_done, 30, "frames done")
	check_eq(job.fraction(), 0.25, "fraction")
	check_eq(job.status_text(), "Recording frame 30 / 120", "status")
	job.stage = RecordJob.Stage.ENCODING
	job._on_line("frame=60")
	job._on_line("fps=12.0")
	check_eq(job.frames_encoded, 60, "encoded")
	check_eq(job.fraction(), 0.5, "encode fraction")
	check(not job.log_lines.has("fps=12.0"), "progress keys not logged")
	_cleanup()

# --- the editor ---------------------------------------------------------------------------

func _editor(scenario: String) -> ScenarioEditor:
	var ed: ScenarioEditor = EDITOR.instantiate()
	ed.manage_window = false
	ed.settings_path = _dir().path_join("settings.cfg")
	ed.runs_dir = TEMP_DIR.path_join(current_test.get_slice("::", 1)).path_join("runs")
	ed.project_dir = _dir()
	ed.godot_path = _dir().path_join("no_such_godot.exe")
	if scenario != "":
		ed.args = {"scenario": scenario}
	_root().add_child(ed)
	return ed

func test_editor_run_uses_an_unsaved_copy() -> void:
	var ed := _editor("basic_forage")
	var launched: Array = []
	ed.launch_process = func(exe: String, a: PackedStringArray) -> int:
		launched.append([exe, a])
		return FAKE_PID
	ed.doc.set_at(["seed"], 77)
	ed.timeline.playhead = 4.5
	var saved := LaunchCommands.RUN_DEFAULTS.duplicate()
	saved["from_playhead"] = true
	saved["layout"] = "nest"
	LaunchSettings.save_for(ed.settings_path, "run", ed.doc.file_path, saved)
	ed._on_run_menu(ScenarioEditor.RunItem.RUN)
	check_eq(launched.size(), 1, "launched once")
	var copy := ProjectSettings.globalize_path(ed.runs_dir.path_join("run/basic_forage.json"))
	check_eq(launched[0][0], ed.godot_path, "the editor's Godot")
	check_eq(launched[0][1], LaunchCommands.run_args(saved, copy, ed.project_dir, 4.5), "run arguments")
	check_eq(int(ScenarioJson.load_file(copy)["seed"]), 77, "the copy has the unsaved edit")
	check_eq(int(ScenarioJson.load_file("res://scenarios/basic_forage.json")["seed"]), 1, "the file is untouched")
	check_eq(ed.run_pid, FAKE_PID, "running")
	check(ed.status.text.contains("Running"), "status: " + ed.status.text)
	ed._process(0.0)
	check_eq(ed.run_pid, -1, "a process that isn't running is forgotten")
	ed.launch_process = func(_exe: String, _a: PackedStringArray) -> int: return -1
	ed.run()
	check_eq(ed.run_pid, -1, "failed launch")
	# Run options: the dialog's settings are remembered and run.
	ed.launch_process = func(exe: String, a: PackedStringArray) -> int:
		launched.append([exe, a])
		return FAKE_PID
	var s := LaunchCommands.RUN_DEFAULTS.duplicate()
	s["debug"] = true
	ed.run_dialog.run_requested.emit(s)
	check_eq(LaunchSettings.load_for(ed.settings_path, "run", ed.doc.file_path, LaunchCommands.RUN_DEFAULTS), s,
			"remembered")
	check(launched[-1][1].has("--debug=1"), "ran with them")
	ed.stop_run()
	check_eq(ed.run_pid, -1, "stopped")
	ed.free()
	_cleanup()

func test_editor_untitled_copy_name() -> void:
	var ed := _editor("")
	check_eq(ed.run_name(), "untitled", "template name")
	ed.doc.set_at(["name"], "My test run")
	check_eq(ed.run_name(), "My_test_run", "from the scenario name")
	ed.free()
	_cleanup()

func test_editor_record_plan_and_output_size() -> void:
	var ed := _editor("basic_forage")
	var s := LaunchCommands.RECORD_DEFAULTS.duplicate()
	s["format"] = "avi"
	s["size"] = "1920x1080"
	s["end"] = 2.0
	var job := ed.start_recording(s, true)
	check(job != null and job == ed.record_job, "a job")
	check_eq(ed.doc.get_at(["output", "size"]), [1920, 1080], "set as the scenario's output size")
	ed.doc.undo()
	check(not ed.doc.has_at(["output"]), "one undoable edit")
	var copy := ProjectSettings.globalize_path(ed.runs_dir.path_join("record/basic_forage.json"))
	check_eq(job.plan["record_args"][8], "--scenario=" + copy, "records the copy")
	check(job.plan["name"].begins_with("basic_forage_seed1_1920x1080_"), job.plan["name"])
	check_eq(job.plan["out_dir"], ed.project_dir.path_join("renders"), "renders/ in the project")
	check_eq(job.stage, RecordJob.Stage.FAILED, "no such Godot")
	check(not FileAccess.file_exists(ed.project_dir.path_join("override.cfg")), "override.cfg removed")
	check_eq(LaunchSettings.load_for(ed.settings_path, "record", ed.doc.file_path, LaunchCommands.RECORD_DEFAULTS), s,
			"remembered")
	check(ed.status.text.contains("Can't start Godot"), "status: " + ed.status.text)
	ed.free()
	_cleanup()

# --- end to end (long) -----------------------------------------------------------------

## tools/record.gd on a scenario path records a draft of the requested size,
## 60 fps and length (ffprobe). Opens a window: tools/test.sh --long test_record_pipeline_draft.
func test_record_pipeline_draft() -> void:
	if not OS.get_cmdline_user_args().has("--long"):
		print("    (long: pass --long to run)")
		return
	var dir := _dir()
	var scenario := dir.path_join("draft_forage.json")
	_copy("basic_forage", scenario)
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tools/record.gd", "--", scenario, "3", "2", "--format=avi", "--size=1920x1080",
			"--out_dir=" + dir, "--out=draft.mp4"], out, true)
	check_eq(code, 0, "pipeline exit code; output:\n" + "".join(out).right(2000))
	var video := dir.path_join("draft.mp4")
	check(FileAccess.file_exists(video), "wrote the video")
	check_eq(DirAccess.get_directories_at(dir), PackedStringArray(), "capture folder removed")
	_check_video(video, "width=1920|height=1080", 120)
	check(not FileAccess.file_exists(ProjectSettings.globalize_path("res://override.cfg")), "override.cfg removed")
	_cleanup()

## The editor's Record (an unsaved edit included) through the real pipeline:
## tools/test.sh --long test_record_from_the_editor.
func test_record_from_the_editor() -> void:
	if not OS.get_cmdline_user_args().has("--long"):
		print("    (long: pass --long to run)")
		return
	var ed := _editor("basic_forage")
	ed.project_dir = ProjectSettings.globalize_path("res://").trim_suffix("/")
	ed.godot_path = ""
	ed.doc.set_at(["seed"], 11)
	var s := LaunchCommands.RECORD_DEFAULTS.duplicate()
	s["format"] = "avi"
	s["end"] = 2.0
	s["out_dir"] = _dir()
	s["file_name"] = "editor.mp4"
	var job := ed.start_recording(s)
	check(job.wait(300000), "recorded: " + job.message + "\n" + "\n".join(job.log_lines.slice(-20)))
	check(job.plan["name"].begins_with("basic_forage_seed11_"), job.plan["name"])
	_check_video(_dir().path_join("editor.mp4"), "width=1080|height=1920", 120)
	ed.free()
	_cleanup()

func _check_video(video: String, size: String, frames: int) -> void:
	var probe: Array = []
	OS.execute("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
			"stream=width,height,r_frame_rate,nb_frames", "-show_entries", "format=duration", "-of", "compact", video], probe)
	var info := "".join(probe)
	check(info.contains(size), size + ": " + info)
	check(info.contains("r_frame_rate=60/1"), "60 fps: " + info)
	check(info.contains("nb_frames=%d" % frames), "%d frames: %s" % [frames, info])
