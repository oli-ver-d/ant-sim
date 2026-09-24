class_name Highways
extends RefCounted
## Busy tunnels grow into highways (nest_params underground "highways", see
## NestType): the nest's tunnels are watched in sections, and a section whose
## traffic (the layer's TrafficMap) stays above `threshold` for `sustain`
## checks in a row is widened: a path job along it, its kinks smoothed out,
## with `grow` times the radius, up to `max_radius`. So the busiest routes
## become wide, smooth galleries while quiet side tunnels stay narrow. A
## section already at full width that is still congested (`bypass` times the
## threshold) gets a bypass: a second tunnel routed alongside it
## (SimLayer.route keeps it clear of the first), so the traffic splits.
##
## A section's traffic is the traffic summed over the cells within its
## radius, per unit of its length: roughly the ants that walked through it
## in the traffic map's window times the seconds each spends on a unit of
## tunnel.
##
## Tunnels watched: every path job of the plan once it is finished (unless
## tagged {"widen": false}), and any given to watch() (e.g. tunnels a nest
## starts with, carved at once).
##
## params: check_every (s, 20), threshold (45), sustain (3), grow (1.35),
##         max_radius (14), section (world units, 50), bypass (1.8),
##         max_bypasses (6), priority (plan priority of the widening jobs, -0.5),
##         half_life (s, the traffic map's, 60), lanes (SimLayer.lanes, 0.8)

class Section:
	var points: PackedVector2Array = []
	var radii: PackedFloat32Array = []
	var length: float = 0.0
	## Checks in a row above the threshold.
	var hot: int = 0
	## Times widened.
	var level: int = 0
	## The widening or bypass job being dug (-1: none).
	var job: int = -1
	var bypassed: bool = false
	## Its traffic at the last check (for views and tests).
	var traffic: float = 0.0

var plan: ExcavationPlan
var layer: SimLayer
var traffic: TrafficMap
var sections: Array[Section] = []
var check_every: float = 20.0
var threshold: float = 45.0
var sustain: int = 3
var grow: float = 1.35
var max_radius: float = 14.0
var section_length: float = 50.0
var bypass: float = 1.8
var max_bypasses: int = 6
var priority: float = -0.5
## Widenings and bypasses planned so far.
var widened: int = 0
var bypasses: int = 0
var _timer: float = 0.0
## Per plan job: 1 once looked at.
var _jobs_seen: PackedByteArray = []

func setup(sim: Simulation, on_plan: ExcavationPlan, params: Dictionary) -> void:
	plan = on_plan
	layer = sim.layers[plan.layer]
	check_every = float(params.get("check_every", check_every))
	threshold = float(params.get("threshold", threshold))
	sustain = int(params.get("sustain", sustain))
	grow = float(params.get("grow", grow))
	max_radius = float(params.get("max_radius", max_radius))
	section_length = float(params.get("section", section_length))
	bypass = float(params.get("bypass", bypass))
	max_bypasses = int(params.get("max_bypasses", max_bypasses))
	priority = float(params.get("priority", priority))
	var half_life := float(params.get("half_life", 60.0))
	traffic = layer.enable_traffic(half_life, sim.dt)
	# The surface counts its traffic too (for views; its trunk trails).
	sim.layers[0].enable_traffic(half_life, sim.dt)
	layer.lanes = float(params.get("lanes", 0.8))

## Watches a tunnel (points with a radius each), cut into sections.
func watch(points: PackedVector2Array, radii: PackedFloat32Array) -> void:
	if points.size() < 2:
		return
	var total := Router.length_of(points)
	var n := maxi(1, roundi(total / section_length))
	for k in n:
		var s := Section.new()
		var from := total * k / n
		var to := total * (k + 1) / n
		# Each section overlaps its neighbours a little, so widenings join up.
		var pts := _sub_path(points, maxf(0.0, from - 6.0), minf(total, to + 6.0))
		s.points = pts
		s.length = Router.length_of(pts)
		for p in pts:
			s.radii.append(_radius_at(points, radii, p))
		sections.append(s)

