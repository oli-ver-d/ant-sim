extends SceneTree
## Headless test runner. Loads every res://tests/test_*.gd, runs its test_*
## methods and exits with code 1 if anything failed.
##
##   godot --headless --path . -s res://tests/run_tests.gd -- [name_filter]
##
## Use tools/test.sh, which also refreshes the class cache first.

const TEST_DIR := "res://tests"

func _initialize() -> void:
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
			var t0 := Time.get_ticks_msec()
			tc.call(method_name)
			var ms := Time.get_ticks_msec() - t0
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
