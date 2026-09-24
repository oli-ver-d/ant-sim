class_name NestType
extends RefCounted
## Base interface for a colony's home. One instance per colony, created from
## the Registry by the species' nest_type id. Rendering is hooked up by
## registering a renderer under "nest:<type_id>".
##
## Nests without a fixed entrance (e.g. a moving bivouac) return
## has_entrance() == false and can move `position` in update(); nests that are
## built at runtime can start without an entrance and gain one later.

var type_id: String = ""
## Owning colony, as an index into sim.colonies (not a reference, to avoid a
## Colony <-> NestType reference cycle that would leak).
var colony_id: int = -1
var position: Vector2 = Vector2.ZERO
## Distance from the entrance at which an ant counts as "at the nest".
var radius: float = 12.0
## Distance from which returning ants see the entrance and head straight for it.
var sense_radius: float = 60.0

func setup(sim: Simulation, owner_colony: Colony, params: Dictionary) -> void:
	colony_id = owner_colony.id
	position = owner_colony.nest_position
	radius = params.get("radius", radius)
	sense_radius = params.get("sense_radius", sense_radius)
	if params.has("underground"):
		setup_underground(sim, params["underground"])

## A nest with an underground has an entrance once its portal is open.
func has_entrance() -> bool:
	return portal == null or portal.open

func entrance_position() -> Vector2:
	return position

func is_at_nest(pos: Vector2) -> bool:
	return has_entrance() and pos.distance_squared_to(entrance_position()) <= radius * radius

## Takes ownership of a delivered item. The Simulation destroys the item afterwards.
func receive_item(_sim: Simulation, _item: Item) -> void:
	pass

## Growth and internal processes; called once per tick.
func update(_sim: Simulation, _dt: float) -> void:
	pass

## Adds any nest state that affects the simulation to a state_hash() fingerprint.
func hash_state(_ctx: HashingContext) -> void:
	pass

# --- Gradual release ---------------------------------------------------------------
# Ants can start "inside" the nest and emerge over time instead of all at once
# (scenario colony option "release_per_second"). The Simulation calls
# release_waiting() every tick, before update(), for every nest type.

## Caste indices of ants still inside, in emergence order.
var waiting: PackedInt32Array = []
## Ants released per second.
var release_rate: float = 0.0
var _release_budget: float = 0.0

## Queues ants to emerge at `per_second`.
func queue_release(castes: PackedInt32Array, per_second: float) -> void:
	waiting.append_array(castes)
	release_rate = per_second

func release_waiting(sim: Simulation, dt: float) -> void:
	if waiting.is_empty() or not has_entrance():
		return
	_release_budget += release_rate * dt
	var colony := sim.colonies[colony_id]
	while _release_budget >= 1.0 and not waiting.is_empty():
		_release_budget -= 1.0
		sim.spawn_ant(colony, waiting[0], entrance_position(), sim.rng.randf_range(-PI, PI))
		waiting.remove_at(0)

## Spawns `count` ants at the entrance, choosing castes by spawn_ratio.
func spawn_ants(sim: Simulation, count: int) -> void:
	for n in count:
		var caste := pick_caste(sim)
		var heading := sim.rng.randf_range(-PI, PI)
		sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position(), heading)

## Weighted random caste index by CasteDef.spawn_ratio. Pass the species
## during setup(), before the colony is in sim.colonies.
func pick_caste(sim: Simulation, species: SpeciesDef = null) -> int:
	var castes := (species if species != null else sim.colonies[colony_id].species).castes
	var total := 0.0
	for c in castes:
		total += c.spawn_ratio
	var r := sim.rng.randf() * total
	for i in castes.size():
		r -= castes[i].spawn_ratio
		if r <= 0.0 and castes[i].spawn_ratio > 0.0:
			return i
	# Rounding left some over: the last caste that is ever spawned.
	for i in range(castes.size() - 1, -1, -1):
		if castes[i].spawn_ratio > 0.0:
			return i
	return 0

# --- Waste ---------------------------------------------------------------------------
# Nests may produce refuse that workers carry out to a dump (a midden) on the
# surface; see the core carry_waste behaviour. The base nest makes none.

## Mass of waste carried out and dumped so far.
var dumped_mass: float = 0.0
## Number of waste loads dumped so far.
var dumped_items: int = 0

## True if there is waste ready to be carried out.
func has_waste() -> bool:
	return false

## Hands out one load of waste as a new Item (the caller picks it up), or
## null if there is none.
func take_waste(_sim: Simulation) -> Item:
	return null

## Where waste is dumped.
func dump_position() -> Vector2:
	return position

## Called when a load of waste is dropped at the dump. The Simulation destroys
## the item afterwards; the dump keeps only the totals.
func receive_waste(_sim: Simulation, item: Item) -> void:
	dumped_mass += item.mass
	dumped_items += 1

