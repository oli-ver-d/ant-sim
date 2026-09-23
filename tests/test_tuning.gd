extends TestCase
## M9: live tuning (Simulation.refresh_params and the TuningPanel), and the
## wall-drawing tool's guarantee that no ant ends up inside a wall.
##
## Uses copies of the config and species so the shared resources (and the
## .tres files) are never touched.

## A registry whose leafcutter SpeciesDef is a private deep copy, with no
## resource path so nothing can save over the real file.
func _private_registry() -> Registry:
	var registry := Registry.create_default()
	var species := (registry.species["leafcutter"] as SpeciesDef).duplicate(true) as SpeciesDef
	species.resource_path = ""
	registry.species["leafcutter"] = species
	return registry

func _private_config() -> SimConfig:
	var config := (load("res://sim/default_config.tres") as SimConfig).duplicate() as SimConfig
	config.resource_path = ""
	return config

func test_refresh_params_applies_config_species_and_channel_changes() -> void:
	var config := _private_config()
	var sim := Simulation.new(config, _private_registry(), 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1400))
	var home := colony.channels[&"home"]
	config.wander_strength = 3.5
	colony.species.tunables["bite_radius"] = 9.0
	colony.species.channels[0].half_life = 5.0
	sim.refresh_params()
	check_eq(colony.wander_strength, 3.5, "config change reaches the colony's cached params")
	check_eq(colony.params[&"bite_radius"], 9.0, "species tunable change")
	check(absf(sim.pheromones.decay_per_tick[home] - pow(0.5, sim.dt / 5.0)) < 1e-6, "channel change reaches the field")

func test_refresh_keeps_colony_overrides() -> void:
	var config := _private_config()
	var sim := Simulation.new(config, _private_registry(), 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1400), {},
			{"params": {"wander_strength": 1.25}, "channels": {"home": {"half_life": 60.0}}})
	config.wander_strength = 3.5
	sim.refresh_params()
	check_eq(colony.wander_strength, 1.25, "scenario override still wins")
	check(absf(sim.pheromones.decay_per_tick[colony.channels[&"home"]] - pow(0.5, sim.dt / 60.0)) < 1e-6, "channel override kept")

func test_new_wall_pushes_ants_out() -> void:
	var sim := Simulation.new(_private_config(), _private_registry(), 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1400))
	var ants: PackedInt32Array = []
	for k in 20:
		ants.append(sim.spawn_ant(colony, 1, Vector2(400 + k * 2.0, 700 + k), 0.0))
	sim.world.draw_polyline(PackedVector2Array([Vector2(380, 690), Vector2(460, 730)]), 16.0, World.Cell.WALL)
	check(SimChecks.ants_in_obstacles(sim) > 0, "the wall landed on ants")
	var moved := sim.evict_ants_from_obstacles()
	check(moved > 0, "moved %d ants" % moved)
	check_eq(SimChecks.ants_in_obstacles(sim), 0, "no ant inside the wall")
	for i in ants:
		check(sim.pos[i].distance_to(Vector2(400 + (i - ants[0]) * 2.0, 700 + (i - ants[0]))) < 30.0, "moved only a short way")

func test_tuning_panel_sliders_edit_live_and_reset() -> void:
	var config := _private_config()
	var registry := _private_registry()
	var sim := Simulation.new(config, registry, 1)
	var colony := sim.add_colony("leafcutter", Vector2(540, 1400))
	var panel := TuningPanel.new()
	panel.setup(sim, registry)
	# In the scene tree, as in the app.
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	check_eq(panel.food_type, "leaf", "first food type of the selected species")
	var slider := _find_slider(panel, "wander_strength")
	check(slider != null, "slider for a SimConfig value")
	var structural := _find_slider(panel, "tick_rate")
	check(structural == null, "no slider for structural settings")
	if slider != null:
		# As a drag would (in Godot 4.7 setting `value` from code doesn't emit).
		slider.value = 1.0
		slider.value_changed.emit(1.0)
		check_eq(config.wander_strength, 1.0, "slider writes the config")
		check_eq(colony.wander_strength, 1.0, "and the change is live")
	var original := (load("res://sim/default_config.tres") as SimConfig).wander_strength
	panel.call("_reset")
	check_eq(config.wander_strength, original, "reset restores it")
	panel.free()

func _find_slider(panel: Control, title: String) -> HSlider:
	for node in panel.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == title:
			var row := label.get_parent().get_parent()
			for child in row.get_children():
				if child is HSlider:
					return child
	return null

## The interactive scene's mouse tools: left-drag draws a wall (no ant ends up
## inside it), Shift erases, right-click places the selected food type.
func test_mouse_tools_draw_walls_and_place_food() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var sim: Simulation = main.get("sim")
	var from := Vector2(300, 900)
	var to := Vector2(700, 900)
	var world_from: Vector2 = main.call("_world_at", from)
	var world_to: Vector2 = main.call("_world_at", to)
	# Put some ants right where the wall will go.
	for k in 10:
		sim.spawn_ant(sim.colonies[0], 1, world_from.lerp(world_to, k / 10.0), 0.0)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	main.call("_unhandled_input", press)
	var drag := InputEventMouseMotion.new()
	drag.position = to
	main.call("_unhandled_input", drag)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	main.call("_unhandled_input", release)
	check(sim.world.is_blocked(world_from.lerp(world_to, 0.5)), "wall drawn along the drag")
	check_eq(SimChecks.ants_in_obstacles(sim), 0, "ants under the new wall were moved out")

	press.shift_pressed = true
	main.call("_unhandled_input", press)
	main.call("_unhandled_input", release)
	check(not sim.world.is_blocked(world_from), "shift-click erases")

	var sources := sim.food_sources.size()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(540, 600)
	main.call("_unhandled_input", right)
	check_eq(sim.food_sources.size(), sources + 1, "right-click placed food")
	check_eq(sim.food_sources.back().type_id, main.get("tuning").food_type, "of the selected type")
	main.free()

## "Save to .tres" round trip, on a copy saved to user:// (never the real file).
func test_saved_species_reloads_with_tuned_values() -> void:
	var species := (Registry.create_default().species["leafcutter"] as SpeciesDef).duplicate(true) as SpeciesDef
	species.tunables["bite_radius"] = 7.5
	species.channels[0].half_life = 42.0
	var path := "user://test_saved_species.tres"
	check_eq(ResourceSaver.save(species, path), OK, "saved")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpeciesDef
	check(loaded != null, "reloads as a SpeciesDef")
	if loaded != null:
		check_eq(loaded.tunables["bite_radius"], 7.5, "tunable kept")
		check_eq(loaded.channels[0].half_life, 42.0, "channel setting kept")
		check_eq(loaded.castes.size(), species.castes.size(), "castes kept")
		check_eq(loaded.state_params, species.state_params, "wiring kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
