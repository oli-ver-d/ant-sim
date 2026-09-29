class_name RecordJob
extends RefCounted
## Runs a recording planned by LaunchCommands.record_plan, in GDScript so it
## needs nothing but Godot and ffmpeg (no bash): the same steps as the old
## tools/record.sh + tools/encode.sh, giving the same files.
##
##   1. writes the plan's override.cfg into the project (Movie Maker records
##      at the window size fixed at startup; removed as soon as the recorder
##      reports, and always at the end),
##   2. runs res://scenes/record.tscn under Movie Maker at 60 fps in a child
##      Godot (plan.record_args), reading its "frame n / total" lines,
##   3. encodes the capture with ffmpeg (plan.encode_args) to plan.out_path,
##      reading "frame=n" from -progress, then removes the capture folder
##      unless plan.keep_frames.
##
## Nothing blocks: call poll() every frame (the editor) or wait() (tools/record.gd,
## tests). cancel() kills the running step and removes partial output.

signal output(line: String)
signal finished(ok: bool, message: String)

enum Stage { IDLE, RECORDING, ENCODING, DONE, FAILED, CANCELLED }

const STAGE_NAMES := ["idle", "recording", "encoding", "done", "failed", "cancelled"]

var plan: Dictionary = {}
var stage := Stage.IDLE
var project_dir := ""
var godot_path := ""
var ffmpeg_path := "ffmpeg"
## Video frames the recorder will write / has written.
var frames_total := 0
var frames_done := 0
## Frames ffmpeg has encoded.
var frames_encoded := 0
## Every output line of both steps, and the final message.
var log_lines: PackedStringArray = []
var message := ""

var _pid := -1
var _pipes: Array[FileAccess] = []
## Unfinished last line per pipe.
var _partial: PackedStringArray = ["", ""]
var _override_path := ""

## Starts the recording. `godot` defaults to this Godot's executable. Returns
## false (with `message` set and `finished` emitted) if it can't start.
func start(record_plan: Dictionary, project: String, godot: String = "", ffmpeg: String = "ffmpeg") -> bool:
	plan = record_plan
	project_dir = project
	godot_path = godot if godot != "" else OS.get_executable_path()
	ffmpeg_path = ffmpeg if ffmpeg != "" else "ffmpeg"
	frames_total = int(plan.get("expected_frames", 0))
	if not plan.get("ok", false):
		return _fail(str(plan.get("error", "Bad record settings")))
	_override_path = project_dir.path_join("override.cfg")
	if FileAccess.file_exists(_override_path):
		_override_path = ""
		return _fail("override.cfg already exists in the project: another recording may be running (delete it if not)")
	if DirAccess.make_dir_recursive_absolute(plan["capture_dir"]) != OK:
		return _fail("Can't create %s" % plan["capture_dir"])
	var cfg := FileAccess.open(_override_path, FileAccess.WRITE)
	if cfg == null:
		_override_path = ""
		return _fail("Can't write %s" % project_dir.path_join("override.cfg"))
	cfg.store_string(plan["override_cfg"])
	cfg.close()
	_line("Recording %s (%s, %s) -> %s" % [plan["name"], plan["format"],
			LaunchCommands.size_label(plan["frame_size"]), plan["capture_dir"]])
	if not _launch(godot_path, plan["record_args"]):
		return _fail("Can't start Godot (%s)" % godot_path)
	stage = Stage.RECORDING
	return true

func is_running() -> bool:
	return stage == Stage.RECORDING or stage == Stage.ENCODING

## Progress of the current step, 0..1.
func fraction() -> float:
	var done := frames_done if stage == Stage.RECORDING else frames_encoded
	if stage == Stage.DONE:
		return 1.0
	return clampf(float(done) / frames_total, 0.0, 1.0) if frames_total > 0 else 0.0

## "Recording frame 120 / 1800", "Encoding ...", or the final message.
func status_text() -> String:
	match stage:
		Stage.RECORDING:
			return "Recording frame %d / %d" % [frames_done, frames_total]
		Stage.ENCODING:
			return "Encoding frame %d / %d" % [frames_encoded, frames_total]
		Stage.IDLE:
			return ""
	return message

## Reads the running step's output and moves on when it exits.
func poll() -> void:
	if not is_running():
		return
	_read_pipes()
	if OS.is_process_running(_pid):
		return
	_read_pipes()
	_flush_partial()
	var code := OS.get_process_exit_code(_pid)
	_close_pipes()
	if stage == Stage.RECORDING:
		_remove_override()
		if code != 0:
			_fail("The recorder exited with code %d" % code)
			return
		if not _capture_exists():
			_fail("The recorder wrote no frames")
			return
		_line("Encoding -> %s" % plan["out_path"])
		if not _launch(ffmpeg_path, plan["encode_args"]):
			_fail("Can't start ffmpeg (%s): install it or set its path" % ffmpeg_path)
			return
		stage = Stage.ENCODING
	elif stage == Stage.ENCODING:
		if code != 0:
			_fail("ffmpeg exited with code %d" % code)
			return
		if not plan.get("keep_frames", false):
			remove_tree(plan["capture_dir"])
		stage = Stage.DONE
		message = "Wrote %s" % plan["out_path"]
		_line(message)
		finished.emit(true, message)

