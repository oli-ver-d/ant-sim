extends TestCase
## M11a: layers, portals, diggable soil, navigation fields, digging and
## carrying spoil, and single-layer runs staying exactly as they were.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := _make_registry()

## The default registry plus "digger": a minimal species on a BasicNest whose
## one caste can dig once its nest has an underground, so these core tests
## don't depend on any real species' nest.
static func _make_registry() -> Registry:
	var reg := Registry.create_default()
	var caste := CasteDef.new()
	caste.id = &"worker"
	caste.size = 6.0
	caste.speed = 32.0
	caste.states = PackedStringArray(["linger"])
	caste.underground_states = PackedStringArray(["dig", "carry_spoil"])
	caste.initial_state = "linger"
	var home := PheromoneChannelDef.new()
	home.name = &"home"
	var def := SpeciesDef.new()
	def.id = &"digger"
	def.castes = [caste]
	def.channels = [home]
	def.nest_type = "basic_nest"
	def.state_params = {"dig": {"on_idle": "linger"}}
	reg.register_species("digger", def)
	return reg

## State hashes of every scenario after 300 ticks, recorded before layers
## existed (M10). Scenarios that don't opt in must not change at all.
const SINGLE_LAYER_HASHES := {
	"basic_forage": "e53696a07f9ff675849cb982690502e55d57b017ced4f9b5fd533b07a89f3fd5",
	"chaos_to_highway": "b6ec7c99ff149756be87ffe9fec2a5fd0af076f61b62b250d0a3e79ed9627027",
	"fungus_farm": "2837e1d69e40eb4767b51ebd8b692085fc269b7814b751742ef8c17ad3274f1f",
	"leaf_strip": "5c1a81409a55a320eb50af8fdce1366e64c2318b7326fb5542be26dc3c6f3c08",
	"maze": "076f93a77045531f20407c7ea65436ff5c90a49d43a49798752c817b3cec1616",
	"rain_reset": "8d10e033483c970be3a0c896bc99fc7a82375bff8fa4b2fbc9d28e29c76da7c4",
	"trunk_trail": "d85339b22264dd873a9869b83f5c194360f2037c1298312dd81f3a86a6a50a01",
	"twig_bridge": "5c406223b07ddab3681c5d81217c4e8171e6bf523bdd5f825c624a87e1f568f1",
	"two_species": "55da6f2129c046af00d413638853d60c7d2842b124c3f579856757792309b1b6",
}

## A "digger" colony with a small underground: shaft at (200, 200), plus
## `under` merged over the defaults (e.g. a "plan").
func _sim(under: Dictionary = {}) -> Simulation:
	var u := {"size": [400, 400], "shaft": [200, 200], "shaft_radius": 10}
	u.merge(under, true)
	var sim := Simulation.new(_config, _registry, 1)
	sim.add_colony("digger", Vector2(540, 1200), {"underground": u})
	return sim

func _run_seconds(sim: Simulation, seconds: float) -> void:
	for t in roundi(seconds * _config.tick_rate):
		sim.step()

func test_single_layer_scenarios_keep_their_hashes() -> void:
	for scenario: String in SINGLE_LAYER_HASHES:
		var sim := ScenarioLoader.load_simulation(scenario, _registry, _config)
		for t in 300:
			sim.step()
		check_eq(sim.layers.size(), 1, "%s has one layer" % scenario)
		check_eq(sim.state_hash(), SINGLE_LAYER_HASHES[scenario], "%s state hash" % scenario)

func test_underground_layer_and_portal() -> void:
	var sim := _sim()
	var nest := sim.colonies[0].nest
	check_eq(sim.layers.size(), 2, "surface + underground")
	check_eq(nest.underground_layer, 1, "the nest's layer")
	var under := sim.layers[1]
	check_eq(under.world.size, Vector2i(400, 400), "own size")
	check(under.world.is_blocked(Vector2(50, 50)), "undug soil blocks")
	check(not under.world.is_blocked(Vector2(200, 200)), "shaft bottom dug out")
	check_eq(under.pheromones.channel_count(), sim.pheromones.channel_count(), "same channels on every layer")
	check(nest.portal != null and nest.portal.open, "open entrance")
	check(nest.has_entrance(), "has_entrance")

