extends TestCase
## M15d: plants and grass (PlantProp): blade geometry per kind, built from the
## prop's own seed; only the stem blocks; the canopy mesh (CanopyRenderer) and
## its shadow; the canopy's clear spots round nests, food and the followed ant.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

const KINDS := ["rosette", "clover", "fern", "seedling"]

func _plant(sim: Simulation, kind: String, extra: Dictionary = {}) -> Prop:
	var data := {"type": "grass" if kind == "grass" else "plant", "kind": kind, "center": [400, 600]}
	data.merge(extra, true)
	return sim.scenery.add(data)

func _blades_of_style(prop: Prop, style: int) -> int:
	var n := 0
	for b: Dictionary in prop.detail["blades"]:
		if int(b["style"]) == style:
			n += 1
	return n

func test_every_kind_builds_blades() -> void:
	var sim := Simulation.new(_config, _registry, 7)
	for kind: String in KINDS + ["grass"]:
		var p := _plant(sim, kind)
		var blades: Array = p.detail["blades"]
		check(blades.size() >= 2, "%s has blades (%d)" % [kind, blades.size()])
		check_eq(str(p.detail["kind"]), kind, "%s kind recorded" % kind)
		for b: Dictionary in blades:
			var pts: PackedVector2Array = b["points"]
			check_eq(pts.size(), PlantProp.SEGMENTS + 1, "%s spine points" % kind)
			check_eq((b["widths"] as PackedFloat32Array).size(), pts.size(), "%s widths" % kind)
			check_eq((b["heights"] as PackedFloat32Array).size(), pts.size(), "%s heights" % kind)
			# Blades stay within reach of the plant (fern pinnae hang a little beyond).
			for q in pts:
				check(q.distance_to(p.position) <= float(p.detail["reach"]) * 1.35, "%s blade within reach" % kind)
		# The canopy outline covers every blade's spine.
		for b: Dictionary in blades:
			for q: Vector2 in b["points"]:
				check(Geometry2D.is_point_in_polygon(q, p.canopy) or _near_outline(q, p.canopy), "%s canopy covers %s" % [kind, q])

func _near_outline(q: Vector2, outline: PackedVector2Array) -> bool:
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < 0.01:
			return true
	return false

func test_blade_counts_follow_params() -> void:
	var sim := Simulation.new(_config, _registry, 7)
	check_eq(_plant(sim, "rosette", {"blades": 7}).detail["blades"].size(), 7, "rosette blades")
	var clover := _plant(sim, "clover", {"blades": 4})
	check_eq(_blades_of_style(clover, PlantProp.Style.STALK), 4, "clover stalks")
	check_eq(_blades_of_style(clover, PlantProp.Style.LOBE), 12, "three lobes per stalk")
	var fern := _plant(sim, "fern", {"blades": 3})
	check_eq(_blades_of_style(fern, PlantProp.Style.STALK), 3, "fern fronds")
	check(_blades_of_style(fern, PlantProp.Style.PINNA) >= 30, "pinnae in pairs along each frond")
	check_eq(_plant(sim, "grass", {"blades": 21}).detail["blades"].size(), 21, "grass blades")

func test_same_seed_same_blades() -> void:
	for kind: String in KINDS + ["grass"]:
		var a := _plant(Simulation.new(_config, _registry, 11), kind)
		var b := _plant(Simulation.new(_config, _registry, 11), kind)
		var c := _plant(Simulation.new(_config, _registry, 12), kind)
		check_eq(a.detail["blades"], b.detail["blades"], "%s: same seed, same blades" % kind)
		check(a.detail["blades"] != c.detail["blades"], "%s: another seed, other blades" % kind)

## Only the stem blocks: the ground under the blades stays free.
func test_only_the_stem_blocks() -> void:
	var sim := Simulation.new(_config, _registry, 7)
	var fern := _plant(sim, "fern", {"radius": 90, "stem": 6})
	check(fern.blocks and not fern.cells.is_empty(), "stem blocks")
	for c in fern.cells:
		var at := Vector2((c % sim.world.width) + 0.5, (c / sim.world.width) + 0.5) * sim.world.cell_size
		check(at.distance_to(fern.position) <= 6.0 + sim.world.cell_size, "blocked cell %d within the stem" % c)
	for b: Dictionary in fern.detail["blades"]:
		var tip: Vector2 = (b["points"] as PackedVector2Array)[PlantProp.SEGMENTS]
		if tip.distance_to(fern.position) > 12.0:
			check(not sim.world.is_blocked(tip), "blade tip %s is free" % tip)
	var grass := _plant(sim, "grass", {"center": [700, 600]})
	check(not grass.blocks and grass.cells.is_empty(), "grass is canopy only")

