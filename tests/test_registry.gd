extends TestCase

const FIXTURE_ROOT := "res://tests/fixtures/species"

func test_register_and_lookup() -> void:
	var reg := Registry.new()
	var b := Behaviour.new()
	check(reg.register_behaviour("idle", b), "first registration succeeds")
	check(reg.get_behaviour("idle") == b, "lookup returns the registered instance")

func test_duplicate_ids_rejected() -> void:
	var reg := Registry.new()
	reg.register_behaviour("idle", Behaviour.new())
	check(not reg.register_behaviour("idle", Behaviour.new()), "duplicate id must be rejected")

func test_discover_modules() -> void:
	var reg := Registry.new()
	check(reg.discover_modules(FIXTURE_ROOT), "fixture modules load without errors")
	check_eq(reg.loaded_modules, PackedStringArray(["dummy"]), "loaded modules")
	check(reg.behaviours.has("dummy_idle"), "module registered its behaviour")

func test_discover_real_species() -> void:
	var reg := Registry.new()
	check(reg.discover_modules(), "all species modules under res://species load")