# --- Underground ---------------------------------------------------------------------
# A nest may dig its own underground (nest_params "underground"): a layer of
# soil below the surface, linked to the entrance by a portal (the shaft).
# Its excavation plan says what to dig; diggers ("dig") bite soil at the
# digging face and carry the spoil up ("carry_spoil") to spoil_position() on
# the surface. Nest types extend the plan (e.g. new chambers as they grow)
# through excavation_plan().
#
#   "underground": {"size": [1280, 1280], "cell_size": 4, "hardness": 1.0,
#       "shaft": [640, 640], "shaft_radius": 10, "open": true, "bite": 0.5,
#       "spoil": [-70, 40],
#       "carve": [{"from": [x, y], "to": [x, y], "radius": r}, ...],
#       "plan": [{"name": "tunnel", "origin": [x, y], "from": [x, y], "to": [x, y],
#                 "radius": 7, "priority": 0, "diggers": 4},
#                {"name": "gallery", "path": [[x, y], ...], "radii": [9, 7, ...]},
#                {"name": "cave", "origin": [x, y], "lobes": [cx, cy, rx, ry, angle, ...],
#                 "face": [x, y]}, ...],
#       "texture": {"clay": 0.16, "roots": 0.05, "stones": 5, ...}, "overdig": 4.5,
#       "ragged": 6}
#
# "shaft" is where the entrance comes down (default: the layer's centre);
# "carve" shapes are dug out from the start (default: the shaft bottom, if
# open), "plan" jobs are dug by the colony: capsules (from/to/radius), paths
# (points with a radius each) or blobs of ellipses (see ExcavationPlan and
# DigShape). "texture" gives the soil clay, roots and stones (World.
# add_soil_texture, kept clear of the shaft and the carved shapes);
# "overdig" makes dug outlines rough and "ragged" the digging face uneven.
# A sealed nest ("open": false) has no entrance until the job named
# "entrance" (if any) is finished.

## Layer index of the nest's underground, or -1 if it has none.
var underground_layer: int = -1
## The entrance shaft (surface <-> underground), or null.
var portal: Portal
var plan: ExcavationPlan
## Where spoil is dropped on the surface, relative to the entrance.
var spoil_offset: Vector2 = Vector2(-70, 40)
## Soil carried out and dropped on the spoil heap so far.
var spoil_mass: float = 0.0
var spoil_items: int = 0
## Soil bitten out while the entrance was closed (pressed into the walls).
var packed_spoil: float = 0.0
## Weight of spoil per unit of digging work (see make_spoil()).
const SPOIL_WEIGHT := 0.3
## An ant a view should point out, e.g. a worker that has just come out of
## the nest onto the surface (-1 = none); see SplitLayout.
var highlight_ant: int = -1

func setup_underground(sim: Simulation, params: Dictionary) -> void:
	var size := Vector2i(ScenarioEvents.vec2(params.get("size", [1280, 1280])))
	var l := sim.add_layer(StringName("nest%d" % colony_id), size, int(params.get("cell_size", 4)))
	l.world.fill_soil(float(params.get("hardness", 1.0)))
	underground_layer = l.index
	var shaft := ScenarioEvents.vec2(params["shaft"]) if params.has("shaft") else Vector2(size) * 0.5
	var shaft_r := float(params.get("shaft_radius", 10.0))
	var open := bool(params.get("open", true))
	if params.has("spoil"):
		spoil_offset = ScenarioEvents.vec2(params["spoil"])
	if params.has("texture"):
		# Clay, roots and stones, kept clear of the shaft and anything carved.
		var clear := PackedVector3Array([Vector3(shaft.x, shaft.y, shaft_r + 12.0)])
		for c: Dictionary in params.get("carve", []):
			if c.has("lobes"):
				var lobes: Array = c["lobes"]
				for k in range(0, lobes.size() - 4, 5):
					clear.append(Vector3(lobes[k], lobes[k + 1], maxf(lobes[k + 2], lobes[k + 3]) + 8.0))
				continue
			var a := ScenarioEvents.vec2(c.get("from", c.get("center", [0, 0])))
			var b := ScenarioEvents.vec2(c.get("to", [a.x, a.y]))
			var r := float(c.get("radius", 10.0)) + 8.0
			for k in 5:
				var p := a.lerp(b, k / 4.0)
				clear.append(Vector3(p.x, p.y, r))
		for p: Variant in params.get("keep_clear", []):
			clear.append(Vector3(p[0], p[1], p[2]))
		l.world.add_soil_texture(sim.rng.seed * 31 + colony_id, params["texture"], clear)
	if params.has("carve"):
		for c: Dictionary in params["carve"]:
			if c.has("lobes"):
				l.world.carve_ellipses(PackedFloat32Array(c["lobes"]), float(c.get("rough", 0.0)), int(c.get("seed", 0)))
				continue
			var a := ScenarioEvents.vec2(c.get("from", c.get("center", [0, 0])))
			l.world.carve_segment(a, ScenarioEvents.vec2(c.get("to", [a.x, a.y])), float(c.get("radius", 10.0)))
	elif open:
		l.world.carve_segment(shaft, shaft, shaft_r)
	portal = sim.add_portal(0, entrance_position(), l.index, shaft, maxf(radius, shaft_r))
	portal.open = open
	plan = ExcavationPlan.new(l)
	plan.bite = float(params.get("bite", plan.bite))
	plan.overdig = float(params.get("overdig", plan.overdig))
	plan.ragged = float(params.get("ragged", plan.ragged))
	plan.rough_seed = sim.rng.seed * 13 + colony_id
	for j: Dictionary in params.get("plan", []):
		var job: ExcavationPlan.Job
		var name := str(j.get("name", ""))
		var prio := float(j.get("priority", 0.0))
		var diggers := int(j.get("diggers", 4))
		if j.has("path"):
			var pts := PackedVector2Array()
			for p: Array in j["path"]:
				pts.append(Vector2(p[0], p[1]))
			var radii := PackedFloat32Array(j.get("radii", []))
			while radii.size() < pts.size():
				radii.append(float(j.get("radius", 7.0)))
			job = plan.add_path_job(name, ScenarioEvents.vec2(j.get("origin", j["path"][0])), pts, radii, prio, diggers)
		elif j.has("lobes"):
			var lobes := PackedFloat32Array(j["lobes"])
			var into := ScenarioEvents.vec2(j.get("origin", [lobes[0], lobes[1]]))
			job = plan.add_blob_job(name, into, lobes, ScenarioEvents.vec2(j.get("face", [into.x, into.y])), prio, diggers)
		else:
			var a := ScenarioEvents.vec2(j["from"])
			job = plan.add_job(name, ScenarioEvents.vec2(j.get("origin", j["from"])), a,
					ScenarioEvents.vec2(j.get("to", j["from"])), float(j.get("radius", 7.0)), prio, diggers)
		if job.name == "entrance":
			plan.open_portal_when_done(job, portal)

