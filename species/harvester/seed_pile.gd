class_name SeedPile
extends FoodSource
## A scattered cluster of individual seeds. Each seed is its own point:
## foragers walk to the nearest remaining seed and carry it off, so the pile
## visibly thins out seed by seed.
##
## params: pos, radius, count, seed_size (world units, half-length), seed_mass,
##         seed (rng seed), sense_radius

## How close an ant must be to a seed to pick it up.
const REACH := 7.0
## Seed image resolution (pixels per world unit) for carried seeds.
const ITEM_RES := 2.0
const PALETTE: Array[Color] = [Color(0.8, 0.63, 0.36), Color(0.68, 0.5, 0.27), Color(0.87, 0.74, 0.47), Color(0.58, 0.41, 0.22)]

var radius: float = 30.0
var seed_size: float = 2.4
var seed_mass: float = 0.4

## Per-seed state (index = seed number).
var seed_pos: PackedVector2Array = []
var seed_rot: PackedFloat32Array = []
var seed_scale: PackedFloat32Array = []
var seed_color: PackedColorArray = []
var seed_alive: PackedByteArray = []
var seeds_left: int = 0
var initial_count: int = 0

func setup(sim: Simulation, params: Dictionary) -> void:
	super.setup(sim, params)
	radius = params.get("radius", radius)
	seed_size = params.get("seed_size", seed_size)
	seed_mass = params.get("seed_mass", seed_mass)
	var count := int(params.get("count", 150))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", sim.rng.randi()))
	for n in count:
		# Denser in the middle: radius ~ u^0.75 instead of sqrt(u).
		var p := position + Vector2.from_angle(rng.randf() * TAU) * radius * pow(rng.randf(), 0.75)
		seed_pos.append(p)
		seed_rot.append(rng.randf() * TAU)
		seed_scale.append(rng.randf_range(0.8, 1.2))
		seed_color.append(PALETTE[rng.randi() % PALETTE.size()])
		seed_alive.append(1)
	seeds_left = count
	initial_count = count

func is_sensed_at(pos: Vector2, _colony: Colony) -> bool:
	return seeds_left > 0 and pos.distance_to(position) <= radius + sense_radius

func sense_bound() -> float:
	return radius + sense_radius + 1.0

## Position of the remaining seed nearest to pos.
func nearest_access_point(pos: Vector2) -> Vector2:
	var s := _nearest_seed(pos, INF)
	return position if s < 0 else seed_pos[s]

func is_depleted() -> bool:
	return seeds_left <= 0

func remaining_mass() -> float:
	var total := 0.0
	for s in seed_pos.size():
		if seed_alive[s] != 0:
			total += _mass_of(s)
	return total

## Picks up the nearest seed within reach of the ant.
func take(sim: Simulation, ant: int) -> Item:
	var s := _nearest_seed(sim.pos[ant], REACH)
	if s < 0:
		return null
	seed_alive[s] = 0
	seeds_left -= 1
	var item := sim.create_item("seed", _mass_of(s))
	item.source_id = id
	item.color = seed_color[s]
	item.shape = _seed_image(s)
	item.pixel_size = 1.0 / ITEM_RES
	taken_mass += item.mass
	version += 1
	return item

func _mass_of(s: int) -> float:
	return seed_mass * seed_scale[s] * seed_scale[s]

func _nearest_seed(pos: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for s in seed_pos.size():
		if seed_alive[s] == 0:
			continue
		var d := seed_pos[s].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best

## Small anti-aliased seed (ellipse with a highlight) for the carried item,
## drawn lengthwise across the carrier's jaws.
func _seed_image(s: int) -> Image:
	var half := Vector2(seed_size * 1.6, seed_size) * seed_scale[s]
	var size := Vector2i(ceili(half.y * 2.0 * ITEM_RES) + 2, ceili(half.x * 2.0 * ITEM_RES) + 2)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size) * 0.5
	var base := seed_color[s]
	for y in size.y:
		for x in size.x:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / ITEM_RES
			var d := Vector2(p.x / half.y, p.y / half.x).length()
			var a := clampf((1.0 - d) * half.y * ITEM_RES, 0.0, 1.0)
			if a > 0.0:
				var hl := clampf(1.0 - (p - Vector2(-0.3, -0.4) * half.y).length() / (half.y * 0.7), 0.0, 1.0)
				var c := base.lightened(hl * 0.35).darkened((1.0 - hl) * d * 0.25)
				c.a = a
				img.set_pixel(x, y, c)
	return img
