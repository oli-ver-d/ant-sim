extends TestCase
## M16f: the editor preview's partial rebuilds. Redoing only the ground and
## the scatters on a kept sim must give the same sim as building the edited
## document from scratch: same surface cells, props and ground, same state
## hash after a few ticks. One test per scenario so they run in parallel.

const TICKS := 20

func test_rebuild_kind() -> void:
	var base := {"seed": 1, "colonies": [{"species": "a", "nest": [1, 2]}], "ground": "soil",
			"scenery": [{"type": "rock", "center": [5, 5], "radius": 10}, {"scatter": {"preset": "meadow"}}],
			"render": {"pheromones": true}, "camera": [{"t": 0, "pos": [1, 1]}]}
	check_eq(EditorPreview.rebuild_kind({}, base), "full", "nothing built yet")
	check_eq(EditorPreview.rebuild_kind(base, base.duplicate(true)), "view", "same document")
	var d := base.duplicate(true)
	d["render"]["pheromones"] = false
	d["camera"][0]["zoom"] = 2
	d["output"] = {"size": [1920, 1080]}
	check_eq(EditorPreview.rebuild_kind(base, d), "view", "render, camera and output only")
	d = base.duplicate(true)
	d["ground"] = {"base": "sand", "regions": []}
	check_eq(EditorPreview.rebuild_kind(base, d), "scatter", "ground")
	d = base.duplicate(true)
	d.erase("ground")
	check_eq(EditorPreview.rebuild_kind(base, d), "scatter", "ground removed")
	d = base.duplicate(true)
	d["scenery"][1]["scatter"]["density"] = 2
	check_eq(EditorPreview.rebuild_kind(base, d), "scatter", "scatter option")
	d["scenery"].append({"scatter": {"preset": "rocky"}})
	d["ground"] = "moss"
	check_eq(EditorPreview.rebuild_kind(base, d), "scatter", "scatter added, ground")
	d = base.duplicate(true)
	d["scenery"][0]["radius"] = 12
	check_eq(EditorPreview.rebuild_kind(base, d), "full", "hand-placed prop")
	d = base.duplicate(true)
	d["scenery"].reverse()
	check_eq(EditorPreview.rebuild_kind(base, d), "scatter", "hand props in the same order")
	d = base.duplicate(true)
	d["scenery"] = "oops"
	check_eq(EditorPreview.rebuild_kind(base, d), "full", "not a list")
	for key: String in ["seed", "colonies", "food", "obstacles", "debris", "events", "max_agents"]:
		d = base.duplicate(true)
		d[key] = 7
		check_eq(EditorPreview.rebuild_kind(base, d), "full", key)
	d = base.duplicate(true)
	d["seed"] = 1.0
	check_eq(EditorPreview.rebuild_kind(base, d), "full", "an int that became a float counts as a change")

## M16j: a world edit is a full rebuild; the preview's bounds follow the document at once.
func test_world_size_edit_is_a_full_rebuild() -> void:
	var base := {"seed": 1, "colonies": [{"species": "a", "nest": [1, 2]}], "ground": "soil"}
	var d := base.duplicate(true)
	d["world"] = {"size": [1920, 1080]}
	check_eq(EditorPreview.rebuild_kind(base, d), "full", "world added")
	var e := d.duplicate(true)
	e["world"]["size"] = [2160, 3840]
	check_eq(EditorPreview.rebuild_kind(d, e), "full", "world size changed")
	var data := ScenarioLoader.load_data("basic_forage")
	var preview := _preview()
	preview.show_data(data, true)
	check_eq(preview.world_size(), Vector2(1080, 1920), "default world")
	check_eq(preview.sim.world.size, Vector2i(1080, 1920), "default sim world")
	var edited := data.duplicate(true)
	edited["world"] = {"size": [1920, 1080]}
	preview.show_data(edited)
	check(preview.rebuild_pending(), "rebuild waits")
	check_eq(preview.world_size(), Vector2(1920, 1080), "bounds follow the document before the rebuild")
	preview._process(EditorPreview.REBUILD_DELAY + 0.01)
	check_eq(preview.last_kind, "full", "world edit rebuilds fully")
	check_eq(preview.sim.world.size, Vector2i(1920, 1080), "built sim has the new world")
	preview.free()