## The canopy mesh has a pair of vertices per spine point; the shadow mesh is
## the same blades shifted away from the light by their height.
func test_canopy_mesh_and_shadow() -> void:
	var sim := Simulation.new(_config, _registry, 7)
	for kind: String in KINDS + ["grass"]:
		_plant(sim, kind, {"center": [200 + 150 * KINDS.find(kind), 600]})
	sim.scenery.add({"type": "rock", "center": [900, 900], "radius": 30})
	var points := 0
	for p in sim.scenery.props:
		for b: Dictionary in p.detail.get("blades", []):
			points += (b["points"] as PackedVector2Array).size()
	var body := CanopyRenderer.build_mesh(sim.scenery.props, false)
	var shadow := CanopyRenderer.build_mesh(sim.scenery.props, true)
	var bv: PackedVector2Array = body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sv: PackedVector2Array = shadow.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(bv.size(), points * 2, "two vertices per spine point")
	check_eq(sv.size(), bv.size(), "shadow has the same vertices")
	# Midpoints of each vertex pair: the spine, and the spine cast by its height.
	var b0: Dictionary = sim.scenery.props[0].detail["blades"][0]
	var cast := -PropBaker.LIGHT_DIR.normalized() * CanopyRenderer.CAST
	for k in PlantProp.SEGMENTS + 1:
		var spine: Vector2 = (b0["points"] as PackedVector2Array)[k]
		var h: float = (b0["heights"] as PackedFloat32Array)[k]
		check((bv[k * 2] + bv[k * 2 + 1]) * 0.5 == spine or ((bv[k * 2] + bv[k * 2 + 1]) * 0.5).distance_to(spine) < 0.01, "body on the spine")
		check(((sv[k * 2] + sv[k * 2 + 1]) * 0.5).distance_to(spine + cast * h) < 0.01, "shadow cast by height")
	var again := CanopyRenderer.build_mesh(sim.scenery.props, false)
	check_eq(again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], bv, "deterministic")
	check(CanopyRenderer.build_mesh([sim.scenery.props[-1]], false) == null, "no mesh without plants")

func test_clear_spots() -> void:
	var sim := ScenarioLoader.build({"seed": 3,
		"colonies": [{"species": "leafcutter", "nest": [540, 1300], "population": {"minim": 20}}],
		"food": [{"type": "food_pile", "pos": [540, 850], "radius": 26, "amount": 400}]}, _registry, _config)
	sim.step()
	var spots := CanopyRenderer.clear_spots(sim)
	check_eq(spots.size(), 2, "nest entrance and food")
	check(Vector2(spots[0].x, spots[0].y).distance_to(Vector2(540, 1300)) < 1.0, "entrance first")
	check(spots[0].z > sim.colonies[0].nest.radius, "clears more than the nest radius")
	check_eq(Vector2(spots[1].x, spots[1].y), Vector2(540, 850), "then food")
	var ant := 0
	while sim.alive[ant] == 0:
		ant += 1
	var followed := CanopyRenderer.clear_spots(sim, ant)
	check_eq(followed.size(), 3, "plus the followed ant")
	check_eq(Vector2(followed[0].x, followed[0].y), sim.shown_pos[ant], "followed ant first")
	for i in 30:
		sim.add_food_source("food_pile", {"type": "food_pile", "pos": [100 + i * 20, 300], "radius": 10, "amount": 50})
	check_eq(CanopyRenderer.clear_spots(sim, ant).size(), CanopyRenderer.MAX_SPOTS, "capped")

## Canopy-only plants of every kind leave the run as it was.
func test_plants_without_stems_keep_the_run() -> void:
	var colony := {"species": "leafcutter", "nest": [540, 1300], "population": {"minim": 30, "media": 60}}
	var food := {"type": "food_pile", "pos": [540, 850], "radius": 26, "amount": 400}
	var scenery := []
	for i in KINDS.size():
		scenery.append({"type": "plant", "kind": KINDS[i], "center": [300 + i * 120, 1050], "stem": 0})
	scenery.append({"type": "grass", "center": [540, 1100], "radius": 60})
	var plain := ScenarioLoader.build({"seed": 4, "colonies": [colony], "food": [food]}, _registry, _config)
	var planted := ScenarioLoader.build({"seed": 4, "colonies": [colony], "food": [food], "scenery": scenery}, _registry, _config)
	check_eq(planted.scenery.props.size(), 5, "placed")
	for t in 200:
		plain.step()
		planted.step()
	check_eq(planted.state_hash(), plain.state_hash(), "same run")