## Pheromones and obstacles stay on their own layer.
func test_layers_are_isolated() -> void:
	var sim := _sim()
	var under := sim.layers[1]
	var home := sim.colonies[0].channels[&"home"]
	var p := Vector2(200, 200)
	var ant := sim.spawn_ant(sim.colonies[0], 0, p, 0.0, 1)
	sim.lay(ant, home)
	check(under.pheromones.sample(home, p) > 0.0, "laid underground")
	check_eq(sim.pheromones.sample(home, p), 0.0, "nothing on the surface there")
	sim.world.fill_circle(Vector2(100, 100), 20, World.Cell.WALL)
	under.world.carve_segment(Vector2(100, 100), Vector2(100, 100), 20)
	check(sim.world.is_blocked(Vector2(100, 100)), "surface wall")
	check(not under.world.is_blocked(Vector2(100, 100)), "not underground")
	# An underground ant steers by its own layer's cells.
	var digger := sim.spawn_ant(sim.colonies[0], 0, Vector2(100, 100), 0.0, 1)
	for t in 60:
		Steering.move_to(sim, digger, Vector2(140, 100), 30.0, sim.dt)
	check(not under.world.is_blocked(sim.pos[digger]), "never inside underground soil")
	# Diffusing for a while doesn't leak between layers either.
	_run_seconds(sim, 2.0)
	check(sim.pheromones.total(home) < 1e-6, "surface channel still empty")

func test_portal_round_trip() -> void:
	var sim := _sim()
	var nest := sim.colonies[0].nest
	var ant := sim.spawn_ant(sim.colonies[0], 0, nest.entrance_position(), 0.0)
	sim.change_state(ant, "carry_spoil")  # a state that never moves on its own without an item
	check(sim.enter_portal(ant, nest.portal), "entered")
	check(sim.in_transit(ant), "in transit")
	var fade_start := sim.portal_fade(ant)
	var ticks := 0
	while sim.in_transit(ant) and ticks < 100:
		sim.step()
		ticks += 1
	check_eq(sim.layer[ant], 1, "came out underground")
	check(sim.pos[ant].distance_to(nest.portal.pos_b) < 3.0, "at the shaft bottom")
	check(ticks <= roundi(nest.portal.transit_time * _config.tick_rate) + 1, "took the transit time (%d ticks)" % ticks)
	check(fade_start > 0.9 and sim.portal_fade(ant) < 0.2, "fades out, then in")
	check(sim.enter_portal(ant, nest.portal), "and back up")
	while sim.in_transit(ant):
		sim.step()
	check_eq(sim.layer[ant], 0, "on the surface again")
	check(sim.pos[ant].distance_to(nest.entrance_position()) < 3.0, "at the entrance")

func test_closed_portal_blocks_both_ways() -> void:
	var sim := _sim({"open": false, "carve": [{"center": [200, 200], "radius": 14}]})
	var nest := sim.colonies[0].nest
	check(not nest.has_entrance(), "sealed nest has no entrance")
	var up := sim.spawn_ant(sim.colonies[0], 0, Vector2(200, 200), 0.0, 1)
	check(not sim.enter_portal(up, nest.portal), "can't go up")
	var down := sim.spawn_ant(sim.colonies[0], 0, nest.entrance_position(), 0.0)
	check(not sim.enter_portal(down, nest.portal), "can't go down")

func test_dig_frees_cells_and_bumps_version() -> void:
	var sim := _sim()
	var w := sim.layers[1].world
	var cell := w.cell_at(Vector2(100, 100))
	check(w.is_soil(cell), "soil")
	var version := w.version
	var edits := w.edit_version
	var freed := false
	var bites := 0
	while not freed and bites < 10:
		freed = w.dig(cell, 0.5)
		bites += 1
	check(freed, "freed after %d bites" % bites)
	check(bites >= 2, "hardness takes more than one bite")
	check(not w.is_blocked(Vector2(100, 100)), "walkable")
	check(w.version > version, "version bumped")
	check_eq(w.edit_version, edits, "digging is not an edit (caches update incrementally)")
	check(w.dug_rect.has_point(Vector2(100, 100)), "dug area includes it")
	check(not w.dig(cell, 1.0), "digging a free cell does nothing")

