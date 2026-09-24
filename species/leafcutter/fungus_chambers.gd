class_name FungusChambers
extends RefCounted
## The chambers of a leafcutter nest that digs its own underground (see
## FungusNest, nest_params "underground"): the royal chamber in the middle,
## where the queen lives and the founding garden grows, and garden chambers
## the colony digs as it grows, each at the end of a tunnel branching off an
## existing chamber.
##
## New chambers are placed procedurally from the scenario seed (their own
## RNG, so the simulation's random stream is untouched): a parent is picked
## (more often a recent one, so the nest sprawls outward), then a direction
## away from the nest's middle and a tunnel length; candidates that would
## crowd another chamber or leave the layer are rejected. Each chamber is two
## ExcavationPlan jobs: the tunnel from the parent's rim, then the round
## chamber, dug from where the tunnel comes in.

enum Kind { ROYAL, GARDEN }

class Chamber:
	var index: int
	var kind: int
	var centre: Vector2
	var radius: float
	var parent: int = -1
	## Plan jobs (-1: carved from the start).
	var tunnel_job: int = -1
	var job: int = -1
	var dug: bool = false
	## Nav field toward the centre (on the nest's layer).
	var nav_field: int = -1
	## Where a tunnel from the parent enters (for drawing).
	var door: Vector2

var list: Array[Chamber] = []
## Bottom of the entrance shaft (the portal's underground end).
var shaft: Vector2
var layer_size: Vector2
## Chamber radius range for new garden chambers, and the tunnel between.
var min_radius: float = 38.0
var max_radius: float = 62.0
var tunnel_radius: float = 7.0
var min_gap: float = 26.0
var _rng := RandomNumberGenerator.new()

func setup(size: Vector2, seed_value: int, params: Dictionary) -> void:
	layer_size = size
	_rng.seed = seed_value * 7919 + 101
	min_radius = float(params.get("chamber_min_radius", min_radius))
	max_radius = float(params.get("chamber_max_radius", max_radius))
	tunnel_radius = float(params.get("tunnel_radius", tunnel_radius))
	var royal := Chamber.new()
	royal.index = 0
	royal.kind = Kind.ROYAL
	royal.centre = ScenarioEvents.vec2(params["royal"]) if params.has("royal") else size * 0.5
	royal.radius = float(params.get("royal_radius", 36.0))
	royal.dug = true
	royal.door = royal.centre
	list.append(royal)
	# The shaft comes down a little way from the royal chamber, up and to one side.
	var a := _rng.randf_range(-2.4, -0.7)
	shaft = ScenarioEvents.vec2(params["shaft"]) if params.has("shaft") else \
			royal.centre + Vector2.from_angle(a) * (royal.radius + float(params.get("shaft_distance", 46.0)))

func royal() -> Chamber:
	return list[0]

func count() -> int:
	return list.size()

## Chambers dug out so far.
func dug_count() -> int:
	var n := 0
	for c in list:
		if c.dug:
			n += 1
	return n

## The chamber containing `at` (within its radius), or -1.
func chamber_at(at: Vector2) -> int:
	for c in list:
		if at.distance_squared_to(c.centre) <= c.radius * c.radius:
			return c.index
	return -1

## Picks a place for a new garden chamber and returns it (not yet planned),
## or null if nothing fits.
func propose() -> Chamber:
	for attempt in 40:
		# Recent chambers are likelier parents, so the nest grows outward.
		var n := list.size()
		var parent := list[mini(n - 1, int(pow(_rng.randf(), 0.6) * n))]
		var r := _rng.randf_range(min_radius, max_radius)
		var away := (parent.centre - list[0].centre)
		var base := away.angle() if away.length() > 1.0 else _rng.randf_range(-PI, PI)
		var dir := Vector2.from_angle(base + _rng.randf_range(-1.3, 1.3))
		var dist := parent.radius + r + _rng.randf_range(35.0, 90.0)
		var centre := parent.centre + dir * dist
		if not Rect2(Vector2.ZERO, layer_size).grow(-r - 50.0).has_point(centre):
			continue
		var ok := centre.distance_to(shaft) > r + 30.0
		for c in list:
			if ok and centre.distance_to(c.centre) < c.radius + r + min_gap:
				ok = false
		# The tunnel mustn't run through another chamber.
		for c in list:
			if ok and c != parent and Geometry2D.get_closest_point_to_segment(c.centre, parent.centre, centre).distance_to(c.centre) < c.radius + tunnel_radius + 6.0:
				ok = false
		if not ok:
			continue
		var ch := Chamber.new()
		ch.index = n
		ch.kind = Kind.GARDEN
		ch.centre = centre
		ch.radius = r
		ch.parent = parent.index
		ch.door = centre - dir * r * 0.9
		return ch
	return null

## Plans a proposed chamber: its tunnel and itself as plan jobs, and a nav
## field toward its centre. `priority` orders it among other digging.
func add(ch: Chamber, plan: ExcavationPlan, priority: float) -> void:
	var parent := list[ch.parent]
	var dir := (ch.centre - parent.centre).normalized()
	var start := parent.centre + dir * parent.radius * 0.8
	var tunnel_end := ch.centre - dir * ch.radius * 0.6
	var tunnel := plan.add_job("tunnel%d" % ch.index, start, start, tunnel_end, tunnel_radius, priority, 4)
	var chamber := plan.add_job("chamber%d" % ch.index, tunnel_end, ch.centre, ch.centre, ch.radius, priority + 0.5, 8)
	ch.tunnel_job = tunnel.id
	ch.job = chamber.id
	ch.nav_field = plan.nav.set_target_point(StringName("chamber:%d" % ch.index), ch.centre)
	list.append(ch)

## Marks chambers whose digging is finished. Returns how many became dug.
func update_dug(plan: ExcavationPlan) -> int:
	var n := 0
	for c in list:
		if not c.dug and c.job >= 0 and plan.job_by_id(c.job).done:
			c.dug = true
			n += 1
	return n

## A point in chamber `k`, `u` (0-1) of the way out from the centre at `angle`.
func point_in(k: int, angle: float, u: float) -> Vector2:
	var c := list[k]
	return c.centre + Vector2.from_angle(angle) * c.radius * u

## Adds a proposed chamber already dug out (a nest that starts established):
## its tunnel and itself are carved into the layer's soil at once.
func add_dug(ch: Chamber, world: World, nav: NavGrid) -> void:
	var parent := list[ch.parent]
	var dir := (ch.centre - parent.centre).normalized()
	world.carve_segment(parent.centre + dir * parent.radius * 0.8, ch.centre - dir * ch.radius * 0.6, tunnel_radius)
	world.carve_segment(ch.centre, ch.centre, ch.radius)
	ch.dug = true
	ch.nav_field = nav.set_target_point(StringName("chamber:%d" % ch.index), ch.centre)
	list.append(ch)