func test_truncate_restores_cells() -> void:
	var data := ScenarioLoader.load_data("meadow_forage")
	var registry := Registry.create_default()
	var config: SimConfig = load("res://sim/default_config.tres")
	var sim := ScenarioLoader.build_base(data, registry, config)
	var cells := sim.world.obstacles.duplicate()
	var mask := _mask(sim.world)
	var mark := sim.scenery.mark()
	var results := ScenarioLoader.add_scatters(sim, data)
	check(sim.scenery.props.size() > mark.x, "scatters placed props")
	check(not results.is_empty(), "scatter results by index")
	var blocking := 0
	for p in sim.scenery.props:
		blocking += 1 if p.blocks else 0
	check(blocking > 0, "some scattered props block")
	sim.scenery.truncate(mark)
	check_eq(sim.scenery.mark(), mark, "back at the mark")
	check(sim.world.obstacles == cells, "cells as before the scatters")
	check(_mask(sim.world) == mask, "prop mask as before")

func test_partial_matches_full_basic_forage() -> void:
	_check_partial("basic_forage")

func test_partial_matches_full_meadow_forage() -> void:
	_check_partial("meadow_forage")

func test_partial_matches_full_colony_founding() -> void:
	_check_partial("colony_founding")

func test_partial_matches_full_two_species() -> void:
	_check_partial("two_species")

func test_partial_matches_full_maze() -> void:
	_check_partial("maze")

func test_preview_view_only_keeps_sim() -> void:
	var preview := _preview()
	var data := ScenarioLoader.load_data("basic_forage")
	preview.show_data(data, true)
	var first := preview.sim
	var edited := data.duplicate(true)
	edited["render"] = {"pheromones": false}
	preview.show_data(edited, true)
	check_eq(preview.last_kind, "view", "render only")
	check(preview.sim == first, "same sim")
	check(not preview.view.pheromone_renderer.visible, "new view with the render setting")
	preview.partial = false
	preview.show_data(edited, true)
	check_eq(preview.last_kind, "full", "partial off")
	check(preview.sim != first, "new sim")
	preview.queue_free()

func test_hand_props_and_scatter_results() -> void:
	var preview := _preview()
	var rock := {"type": "rock", "center": [300, 300], "radius": 20}
	var log := {"type": "log", "points": [[600, 600], [760, 640]], "width": 20}
	var data := ScenarioLoader.load_data("basic_forage")
	data["scenery"] = [rock, {"type": "no_such_prop"}, {"scatter": {"preset": "rocky", "density": 0.5}}, log]
	preview.show_data(data, true)
	check(preview.hand_prop(0) != null and preview.hand_prop(0).params == rock, "the rock")
	check(preview.hand_prop(0) != null and not preview.hand_prop(0).cells.is_empty(), "the rock blocks cells")
	check(preview.hand_prop(1) == null, "an unknown type built nothing")
	check(preview.hand_prop(2) == null, "a scatter is not a hand prop")
	check(preview.hand_prop(3) != null and preview.hand_prop(3).params == log, "the log after the scatter")
	check(preview.hand_prop(9) == null, "out of range")
	check_eq(preview.scatter_results.keys(), [2], "results by scenery index")
	var result: Scatter.Result = preview.scatter_results.get(2)
	check(result != null and not result.placed.is_empty(), "the scatter's props")
	if result != null:
		for p: Prop in result.placed:
			check(preview.sim.scenery.props.has(p), "placed props are in the sim")
	preview.queue_free()

func test_scatter_from() -> void:
	var s := [{"type": "rock"}, {"scatter": {"preset": "meadow"}}, {"scatter": {"preset": "rocky"}}]
	var base := {"ground": "soil", "scenery": s}
	var d := base.duplicate(true)
	d["scenery"][2]["scatter"]["seed"] = 3
	check_eq(EditorPreview.scatter_from(base, d), 2, "only the last scatter")
	d["ground"] = "sand"
	check_eq(EditorPreview.scatter_from(base, d), 0, "the ground: all of them")
	d = base.duplicate(true)
	d["scenery"].remove_at(1)
	check_eq(EditorPreview.scatter_from(base, d), 1, "removed")
	d = base.duplicate(true)
	d["scenery"].append({"scatter": {"preset": "sandy"}})
	check_eq(EditorPreview.scatter_from(base, d), 3, "appended")

