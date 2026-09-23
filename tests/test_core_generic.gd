extends TestCase
## Guards the core/species boundary: /sim and /render must not mention any
## species. Forbidden terms are the fixed list from the spec plus the name of
## every folder under /species, so new species are covered automatically.

const CORE_DIRS: PackedStringArray = ["res://sim", "res://render"]
const SCANNED_EXTENSIONS: PackedStringArray = ["gd", "gdshader", "gdshaderinc", "tscn", "tres", "json", "cfg"]
const FIXED_TERMS: PackedStringArray = ["leaf", "fungus", "cutter", "harvester"]

func test_core_has_no_species_identifiers() -> void:
	var terms := FIXED_TERMS.duplicate()
	for dir_name in DirAccess.get_directories_at(Registry.SPECIES_ROOT):
		if not terms.has(dir_name.to_lower()):
			terms.append(dir_name.to_lower())
	var files: PackedStringArray = []
	for dir in CORE_DIRS:
		_collect_files(dir, files)
	check(files.size() > 0, "expected core source files to scan")
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].to_lower()
			for term in terms:
				if line.contains(term):
					check(false, "%s:%d mentions '%s'" % [path, i + 1, term])

func _collect_files(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if SCANNED_EXTENSIONS.has(file.get_extension()):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect_files(dir.path_join(sub), out)
