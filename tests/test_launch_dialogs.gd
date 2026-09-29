extends TestCase
## M16h: the editor's Run options and Record dialogs (RunDialog, RecordDialog):
## settings round trips, widget enabling, the size widget, the summary and the
## progress page of a RecordJob.

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root

func _data() -> Dictionary:
	return {"duration": 20, "seed": 3, "output": {"size": [1920, 1080]}}

func _run_dialog() -> RunDialog:
	var d := RunDialog.new()
	_root().add_child(d)
	return d

func _record_dialog(settings: Dictionary = {}) -> RecordDialog:
	var d := RecordDialog.new()
	_root().add_child(d)
	d.open(settings, "res://scenarios/foo.json", _data(), "C:/proj")
	return d

func _free(d: Node) -> void:
	d.hide()
	d.queue_free()

func test_run_defaults_round_trip() -> void:
	var d := _run_dialog()
	d.open({}, Vector2i(1080, 1920), 12.5)
	check_eq(d.read(), LaunchCommands.RUN_DEFAULTS, "defaults")
	check_eq(d.fields["from_playhead"].text, "From playhead (12.5 s)", "playhead label")
	_free(d)

func test_run_all_options_round_trip() -> void:
	var d := _run_dialog()
	var s := {"seed_mode": "fixed", "seed": 77, "at": 4.5, "from_playhead": false, "layout": "split",
		"size": "1920x1080", "captions": false, "safe": true, "pheromones": false, "debug": true, "tuning": true}
	d.open(s, Vector2i(1080, 1920), 0.0)
	check_eq(d.read(), s, "preset size")
	s["size"] = "800x600"
	s["seed_mode"] = "random"
	s["layout"] = "nest"
	s["from_playhead"] = true
	d.open(s, Vector2i(1080, 1920), 3.0)
	check_eq(d.read(), s, "custom size, random, nest, from playhead")
	s["layout"] = "normal"
	d.open(s, Vector2i(1080, 1920), 3.0)
	check_eq(d.read()["layout"], "normal", "surface")
	_free(d)

func test_run_widget_enabling() -> void:
	var d := _run_dialog()
	d.open({"seed_mode": "scenario"}, Vector2i(1080, 1920), 1.0)
	check(not d.fields["seed"].editable, "seed disabled for scenario")
	d.open({"seed_mode": "random"}, Vector2i(1080, 1920), 1.0)
	check(not d.fields["seed"].editable, "seed disabled for random")
	d.open({"seed_mode": "fixed"}, Vector2i(1080, 1920), 1.0)
	check(d.fields["seed"].editable, "seed enabled for fixed")
	check(d.fields["at"].editable, "at enabled")
	d.open({"from_playhead": true}, Vector2i(1080, 1920), 1.0)
	check(not d.fields["at"].editable, "at disabled by from playhead")
	check(not d.fields["size_custom"].editable, "custom size disabled")
	d.open({"size": "800x600"}, Vector2i(1080, 1920), 1.0)
	check(d.fields["size_custom"].editable, "custom size enabled")
	_free(d)

func test_run_requested_emits_read() -> void:
	var d := _run_dialog()
	d.open({"seed_mode": "fixed", "seed": 5}, Vector2i(1080, 1920), 0.0)
	var got: Array = []
	d.run_requested.connect(func(s: Dictionary) -> void: got.append(s))
	d.confirmed.emit()
	check_eq(got.size(), 1, "emitted once")
	check_eq(got[0], d.read(), "settings")
	check_eq(got[0]["seed"], 5, "seed")
	_free(d)

func test_record_defaults_round_trip() -> void:
	var d := _record_dialog()
	check_eq(d.read(), LaunchCommands.RECORD_DEFAULTS, "defaults")
	check(not d.fields["end"].editable, "end disabled when whole")
	check(not d.fields["mjpeg_quality"].editable, "quality only for avi")
	check_eq(d.get_ok_button().text, "Record", "ok text")
	_free(d)

func test_record_all_options_round_trip() -> void:
	var s := {"format": "avi", "mjpeg_quality": 0.75, "size": "1000x600", "seed": 7, "start": 2.5,
		"end": 9.5, "captions": false, "out_dir": "renders/x", "file_name": "clip.mp4", "keep_frames": true}
	var d := _record_dialog(s)
	check_eq(d.read(), s, "all changed, custom size")
	check(d.fields["end"].editable, "end enabled")
	check(d.fields["mjpeg_quality"].editable, "quality enabled for avi")
	check(d.fields["size_custom"].editable, "custom size editable")
	s["size"] = "1080x1080"
	d.open(s, "res://scenarios/foo.json", _data(), "C:/proj")
	check_eq(d.read(), s, "preset size")
	_free(d)

func test_record_size_widget_mapping() -> void:
	var opt := OptionButton.new()
	var custom := LineEdit.new()
	RecordDialog.fill_size_options(opt, Vector2i(640, 360))
	check_eq(opt.item_count, OutputFrame.PRESETS.size() + 2, "items")
	check_eq(opt.get_item_text(0), "Scenario's (640x360)", "first item")
	RecordDialog.select_size(opt, custom, "")
	check_eq(opt.selected, 0, "empty -> first")
	check_eq(RecordDialog.size_from(opt, custom), "", "value empty")
	check(not custom.editable, "custom off")
	RecordDialog.select_size(opt, custom, "1920x1080")
	check(opt.selected > 0 and opt.selected < opt.item_count - 1, "preset selected")
	check_eq(RecordDialog.size_from(opt, custom), "1920x1080", "preset value")
	check_eq(opt.get_item_text(opt.selected), "landscape 1920x1080", "preset text")
	RecordDialog.select_size(opt, custom, "1234x566")
	check_eq(opt.selected, opt.item_count - 1, "custom selected")
	check_eq(RecordDialog.size_from(opt, custom), "1234x566", "custom value")
	check(custom.editable, "custom on")
	opt.free()
	custom.free()