## Builds `scenario` in a preview, then makes a series of ground and scatter
## edits (each redone on the kept sim) and compares each with a full build:
## the ground and every scatter, the last scatter only, the first scatter
## removed, a scatter appended.
func _check_partial(scenario: String) -> void:
	var preview := _preview()
	var data := ScenarioLoader.load_data(scenario)
	preview.show_data(data, true)
	var kept := preview.sim
	var full: Simulation
	var steps := {"ground and scatters": _edit_ground_and_scatters, "last scatter": _reseed_last,
			"first scatter removed": _remove_first_scatter, "scatter appended": _append_scatter}
	for step: String in steps:
		var edited: Dictionary = (steps[step] as Callable).call(data)
		var from := EditorPreview.scatter_from(data, edited)
		data = edited
		preview.show_data(data, true)
		var what := "%s, %s" % [scenario, step]
		check_eq(preview.last_kind, "scatter", what + ": partial rebuild")
		check_eq(preview.rescattered_from, from, what + ": scattered again from")
		check(preview.sim == kept, what + ": the sim was kept")
		full = ScenarioLoader.build(data, Registry.create_default(), preview.config)
		_compare(preview, full, what)
	# The kept sim now belongs to this test: step both.
	preview.queue_free()
	for i in TICKS:
		kept.step()
		full.step()
	check_eq(kept.state_hash(), full.state_hash(), scenario + ": state hash after %d ticks" % TICKS)

func _compare(preview: EditorPreview, full: Simulation, what: String) -> void:
	var partial := preview.sim
	check(partial.world.obstacles == full.world.obstacles, what + ": surface cells")
	check(_mask(partial.world) == _mask(full.world), what + ": prop mask")
	check_eq(_props(partial), _props(full), what + ": props")
	check((partial.ground == null) == (full.ground == null), what + ": ground")
	if full.ground != null:
		for m in GroundMap.MATERIALS.size():
			check(partial.ground.weights[m] == full.ground.weights[m], what + ": ground " + GroundMap.MATERIALS[m])
	var scatters: Array = []
	var scenery: Array = preview.data.get("scenery", [])
	for k in scenery.size():
		if scenery[k].has("scatter"):
			scatters.append(k)
	var keys := preview.scatter_results.keys()
	keys.sort()
	check_eq(keys, scatters, what + ": a result per scatter")
	for r: Scatter.Result in preview.scatter_results.values():
		check_eq(r.dropped_bounds.size(), r.dropped, what + ": a bound per dropped prop")
		for p: Prop in r.placed:
			if not partial.scenery.props.has(p):
				check(false, what + ": a result's prop is not in the sim")
				break

func _scatter_indices(d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var scenery: Array = d.get("scenery", [])
	for k in scenery.size():
		if scenery[k].has("scatter"):
			out.append(k)
	return out

func _reseed_last(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var ks := _scatter_indices(d)
	d["scenery"][ks[-1]]["scatter"]["seed"] = 9191
	return d

func _remove_first_scatter(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	d["scenery"].remove_at(_scatter_indices(d)[0])
	return d

func _append_scatter(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	d["scenery"].append({"scatter": {"preset": "forest_floor", "density": 0.6, "rect": [0, 0, 1080, 960]}})
	return d

func _edit_ground_and_scatters(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var region := {"material": "moss", "shape": "circle", "center": [540, 900], "radius": 260, "soft": 50}
	var ground: Variant = d.get("ground")
	if ground is Dictionary:
		var regions: Array = ground.get("regions", [])
		regions.append(region)
		ground["regions"] = regions
	else:
		d["ground"] = {"base": ground if ground is String else "sand", "regions": [region]}
	var scenery: Array = d.get("scenery", [])
	var any := false
	for e: Dictionary in scenery:
		if e.has("scatter"):
			e["scatter"]["seed"] = 4242
			e["scatter"]["density"] = float(e["scatter"].get("density", 1.0)) * 1.2
			any = true
	if not any:
		scenery.append({"scatter": {"preset": "rocky", "density": 0.5}})
	d["scenery"] = scenery
	return d

func _preview() -> EditorPreview:
	var preview := EditorPreview.new()
	preview.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(preview)
	return preview

## The prop mask, empty read as all zeros.
func _mask(world: World) -> PackedByteArray:
	if not world.prop_mask.is_empty():
		return world.prop_mask
	var m := PackedByteArray()
	m.resize(world.width * world.height)
	return m

func _props(sim: Simulation) -> Array:
	var out := []
	for p in sim.scenery.props:
		out.append([p.id, p.type_id, p.position, p.prop_seed, p.blocks, p.cells, JSON.stringify(p.params)])
	return out