## Once a tick; every check_every seconds it picks up finished tunnels,
## checks every section's traffic and plans what is due.
func update(_sim: Simulation, dt: float) -> void:
	_timer += dt
	if _timer < check_every:
		return
	_timer = 0.0
	# Newly finished path jobs.
	_jobs_seen.resize(plan.jobs.size())
	for job in plan.jobs:
		if _jobs_seen[job.id] != 0 or not job.done:
			continue
		_jobs_seen[job.id] = 1
		if job.shape != null and job.shape.kind == DigShape.Kind.PATH and bool(job.tags.get("widen", true)):
			watch(job.shape.points, job.shape.radii)
	for s in sections:
		if s.job >= 0:
			if not plan.job_by_id(s.job).done:
				continue
			s.job = -1
		s.traffic = section_traffic(s)
		s.hot = s.hot + 1 if s.traffic > threshold else maxi(0, s.hot - 1)
		if s.hot < sustain:
			continue
		s.hot = 0
		if _max_radius_of(s) < max_radius - 0.5:
			_widen(s)
		elif not s.bypassed and bypasses < max_bypasses and s.traffic > threshold * bypass:
			_bypass(s)

## Traffic through section s (see the class notes).
func section_traffic(s: Section) -> float:
	return traffic.sum_path(s.points, _max_radius_of(s)) / maxf(s.length, 1.0)

func _max_radius_of(s: Section) -> float:
	var m := 0.0
	for r in s.radii:
		m = maxf(m, r)
	return m

## Plans a wider, smoother tunnel along section s.
func _widen(s: Section) -> void:
	var pts := Router.smooth(Router.smooth(s.points))
	var radii := PackedFloat32Array()
	for p in pts:
		radii.append(minf(max_radius, _radius_at(s.points, s.radii, p) * grow))
	@warning_ignore("integer_division")
	var mid := s.points[s.points.size() / 2]
	var job := plan.add_path_job("highway%d" % widened, mid, pts, radii, priority, 6)
	job.tags["widen"] = false
	job.tags["highway"] = true
	s.points = pts
	s.radii = radii
	s.level += 1
	s.job = job.id if not job.done else -1
	widened += 1

## Plans a tunnel alongside section s, from a little before it to a little
## after (routed clear of it), as wide as a capillary highway.
func _bypass(s: Section) -> void:
	s.bypassed = true
	var a := s.points[0]
	var b := s.points[s.points.size() - 1]
	var route := layer.route(a, b, {"avoid": plan.planned_cells(), "clearance": _max_radius_of(s) + 10.0,
			"end_radius": _max_radius_of(s) + 4.0, "seed": bypasses * 31 + 7, "margin": 60.0})
	if route.size() < 2 or Router.length_of(route) > s.length * 2.5:
		return
	var r := maxf(5.0, max_radius * 0.5)
	var radii := PackedFloat32Array()
	for p in route:
		radii.append(r)
	var job := plan.add_path_job("bypass%d" % bypasses, a, route, radii, priority + 0.3, 6)
	s.job = job.id if not job.done else -1
	bypasses += 1

## The radius of a tunnel (points, radii) at its point nearest `at`.
static func _radius_at(points: PackedVector2Array, radii: PackedFloat32Array, at: Vector2) -> float:
	var best := INF
	var r := radii[0]
	for k in points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(at, points[k], points[k + 1])
		var d := q.distance_squared_to(at)
		if d < best:
			best = d
			var seg := points[k].distance_to(points[k + 1])
			var t := points[k].distance_to(q) / seg if seg > 1e-6 else 0.0
			r = lerpf(radii[k], radii[k + 1], t)
	return r

## The part of a polyline between arc lengths `from` and `to`.
static func _sub_path(points: PackedVector2Array, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := 0.0
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var seg_len := a.distance_to(b)
		var s1 := s + seg_len
		if s1 >= from and s <= to:
			var t0 := clampf((from - s) / seg_len, 0.0, 1.0) if seg_len > 1e-6 else 0.0
			var t1 := clampf((to - s) / seg_len, 0.0, 1.0) if seg_len > 1e-6 else 1.0
			if out.is_empty():
				out.append(a.lerp(b, t0))
			out.append(a.lerp(b, t1))
		s = s1
	return out

## Fingerprint for Simulation.state_hash().
func hash_into(ctx: HashingContext) -> void:
	var state := PackedInt32Array([widened, bypasses, sections.size()])
	for s in sections:
		state.append(s.hot)
	ctx.update(state.to_byte_array())