func test_record_set_output_enabled_only_when_different() -> void:
	var d := _record_dialog()
	check(d.fields["set_output"].disabled, "same size (scenario's)")
	check(not d.set_output_requested(), "not requested")
	d.fields["size"].select(1)
	d.fields["size"].item_selected.emit(1)
	check_eq(d.read()["size"], "1080x1920", "portrait")
	check(not d.fields["set_output"].disabled, "differs from 1920x1080")
	d.fields["set_output"].button_pressed = true
	check(d.set_output_requested(), "requested")
	d.open({"size": "1920x1080"}, "res://scenarios/foo.json", _data(), "C:/proj")
	check(d.fields["set_output"].disabled, "preset equal to the document's size")
	check(not d.set_output_requested(), "disabled box is not requested")
	_free(d)

func test_record_summary_and_bad_size() -> void:
	var d := _record_dialog({"start": 0.0, "end": 5.0})
	check(d.summary.text.begins_with("1920x1080, 300 frames (5 s) -> "), "summary: %s" % d.summary.text)
	check(d.summary.text.contains("foo_seed3"), "out path: %s" % d.summary.text)
	var got: Array = []
	d.record_requested.connect(func(s: Dictionary, o: bool) -> void: got.append([s, o]))
	d.fields["size"].select(d.fields["size"].item_count - 1)
	d.fields["size"].item_selected.emit(d.fields["size"].item_count - 1)
	d.fields["size_custom"].text = "1001x500"
	d.fields["size_custom"].text_changed.emit("1001x500")
	check(d.summary.text.contains("even"), "error shown: %s" % d.summary.text)
	d.confirmed.emit()
	check_eq(got.size(), 0, "not emitted for a bad size")
	d.fields["size_custom"].text = "1000x500"
	d.fields["size_custom"].text_changed.emit("1000x500")
	check(d.summary.text.begins_with("1000x500, 300 frames"), "summary again: %s" % d.summary.text)
	d.fields["set_output"].button_pressed = true
	d.confirmed.emit()
	check_eq(got.size(), 1, "emitted")
	check_eq(got[0][0]["size"], "1000x500", "settings size")
	check_eq(got[0][1], true, "set_output")
	_free(d)

func test_record_end_before_start_is_an_error() -> void:
	var d := _record_dialog({"start": 6.0, "end": 5.0})
	check(d.summary.text.contains("End must be after start"), d.summary.text)
	_free(d)

func _job(stage: RecordJob.Stage) -> RecordJob:
	var plan := LaunchCommands.record_plan({"out_dir": "user://_test_dialogs", "size": "1000x500"},
			"res://scenarios/foo.json", _data(), "C:/proj", "t")
	var job := RecordJob.new()
	job.plan = plan
	job.stage = stage
	job.frames_total = 100
	job.frames_done = 25
	return job

func test_record_progress_page() -> void:
	var d := _record_dialog()
	var job := _job(RecordJob.Stage.RECORDING)
	job.log_lines.append("first line")
	d.show_job(job)
	check(d.status.get_parent().visible, "progress page visible")
	check(not d.summary.get_parent().visible, "settings page hidden")
	check_eq(d.status.text, "Recording frame 25 / 100", "status")
	check(absf(d.progress.value - 0.25) < 1e-6, "progress %s" % d.progress.value)
	check(d.log.text.contains("first line"), "existing log")
	check(d.cancel_button.visible, "cancel visible while running")
	check(not d.get_ok_button().visible, "ok hidden while running")
	job.output.emit("a new line")
	check(d.log.text.contains("a new line"), "appended")
	job.frames_done = 50
	d._process(0.0)
	check(absf(d.progress.value - 0.5) < 1e-6, "progress updated")
	job.stage = RecordJob.Stage.DONE
	job.message = "Wrote x.mp4"
	job.finished.emit(true, "Wrote x.mp4")
	check_eq(d.result.text, "Wrote x.mp4", "result")
	check(d.result.visible and d.open_folder_button.visible and d.play_button.visible, "result buttons")
	check(not d.cancel_button.visible, "cancel hidden")
	check(d.new_button.visible, "new recording")
	d.new_button.pressed.emit()
	check(d.summary.get_parent().visible, "back to settings")
	check(not d.status.get_parent().visible, "progress hidden")
	job.output.emit("ignored after leaving")
	check(not d.log.text.contains("ignored"), "disconnected from the job")
	_free(d)

func test_record_progress_failed_and_switching_jobs() -> void:
	var d := _record_dialog()
	var old := _job(RecordJob.Stage.RECORDING)
	d.show_job(old)
	var failed := _job(RecordJob.Stage.FAILED)
	failed.message = "The recorder exited with code 1"
	d.show_job(failed)
	check_eq(d.result.text, "The recorder exited with code 1", "failed result shown at once")
	check(not d.open_folder_button.visible and not d.play_button.visible, "no open/play when failed")
	old.output.emit("from the old job")
	check(not d.log.text.contains("old job"), "old job disconnected")
	_free(d)

func test_record_log_is_capped() -> void:
	var d := _record_dialog()
	var job := _job(RecordJob.Stage.RECORDING)
	d.show_job(job)
	for i in RecordDialog.MAX_LOG_LINES + 50:
		job.output.emit("line %d" % i)
	check(d.log.get_line_count() <= RecordDialog.MAX_LOG_LINES, "capped: %d" % d.log.get_line_count())
	check(d.log.text.contains("line %d" % (RecordDialog.MAX_LOG_LINES + 49)), "newest kept")
	_free(d)