func test_nav_field_reaches_newly_dug_cells() -> void:
	var sim := _sim()
	var under := sim.layers[1]
	var nav := under.nav()
	var field := nav.field_id(&"portal:0")
	check(field >= 0, "portal field")
	check_eq(nav.distance(field, Vector2(260, 200)), INF, "soil is unreachable")
	# Dig a tunnel out from the shaft, cell by cell.
	for x in range(208, 264, 4):
		for y: int in [196, 200, 204]:
			while not under.world.dig(under.world.cell_at(Vector2(x, y)), 1.0) and under.world.is_soil(under.world.cell_at(Vector2(x, y))):
				pass
	nav.update()
	var d := nav.distance(field, Vector2(260, 200))
	check(d > 40.0 and d < 70.0, "tunnel end reachable, about 55 units away (%.1f)" % d)
	# Following the field leads back to the shaft.
	var ant := sim.spawn_ant(sim.colonies[0], 0, Vector2(260, 200), PI, 1)
	for t in 90:
		Steering.move_to(sim, ant, nav.downhill(field, sim.pos[ant]), 30.0, sim.dt)
	check(sim.pos[ant].distance_to(Vector2(200, 200)) < 10.0, "walked to the shaft (%s)" % sim.pos[ant])
	# A wall edit recomputes everything.
	under.world.fill_circle(Vector2(236, 200), 8, World.Cell.WALL)
	nav.update()
	check_eq(nav.distance(field, Vector2(260, 200)), INF, "cut off by a wall")

## Diggers take the planned tunnel, bite it out and carry the spoil up to
## the heap on the surface.
func test_diggers_dig_and_spoil_reaches_the_surface() -> void:
	var sim := _sim({"plan": [{"name": "tunnel", "from": [200, 200], "to": [300, 200], "radius": 6, "diggers": 6}]})
	var nest := sim.colonies[0].nest
	var plan := nest.excavation_plan()
	var cells := plan.remaining()
	check(cells > 50, "a tunnel of soil planned (%d cells)" % cells)
	var ants: PackedInt32Array = []
	for n in 6:
		var ant := sim.spawn_ant(sim.colonies[0], 0, nest.entrance_position(), 0.0)
		sim.change_state(ant, "dig")
		ants.append(ant)
	var surface_carriers := 0
	var worst_blocked := 0
	for t in 120 * _config.tick_rate:
		sim.step()
		if t % 15 == 0:
			for ant in ants:
				if sim.state_id(ant) == "carry_spoil" and sim.layer[ant] == 0:
					surface_carriers += 1
				if not sim.in_transit(ant) and sim.world_of(ant).is_blocked(sim.pos[ant]):
					worst_blocked += 1
	check(plan.remaining() < cells, "soil dug (%d of %d left)" % [plan.remaining(), cells])
	check(nest.spoil_items > 0, "spoil dropped on the heap (%d)" % nest.spoil_items)
	check(surface_carriers > 0, "carriers seen on the surface")
	check_eq(worst_blocked, 0, "no ant ever inside soil or walls")
	check(sim.layers[1].world.dug_rect.end.x > 215.0, "the tunnel advanced (%s)" % sim.layers[1].world.dug_rect)
	# Determinism with layers.
	var again := _sim({"plan": [{"name": "tunnel", "from": [200, 200], "to": [300, 200], "radius": 6, "diggers": 6}]})
	for n in 6:
		again.change_state(again.spawn_ant(again.colonies[0], 0, again.colonies[0].nest.entrance_position(), 0.0), "dig")
	for t in 120 * _config.tick_rate:
		again.step()
	check_eq(again.state_hash(), sim.state_hash(), "same run, same hash")

## Finishing the "entrance" job opens a sealed nest.
func test_entrance_job_opens_the_portal() -> void:
	var sim := _sim({"open": false, "carve": [{"center": [200, 240], "radius": 14}],
			"plan": [{"name": "entrance", "origin": [200, 240], "from": [200, 226], "to": [200, 200], "radius": 7}]})
	var nest := sim.colonies[0].nest
	check(not nest.has_entrance(), "sealed")
	for n in 4:
		sim.change_state(sim.spawn_ant(sim.colonies[0], 0, Vector2(200, 240), 0.0, 1), "dig")
	var opened_at := -1.0
	for t in 240 * _config.tick_rate:
		sim.step()
		if nest.has_entrance():
			opened_at = sim.time()
			break
	check(opened_at > 0.0, "dug open (at %.0f s)" % opened_at)
	check(nest.packed_spoil > 0.0, "soil pressed into the walls while sealed")

# --- Layout and camera -----------------------------------------------------------------

## A layered nest plays in the split layout with its own layer view and
## camera, and L cycles surface / split / nest.
func test_nest_layout_modes() -> void:
	var player := ScenarioPlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.setup("res://tests/fixtures/scenarios/dig_demo.json")
	check_eq(player.mode(), "split", "starts split")
	var layout := player.layout
	check(layout != null and layout.nest_viewport != null, "a nest viewport for the underground")
	check(player.nest_view != null and player.nest_view.layer == 1, "a view of layer 1")
	check(player.nest_view.get_parent() == layout.nest_viewport, "in the nest viewport")
	check_eq(player.nest_camera.layer, 1, "its own camera on layer 1")
	player.toggle_layout()
	check_eq(player.mode(), "nest", "L: nest full screen")
	check_eq(layout.nest_viewport.size, Vector2i(1080, 1920), "full frame")
	check(not player.shows_world_at(Vector2(540, 300)), "the surface isn't shown")
	player.toggle_layout()
	check_eq(player.mode(), "surface", "L: surface")
	check(player.view.get_parent() == player, "world drawn full screen")
	player.toggle_layout()
	check_eq(player.mode(), "split", "L: split again")
	check_eq(layout.nest_viewport.size, Vector2i(layout.underground_rect.size), "nest part resized back")
	player.queue_free()

