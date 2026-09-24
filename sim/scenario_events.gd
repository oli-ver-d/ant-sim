class_name ScenarioEvents
extends RefCounted
## Things a scenario can make happen, at load time or as timed events.
## Timed events are applied by the Simulation at the start of the first tick
## whose time reaches the event's "t" (simulated seconds), so they are part of
## the deterministic run and work headlessly.
##
## Event types:
##   {"t": 30, "type": "spawn_food",      "food": {"type": "...", "pos": [x, y], ...}}
##   {"t": 30, "type": "add_obstacle",    "obstacle": {shape...}}
##   {"t": 30, "type": "remove_obstacle", "obstacle": {shape...}}   (clears those cells)
##   {"t": 30, "type": "add_colony",      "colony": {colony...}}
##   {"t": 30, "type": "rain", "duration": 6, "area": {"center": [x, y], "radius": r} | {"rect": [x, y, w, h]},
##    "wash_half_life": 0.5}   (no area = whole world; half-life 0 = wiped at once)
##   {"t": 30, "type": "drop_debris", "debris": [{"type": "twig", "pos": [x, y], ...}, ...]}  (see Debris)
##   {"t": 30, "type": "drop_debris", "scatter": {"count": 6, "near": [x, y], "on_channel": "c0.food", ...}}
##
## Obstacle shapes:
##   {"shape": "polyline", "points": [[x, y], ...], "width": 16, "kind": "wall" | "water"}
##   {"shape": "polyline", "points": [...], "width": 12, "kind": "bridge"}  (a walkable
##      strip over walls or water, drawn as a twig; see World.add_bridge)
##   {"shape": "polygon", "points": [[x, y], ...]}
##   {"shape": "rect", "rect": [x, y, w, h]}
##   {"shape": "circle", "center": [x, y], "radius": r}

static func apply(sim: Simulation, event: Dictionary) -> void:
	match event.get("type", ""):
		"spawn_food":
			var food: Dictionary = event["food"]
			sim.add_food_source(food["type"], food)
		"add_obstacle":
			add_obstacle(sim.world, event["obstacle"])
		"remove_obstacle":
			add_obstacle(sim.world, event["obstacle"], World.Cell.FREE)
		"add_colony":
			add_colony(sim, event["colony"])
		"rain":
			sim.start_rain(event.get("area", {}), float(event.get("duration", 5.0)), float(event.get("wash_half_life", 0.0)))
		"drop_debris":
			for d: Dictionary in event.get("debris", []):
				Debris.create(sim, d)
			if event.has("scatter"):
				scatter_debris(sim, event["scatter"])
		var other:
			push_error("Unknown scenario event type '%s'" % other)

## Drops `count` random debris pieces near a point. With "on_channel" (a
## pheromone channel name such as "c0.food") they land on the strongest spots
## of that channel - e.g. right on an emergent trail wherever it formed.
##   {"count": 6, "near": [x, y], "radius": 150, "on_channel": "c0.food",
##    "min_spacing": 25, "types": ["twig", "pebble"]}
static func scatter_debris(sim: Simulation, s: Dictionary) -> void:
	var count := int(s.get("count", 5))
	var near := vec2(s["near"])
	var radius := float(s.get("radius", 150.0))
	var spacing := float(s.get("min_spacing", 25.0))
	var types: Array = s.get("types", ["twig", "pebble"])
	var channel := sim.pheromones.channel_index(StringName(str(s.get("on_channel", ""))))
	# Candidate points, scored by channel strength (or random order without a channel).
	var candidates: Array[Vector3] = []
	for n in 400:
		var p := near + Vector2.from_angle(sim.rng.randf() * TAU) * radius * sqrt(sim.rng.randf())
		if sim.world.is_blocked(p):
			continue
		var score := sim.pheromones.sample(channel, p) if channel >= 0 else sim.rng.randf()
		candidates.append(Vector3(p.x, p.y, score))
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	var placed: PackedVector2Array = []
	for c in candidates:
		if placed.size() >= count:
			break
		var p := Vector2(c.x, c.y)
		var ok := true
		for q in placed:
			if q.distance_to(p) < spacing:
				ok = false
				break
		if ok:
			placed.append(p)
			Debris.create(sim, {"type": types[sim.rng.randi() % types.size()], "pos": [p.x, p.y]})

## Creates a colony and its starting population. Castes are taken in
## SpeciesDef order so spawn order doesn't depend on JSON key order.
## With "release_per_second" the ants start inside the nest (in a shuffled
## order) and emerge gradually instead of all at once.
## "params", "state_params" and "channels" tweak this colony only (see
## Simulation.add_colony).
static func add_colony(sim: Simulation, col: Dictionary) -> Colony:
	var overrides := {"params": col.get("params", {}), "state_params": col.get("state_params", {}),
			"channels": col.get("channels", {})}
	var colony := sim.add_colony(col["species"], vec2(col["nest"]), col.get("nest_params", {}), overrides)
	var population: Dictionary = col.get("population", {})
	var castes: PackedInt32Array = []
	for c in colony.species.castes.size():
		for n in int(population.get(str(colony.species.castes[c].id), 0)):
			castes.append(c)
	var rate := float(col.get("release_per_second", 0.0))
	# Nests with an underground place their ants inside (spawn_initial).
	if rate > 0.0 and colony.nest.underground_layer < 0:
		# Fisher-Yates shuffle with the sim's RNG so castes emerge mixed.
		for k in range(castes.size() - 1, 0, -1):
			var j := sim.rng.randi_range(0, k)
			var tmp := castes[k]
			castes[k] = castes[j]
			castes[j] = tmp
		colony.nest.queue_release(castes, rate)
	else:
		for c in castes:
			colony.nest.spawn_initial(sim, c)
	return colony

## Stamps an obstacle shape into the world. kind_override (a World.Cell value)
## replaces the shape's own "kind", e.g. FREE to remove an obstacle.
static func add_obstacle(world: World, ob: Dictionary, kind_override: int = -1) -> void:
	if ob.get("kind", "wall") == "bridge" and kind_override < 0:
		world.add_bridge(points(ob["points"]), float(ob.get("width", 12.0)))
		return
	var kind: int = World.Cell.WATER if ob.get("kind", "wall") == "water" else World.Cell.WALL
	if kind_override >= 0:
		kind = kind_override
	match ob.get("shape", "polyline"):
		"polyline":
			world.draw_polyline(points(ob["points"]), float(ob.get("width", 16.0)), kind)
		"polygon":
			world.fill_polygon(points(ob["points"]), kind)
		"rect":
			world.fill_rect(rect2(ob["rect"]), kind)
		"circle":
			world.fill_circle(vec2(ob["center"]), float(ob["radius"]), kind)
		var other:
			push_error("Unknown obstacle shape %s" % other)

static func points(arr: Array) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p: Variant in arr:
		out.append(vec2(p))
	return out

static func vec2(v: Variant) -> Vector2:
	var a: Array = v
	return Vector2(a[0], a[1])

static func rect2(v: Variant) -> Rect2:
	var a: Array = v
	return Rect2(a[0], a[1], a[2], a[3])
