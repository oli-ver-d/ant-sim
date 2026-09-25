extends TestCase
## M15g: drawing middens: a look for every refuse kind, baked sprites that
## leave room for their shadow, the ground data (stain, mound height) the
## midden shader reads, dead workers keeping their caste on the midden, and
## the renderer's chunks following deposits as they arrive and rot away.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := _with_looks()

static func _with_looks() -> Registry:
	var registry := Registry.create_default()
	CoreRenderers.register(registry)
	return registry

func _basic(params: Dictionary = {}) -> Simulation:
	var data := {"seed": 7, "food": [], "colonies": [{"species": "leafcutter", "nest_type": "basic_nest",
			"nest": [540, 1000], "population": {"media": 10, "major": 2}, "params": params}]}
	return ScenarioLoader.build(data, _registry, _config)

func test_every_refuse_kind_has_a_look() -> void:
	for kind: String in _registry.refuse_kinds:
		var script: Script = _registry.renderers.get("refuse:" + kind)
		check(script != null, "a look for %s" % kind)
		if script != null:
			check(script.new() is RefuseLook, "%s's look is a RefuseLook" % kind)

func test_looks_bake_sprites_with_room_for_their_shadow() -> void:
	var px := RefuseLook.PX
	for kind: String in _registry.refuse_kinds:
		var look: RefuseLook = _registry.renderers["refuse:" + kind].new()
		var img := look.bake(kind)
		check_eq(img.get_size(), Vector2i(px * RefuseLook.VARIANTS, px), "%s atlas size" % kind)
		check(img.has_mipmaps(), "%s has mipmaps" % kind)
		var empty := 0
		for v in RefuseLook.VARIANTS:
			var covered := 0
			var edge := 0.0
			for y in px:
				for x in px:
					var a := img.get_pixel(v * px + x, y).a
					covered += 1 if a > 0.5 else 0
					if x == 0 or y == 0 or x == px - 1 or y == px - 1:
						edge = maxf(edge, a)
			empty += 1 if covered < 12 else 0
			check(edge < 0.05, "%s variant %d stays off the cell's edge" % [kind, v])
		check_eq(empty, 0, "%s: every variant has a body" % kind)
	# Same kind, same sprites.
	var a: Image = RefuseLooks.Husk.new().bake("husk")
	var b: Image = RefuseLooks.Husk.new().bake("husk")
	check(a.get_data() == b.get_data(), "baking is repeatable")

func test_dead_workers_keep_their_caste_on_the_midden() -> void:
	var sim := _basic({"worker_lifespan": 1000})
	var nest := sim.colonies[0].nest
	var at := nest.position + Vector2(150, 0)
	for caste in sim.colonies[0].species.castes.size():
		var item := nest.leave_corpse(sim, "corpse", 0.08, at, 0, caste)
		nest.drop_refuse(sim, item, nest.refuse_target(sim, 0.5, 0.5))
	var crumb := sim.create_item("crumb", 0.2)
	nest.drop_refuse(sim, crumb, nest.refuse_target(sim, 0.3, 0.3))
	var m := nest.middens[0]
	check_eq(m.count(), sim.colonies[0].species.castes.size() + 1, "every load is a deposit")
	for d in m.count():
		var corpse := m.kinds[m.dep_kind[d]] == "corpse"
		check_eq(m.dep_extra[d], d if corpse else -1, "deposit %d's caste" % d)

func test_extra_stays_with_its_deposit_through_merges() -> void:
	var m := Midden.new(Vector2(600, 1000), Vector2(500, 1000), "pile", 1e9)
	for k in 30:
		# Remnants rot away; soil clumps (tagged with their number) stay.
		var soil := k % 3 == 0
		m.add("soil_clump" if soil else "remnant", Vector2(600 + k, 1000), 0.2, 0.0, _registry, k if soil else -1)
	m.update(10000.0, _registry)
	check_eq(m.count(), 10, "only the soil is left")
	for d in m.count():
		check_eq(m.dep_extra[d], m.dep_id[d], "extra kept with deposit %d" % m.dep_id[d])

func test_ground_data_holds_stain_and_mound() -> void:
	var m := Midden.new(Vector2(600, 1000), Vector2(500, 1000), "pile", 1e9)
	for k in 20:
		m.add("soil_clump", Vector2(600, 1000), 0.3, 0.0, _registry)
	for k in 20:
		m.add("remnant", Vector2(640, 1000), 0.3, 0.0, _registry)
	# Remnants have 18% left at 2,200 s: merged into the stain.
	m.update(2200.0, _registry)
	var img := MiddenRenderer.ground_data(m, 2200.0, _registry)
	check_eq(img.get_size(), Vector2i(Midden.STAIN_SIZE, Midden.STAIN_SIZE), "one texel per stain cell")
	var cell := func(at: Vector2) -> Vector2i:
		return Vector2i(((at - m.stain_origin()) / Midden.STAIN_CELL).floor())
	var pile := img.get_pixelv(cell.call(Vector2(600, 1000)))
	var rotted := img.get_pixelv(cell.call(Vector2(640, 1000)))
	var bare := img.get_pixelv(cell.call(Vector2(560, 960)))
	check(pile.g > 0.9 and pile.r < 0.01, "soil still lies in a heap (h %.2f, stain %.2f)" % [pile.g, pile.r])
	check(rotted.r > 0.5 and rotted.g < 0.01, "rotted remnants stain the ground (%.2f)" % rotted.r)
	check(bare.r == 0.0 and bare.g == 0.0, "bare ground elsewhere")

func test_renderer_chunks_follow_the_deposits() -> void:
	var sim := _basic()
	var nest := sim.colonies[0].nest
	var renderer := MiddenRenderer.new()
	renderer.bind(sim, nest)
	var n := MiddenRenderer.CHUNK * 2 + 5
	for k in n:
		var item := sim.create_item("crumb" if k < MiddenRenderer.CHUNK else "spoil", 0.1)
		nest.drop_refuse(sim, item, nest.refuse_target(sim, fmod(k * 0.37, 1.0), fmod(k * 0.61, 1.0)))
	renderer._process(0.0)
	check_eq(renderer._views.size(), 1, "one view per midden")
	var view: MiddenRenderer.View = renderer._views[0]
	check_eq(view.chunks.size(), 3, "chunks by id")
	check_eq(view.chunks[2].count, 5, "the newest chunk holds the last loads")
	check(renderer.look("crumb_that_does_not_exist")[0] != null, "unknown kinds fall back to a look")
	# The crumbs (remnants) rot into the stain; their chunk goes.
	nest.middens[0].update(20000.0, sim.registry)
	renderer._process(0.0)
	check_eq(view.chunks.size(), 2, "the rotted chunk was freed")
	check(not view.chunks.has(0), "and it was the first")
	check(view.ground_texture != null, "the ground has its data")
	renderer.free()

func test_rain_wets_middens_under_it() -> void:
	var sim := _basic()
	sim.start_rain({"center": [600, 1000], "radius": 100}, 10.0)
	for t in 60:
		sim.step()
	check(RainRenderer.wetness_at(sim, Vector2(620, 1000), sim.time()) > 0.5, "wet under the shower")
	check_eq(RainRenderer.wetness_at(sim, Vector2(900, 1000), sim.time()), 0.0, "dry outside it")