## Polls until the job ends or `timeout_ms` passes (0 = no limit). Returns
## whether it succeeded.
func wait(timeout_ms: int = 0) -> bool:
	var until := Time.get_ticks_msec() + timeout_ms
	while is_running():
		poll()
		if timeout_ms > 0 and Time.get_ticks_msec() > until:
			cancel()
			message = "Timed out"
			return false
		OS.delay_msec(20)
	return stage == Stage.DONE

## Kills the running step and removes the capture and any partial video.
func cancel() -> void:
	if not is_running():
		return
	_kill_and_wait()
	_close_pipes()
	_remove_override()
	# A killed process's files can stay locked for a moment after it has gone.
	var until := Time.get_ticks_msec() + 3000
	while true:
		remove_tree(plan["capture_dir"])
		if FileAccess.file_exists(plan["out_path"]):
			DirAccess.remove_absolute(plan["out_path"])
		if (not DirAccess.dir_exists_absolute(plan["capture_dir"]) and not FileAccess.file_exists(plan["out_path"])) \
				or Time.get_ticks_msec() > until:
			break
		OS.delay_msec(50)
	stage = Stage.CANCELLED
	message = "Cancelled"
	_line(message)
	finished.emit(false, message)

## Deletes a folder and everything in it (no-op if it doesn't exist).
static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)

## Kills the running step and waits (up to 5 s) until it has exited: Windows
## keeps a killed process's files open until then, so they couldn't be removed.
func _kill_and_wait() -> void:
	if _pid <= 0 or not OS.is_process_running(_pid):
		return
	OS.kill(_pid)
	var until := Time.get_ticks_msec() + 5000
	while OS.is_process_running(_pid) and Time.get_ticks_msec() < until:
		OS.delay_msec(10)

func _launch(exe: String, args: PackedStringArray) -> bool:
	var info := OS.execute_with_pipe(exe, args, false)
	if info.is_empty() or int(info.get("pid", -1)) <= 0:
		return false
	_pid = int(info["pid"])
	_pipes = [info["stdio"], info["stderr"]]
	_partial = ["", ""]
	return true

func _read_pipes() -> void:
	for i in _pipes.size():
		var pipe := _pipes[i]
		while true:
			var chunk := pipe.get_buffer(4096)
			if chunk.is_empty():
				break
			var text := _partial[i] + chunk.get_string_from_utf8().replace("\r", "")
			var lines := text.split("\n")
			_partial[i] = lines[lines.size() - 1]
			for k in lines.size() - 1:
				_on_line(lines[k])

func _flush_partial() -> void:
	for i in _partial.size():
		if _partial[i] != "":
			_on_line(_partial[i])
			_partial[i] = ""

func _close_pipes() -> void:
	for pipe in _pipes:
		pipe.close()
	_pipes = []
	_pid = -1

var _frames_re := RegEx.create_from_string("frame (\\d+) / (\\d+)")
var _total_re := RegEx.create_from_string("^Recording .*: (\\d+) frames")

func _on_line(text: String) -> void:
	if stage == Stage.ENCODING:
		# -progress key=value lines: keep the frame count, log nothing else.
		if text.begins_with("frame="):
			frames_encoded = int(text.substr(6))
		elif not text.contains("="):
			_line(text)
		return
	var m := _total_re.search(text)
	if m != null:
		frames_total = int(m.get_string(1))
		# The recorder's window is open: it has read override.cfg.
		_remove_override()
	m = _frames_re.search(text)
	if m != null:
		frames_done = int(m.get_string(1))
	if text.strip_edges() != "":
		_line(text)

func _line(text: String) -> void:
	log_lines.append(text)
	output.emit(text)

func _capture_exists() -> bool:
	if plan["format"] == "avi":
		return FileAccess.file_exists(plan["capture"])
	return FileAccess.file_exists(str(plan["capture_dir"]).path_join("frame00000000.png"))

func _remove_override() -> void:
	if _override_path != "" and FileAccess.file_exists(_override_path):
		DirAccess.remove_absolute(_override_path)
	_override_path = ""

func _fail(why: String) -> bool:
	_kill_and_wait()
	_close_pipes()
	_remove_override()
	stage = Stage.FAILED
	message = why
	_line(why)
	finished.emit(false, why)
	return false