## Only a nest with an underground layer gets a split layout.
func test_split_layout_needs_an_underground() -> void:
	var sim := _sim()
	sim.add_colony("digger", Vector2(200, 1200))
	var layout := SplitLayout.create(sim, {"colony": 0, "ratio": 0.5})
	check(layout != null, "underground nest: split layout")
	if layout != null:
		check_eq(layout.surface_viewport.size, Vector2i(1080, 960), "surface half")
		check_eq(layout.underground_rect, Rect2(0, 960, 1080, 960), "underground half below it")
		check_eq(layout.nest_viewport.size, Vector2i(1080, 960), "nest viewport fills it")
		layout.free()
	check(SplitLayout.create(sim, {"colony": 1}) == null, "no underground: no layout")
	check(SplitLayout.create(sim, {"colony": 5}) == null, "no such colony: no layout")

## In the split layout the mouse maps to the world on the surface part only.
func test_split_layout_screen_to_world() -> void:
	var player := ScenarioPlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.setup("res://tests/fixtures/scenarios/dig_demo.json")
	check(player.is_split(), "split")
	check(player.view.get_parent() == player.layout.surface_viewport, "world drawn in the surface viewport")
	check(player.camera.get_parent() == player.layout.surface_viewport, "camera there too")
	player.advance(1.0 / 60.0)
	player.camera.force_update_scroll()
	var entrance := player.sim.colonies[0].nest.entrance_position()
	var at := player.layout.surface_viewport.canvas_transform * entrance + player.layout.surface_rect.position
	check(player.shows_world_at(at), "entrance point shows the world (%s)" % at)
	check(not player.shows_world_at(player.layout.underground_rect.get_center()), "underground part does not")
	check(player.screen_to_world(at).distance_to(entrance) < 0.5, "screen_to_world")
	player.queue_free()

## A nest without an underground plays full screen even if the scenario asks
## for the split layout.
func test_split_layout_falls_back_without_an_underground() -> void:
	var player := ScenarioPlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.setup("res://tests/fixtures/scenarios/split_no_underground.json")
	check(not player.is_split(), "full screen")
	check(player.view.get_parent() == player, "world in the main view")
	player.queue_free()

## A "fit": "excavation" keyframe frames the dug area.
func test_camera_fits_the_excavation() -> void:
	var sim := _sim({"size": [1200, 1200], "shaft": [600, 600]})
	sim.layers[1].world.carve_segment(Vector2(500, 600), Vector2(760, 600), 12)
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1000)
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	var cam := CameraDirector.new()
	vp.add_child(cam)
	cam.setup(sim, [{"t": 0, "fit": "excavation", "margin": 40, "max_zoom": 8}], 1)
	cam.update_camera(0.0, 1.0 / 60.0)
	var dug := sim.layers[1].world.dug_rect
	check(cam.position.distance_to(dug.get_center()) < 1.0, "centred on the dug area (%s vs %s)" % [cam.position, dug.get_center()])
	var want := 1080.0 / (dug.size.x + 80.0)
	check(absf(cam.zoom.x - want) < 0.01, "zoomed to fit its width plus margin (%.3f vs %.3f)" % [cam.zoom.x, want])
	# The nest grows: the framing eases out to include it.
	sim.layers[1].world.carve_segment(Vector2(600, 600), Vector2(600, 1000), 12)
	var z0 := cam.zoom.x
	for n in 90:
		cam.update_camera(0.1 + n / 60.0, 1.0 / 60.0)
	check(cam.zoom.x < z0 - 0.1 and cam.zoom.x > 2.1, "eases toward the new framing (%.3f)" % cam.zoom.x)
	for n in 300:
		cam.update_camera(2.0 + n / 60.0, 1.0 / 60.0)
	var grown := sim.layers[1].world.dug_rect
	check(absf(cam.zoom.x - 1000.0 / (grown.size.y + 80.0)) < 0.03, "then fits its height (%.3f)" % cam.zoom.x)
	vp.queue_free()