## What the nest wants dug (null without an underground).
func excavation_plan() -> ExcavationPlan:
	return plan

## Where diggers drop spoil on the surface.
func spoil_position() -> Vector2:
	return entrance_position() + spoil_offset

## A load of spoil dropped on the heap. The Simulation destroys the item.
func receive_spoil(_sim: Simulation, item: Item) -> void:
	spoil_mass += item.mass
	spoil_items += 1

## A new spoil pellet for `dug` work of soil (the digger picks it up). A
## pellet weighs SPOIL_WEIGHT per unit of work, so carrying it slows a
## digger down about like any other load.
func make_spoil(sim: Simulation, dug: float) -> Item:
	var item := sim.create_item("spoil", dug * SPOIL_WEIGHT)
	item.radius = 1.7
	item.color = Color(0.42, 0.3, 0.2)
	return item

## Underground state for Simulation.state_hash() (nest types that override
## hash_state() call this).
func hash_underground(ctx: HashingContext) -> void:
	if plan != null:
		plan.hash_into(ctx)
		ctx.update(PackedFloat64Array([spoil_mass, spoil_items, packed_spoil]).to_byte_array())

## Places one of the colony's starting ants (scenario population) and
## returns its index: at the entrance by default; nests with an underground
## may put them inside instead.
func spawn_initial(sim: Simulation, caste: int) -> int:
	return sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position(), sim.rng.randf_range(-PI, PI))

## Called when ant i comes up onto the surface from the underground (the
## core "go_up" behaviour), e.g. to point out a new worker.
func ant_surfaced(_sim: Simulation, _i: int) -> void:
	pass

## The caste of abstract ant to bring back as an agent onto layer l: the
## one whose agents are furthest below its share of the whole colony (-1 if
## the colony has none abstract).
func pool_caste(sim: Simulation, _l: int) -> int:
	var colony := sim.colonies[colony_id]
	var best := -1
	var best_gap := -INF
	var total := maxf(1.0, colony.total_population())
	var agents := maxf(1.0, colony.population)
	for c in colony.abstract_by_caste.size():
		if colony.abstract_by_caste[c] <= 0:
			continue
		var gap := colony.total_of_caste(c) / total - colony.population_by_caste[c] / agents
		if gap > best_gap:
			best_gap = gap
			best = c
	return best

## Places an ant of caste c coming back from the abstract population onto
## layer l and returns it (-1 if it couldn't be placed): at the entrance by
## default.
func spawn_from_pool(sim: Simulation, caste: int, l: int) -> int:
	if l != 0:
		return -1
	return sim.spawn_ant(sim.colonies[colony_id], caste, entrance_position() + Vector2.from_angle(sim.rng.randf() * TAU) * 4.0,
			sim.rng.randf_range(-PI, PI))

## Lines of text about the colony a nest view may show (e.g. its size),
## the first one larger. None by default.
func stats_lines(_sim: Simulation) -> PackedStringArray:
	return PackedStringArray()
