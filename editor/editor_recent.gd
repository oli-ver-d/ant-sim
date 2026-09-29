class_name EditorRecent
extends RefCounted
## The editor's recently opened files, most recent first, kept in the
## "recent" section of the editor settings file.

const MAX_FILES := 10

var files: PackedStringArray = []

func add(path: String) -> void:
	remove(path)
	files.insert(0, path)
	while files.size() > MAX_FILES:
		files.remove_at(files.size() - 1)

## Removes `path` (compared normalised by simplify_path()).
func remove(path: String) -> void:
	var key := path.simplify_path()
	var i := files.size() - 1
	while i >= 0:
		if files[i].simplify_path() == key:
			files.remove_at(i)
		i -= 1

func load_from(cfg_path: String = "user://editor_settings.cfg") -> void:
	files = []
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return
	var v: Variant = cfg.get_value("recent", "files", PackedStringArray())
	if v is PackedStringArray or v is Array:
		for p: Variant in v:
			if p is String and p != "" and files.size() < MAX_FILES:
				files.append(p)

## Saves the list, keeping other sections of an existing file.
func save_to(cfg_path: String = "user://editor_settings.cfg") -> Error:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)  # a missing file just starts empty
	cfg.set_value("recent", "files", files)
	return cfg.save(cfg_path)
