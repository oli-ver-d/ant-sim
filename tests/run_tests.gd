extends SceneTree
## Headless test runner. Loads every res://tests/test_*.gd, runs its test_*
## methods and exits with code 1 if anything failed.
##
##   godot --headless --path . -s res://tests/run_tests.gd -- [name_filter]
##
## Use tools/test.sh, which also refreshes the class cache first.
##
## Tests run on the first frame (not in _initialize) so the scene tree is fully
## up: tests may add scenes to root and get _ready() as in the app.
## A test fails if it records a failed check or hits a script error (a
## runtime error stops the test function early, which would otherwise look
## like a pass). Engine errors (push_error) don't count: some tests exercise
## error paths on purpose.

const TEST_DIR := "res://tests"

var _started := false
var _errors := ErrorCounter.new()

## Counts script errors reported while tests run.
class ErrorCounter extends Logger:
	var script_errors: int = 0
	var last_message: String = ""

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors += 1
			last_message = rationale if rationale != "" else code

func _initialize() -> void:
	OS.add_logger(_errors)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var name_filter: String = args[0] if args.size() > 0 else ""
	var passed := 0
	var failed := 0
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	var t_start := Time.get_ticks_msec()

	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script := load(TEST_DIR.path_join(file)) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL  %s (failed to load - parse error?)" % file)
			continue
		var tc := script.new() as TestCase
		if tc == null:
			failed += 1
			print("FAIL  %s (does not extend TestCase)" % file)
			continue
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var full_name := "%s::%s" % [file.get_basename(), method_name]
			if name_filter != "" and not full_name.contains(name_filter):
				continue
			tc.current_test = full_name
			var failures_before := tc.failures.size()
			var errors_before := _errors.script_errors
			var t0 := Time.get_ticks_msec()
			tc.call(method_name)
			var ms := Time.get_ticks_msec() - t0
			if _errors.script_errors > errors_before:
				tc.failures.append("%s: script error (%s)" % [full_name, _errors.last_message])
			if tc.failures.size() == failures_before:
				passed += 1
				print("PASS  %s (%d ms)" % [full_name, ms])
			else:
				failed += 1
				print("FAIL  %s (%d ms)" % [full_name, ms])
				for i in range(failures_before, tc.failures.size()):
					print("      - " + tc.failures[i])

	print("\n%d passed, %d failed in %.1f s" % [passed, failed, (Time.get_ticks_msec() - t_start) / 1000.0])
	quit(1 if failed > 0 else 0)
