class_name LaunchSettings
extends RefCounted
## The last Run and Record settings per scenario, kept in the editor settings
## file (not in the scenario: they describe a run, not the scenario). Section
## "run" or "record", key "by_scenario": {scenario key: settings}. The key is
## the document's file path ("" for an unsaved document).

const KEY := "by_scenario"

## `kind`'s settings for `scenario`, over `defaults` (LaunchCommands.RUN_DEFAULTS
## or RECORD_DEFAULTS).
static func load_for(cfg_path: String, kind: String, scenario: String, defaults: Dictionary) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return defaults.duplicate()
	var all: Variant = cfg.get_value(kind, KEY, {})
	if not all is Dictionary or not (all as Dictionary).get(scenario) is Dictionary:
		return defaults.duplicate()
	return LaunchCommands.with_defaults(all[scenario], defaults)

## Remembers `settings` for `scenario`, keeping everything else in the file.
static func save_for(cfg_path: String, kind: String, scenario: String, settings: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)  # a missing file just starts empty
	var all: Variant = cfg.get_value(kind, KEY, {})
	if not all is Dictionary:
		all = {}
	all[scenario] = settings.duplicate()
	cfg.set_value(kind, KEY, all)
	return cfg.save(cfg_path)
