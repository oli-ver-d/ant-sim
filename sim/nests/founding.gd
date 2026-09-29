class_name Founding
extends RefCounted
## A founding queen's arrival (ColonyNest, opt-in nest_params "founding":
## {"landing": {...}}): the queen starts on the surface as a winged alate at
## the end of her nuptial flight, in the "found_nest" state. She
##   1. flies in (FLYING): an eased curve from `from` down to `land`, her
##      altitude falling from `altitude` to 0 (views draw her wings beating
##      and her shadow offset by her height; she doesn't collide);
##   2. sheds her wings (SHEDDING): two Wing items (one pair each) dropped
##      beside her, which lie there until they decay (`wing_life`);
##   3. walks a short loop round the nest site (WALKING);
##   4. digs down where the entrance will be (DIGGING): the opening grows,
##      spoil pellets go on the heap;
##   5. goes down the shaft (GOING_DOWN, through the main portal even while
##      it is closed) and is put in her niche in the royal chamber (HOME),
##      where the "queen" state takes over. A sealed nest ("open": false)
##      stays sealed (the entrance is drawn refilled) and its first workers
##      dig the same shaft open later, as without a landing.
## Until she is home the underground waits: the nest's colony update
## (brood, roles, digging) doesn't run and the colony's starting workers
## (scenario "population") are held back, then placed in the royal chamber
## when she arrives. The garden or store and anything else the nest does
## outside ColonyNest._update_colony() go on as usual.
##
## params ("landing"): from [x, y] (surface point under her at the start;
##   default 480 units up and left of `land`, kept inside the world), land
##   [x, y] (default 30 units from the entrance toward `from`), altitude
##   (220), flight (s, 9), shed (s, 6), loop_radius (14), dig (s, 20),
##   spoil_pellets (6), wing_life (s, 900).

enum Phase { FLYING, SHEDDING, WALKING, DIGGING, GOING_DOWN, HOME }

var phase: int = Phase.FLYING
## Simulated time the current phase started.
var phase_at: float = 0.0
var from: Vector2
var land: Vector2
## Control point of the flight's curve.
var bend: Vector2
var altitude: float = 220.0
var flight: float = 9.0
var shed: float = 6.0
var loop_radius: float = 14.0
var dig: float = 20.0
var spoil_pellets: int = 6
var wing_life: float = 900.0
## Wings still on her (2 pairs, then 1, then 0).
var wings_on: int = 2
## Shed wings still lying on the ground (item ids).
var wings: PackedInt32Array = []
## The walk's waypoints and the one she is heading for.
var waypoints: PackedVector2Array = []
var waypoint: int = 0
## Spoil pellets put on the heap so far while digging.
var pellets: int = 0
## Caste indices of starting workers held back until she is home.
var waiting: PackedInt32Array = []

func setup(sim: Simulation, nest: ColonyNest, params: Dictionary) -> void:
	var e := nest.entrance_position()
	altitude = float(params.get("altitude", altitude))
	flight = maxf(0.1, float(params.get("flight", flight)))
	shed = float(params.get("shed", shed))
	loop_radius = float(params.get("loop_radius", loop_radius))
	dig = float(params.get("dig", dig))
	spoil_pellets = int(params.get("spoil_pellets", spoil_pellets))
	wing_life = float(params.get("wing_life", wing_life))
	var bounds := Rect2(Vector2.ZERO, Vector2(sim.world.size)).grow(-10.0)
	var start := ScenarioEvents.vec2(params["from"]) if params.has("from") else e + Vector2(-300, -380)
	land = ScenarioEvents.vec2(params["land"]) if params.has("land") else e + (start - e).normalized() * 30.0
	if not params.has("from"):
		start = land + (start - e).normalized() * 480.0
	from = Vector2(clampf(start.x, bounds.position.x, bounds.end.x), clampf(start.y, bounds.position.y, bounds.end.y))
	# A gentle curve, bowed to one side.
	var mid := from.lerp(land, 0.5)
	bend = mid + (land - from).orthogonal() * 0.22

## Places the queen on the surface at the start of her flight, in the
## "found_nest" state. Returns her index.
func spawn_queen(sim: Simulation, nest: ColonyNest, caste: int) -> int:
	var q := sim.spawn_ant(sim.colonies[nest.colony_id], caste, from, _tangent(0.0).angle(), 0)
	if q >= 0:
		sim.change_state(q, "found_nest")
		phase = Phase.FLYING
		phase_at = sim.time()
	return q

func is_home() -> bool:
	return phase == Phase.HOME

## Her height above the ground now (views; 0 once landed).
func queen_altitude(sim: Simulation) -> float:
	if phase != Phase.FLYING:
		return 0.0
	return altitude * pow(1.0 - _progress(sim), 1.5)

## Share of the current phase done, 0-1.
func _progress(sim: Simulation) -> float:
	var span: float = [flight, shed, 1.0, dig, 1.0, 1.0][phase]
	return clampf((sim.time() - phase_at) / maxf(span, 1e-3), 0.0, 1.0)

## Flight progress along the curve: slowing as she comes in to land.
static func _eased(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

func _point(u: float) -> Vector2:
	return from.lerp(bend, u).lerp(bend.lerp(land, u), u)

func _tangent(u: float) -> Vector2:
	return (bend - from).lerp(land - bend, u)

func _next(sim: Simulation, p: int) -> void:
	phase = p
	phase_at = sim.time()

## One tick of the queen in "found_nest" (FoundNestBehaviour). Returns the
## next state ("queen" once she is home).
func tick_queen(sim: Simulation, nest: ColonyNest, i: int, dt: float) -> String:
	if sim.layer[i] == nest.underground_layer:
		_arrive(sim, nest, i)
		return "queen"
	var t := _progress(sim)
	match phase:
		Phase.FLYING:
			var u := _eased(t)
			sim.pos[i] = _point(u)
			sim.heading[i] = _tangent(u).angle()
			if t >= 1.0:
				_next(sim, Phase.SHEDDING)
		Phase.SHEDDING:
			# She works each pair of wings off with her legs, turning a little.
			sim.heading[i] += sin((sim.time() - phase_at) * 3.0) * 0.6 * dt
			_step_legs(sim, i, 0.25, dt)
			if wings_on == 2 and t >= 0.35:
				_drop_wing(sim, nest, i, 1.0)
			if wings_on == 1 and t >= 0.75:
				_drop_wing(sim, nest, i, -1.0)
			if t >= 1.0:
				_plan_walk(nest)
				_next(sim, Phase.WALKING)
		Phase.WALKING:
			var goal := waypoints[waypoint]
			if sim.pos[i].distance_to(goal) <= 2.5:
				waypoint += 1
				if waypoint >= waypoints.size():
					_next(sim, Phase.DIGGING)
					return ""
				goal = waypoints[waypoint]
			var before := sim.pos[i]
			Steering.move_to(sim, i, goal, sim.speed[i] * 0.8, dt)
			sim.anim_phase[i] += before.distance_to(sim.pos[i]) * sim.colonies[sim.colony_id[i]].caste_phase_per_unit[sim.caste_id[i]]
		Phase.DIGGING:
			# Round and round over the hole as she bites soil out of it.
			var e := nest.entrance_position()
			sim.heading[i] = wrapf(sim.heading[i] + (0.5 + 0.4 * sin((sim.time() - phase_at) * 1.3)) * dt, -PI, PI)
			sim.pos[i] = sim.pos[i].move_toward(e, 2.0 * dt)
			_step_legs(sim, i, 0.4, dt)
			while pellets < int(t * spoil_pellets):
				pellets += 1
				var pellet := Item.new()
				pellet.mass = NestType.SPOIL_WEIGHT
				nest.receive_spoil(sim, pellet)
			if t >= 1.0:
				_next(sim, Phase.GOING_DOWN)
				sim.enter_portal(i, nest.portal, true)
	return ""

func _step_legs(sim: Simulation, i: int, pace: float, dt: float) -> void:
	sim.anim_phase[i] += sim.speed[i] * pace * dt * sim.colonies[sim.colony_id[i]].caste_phase_per_unit[sim.caste_id[i]]

## Drops one pair of wings beside her (side 1: right, -1: left).
func _drop_wing(sim: Simulation, nest: ColonyNest, i: int, side: float) -> void:
	var def := sim.caste_of(i)
	var w := sim.create_item("wing", 0.02) as Wing
	w.length = def.size * 1.15
	w.tint = def.color.lightened(0.55)
	w.side = side
	w.shed_at = sim.time()
	w.gone_at = sim.time() + wing_life
	w.radius = def.size * 0.6
	var h := sim.heading[i]
	# Off her back to that side, pointing back and out.
	var at := sim.pos[i] + Vector2.from_angle(h + side * PI * 0.5) * def.size * 0.45 - Vector2.from_angle(h) * def.size * 0.2
	sim.place_on_ground(w, at, h + PI - side * 0.5, 0)
	wings.append(w.id)
	wings_on -= 1

## The walk: from where she landed round the nest site and back to its middle.
func _plan_walk(nest: ColonyNest) -> void:
	var e := nest.entrance_position()
	var a0 := (land - e).angle()
	waypoints = PackedVector2Array()
	for k in range(1, 5):
		waypoints.append(e + Vector2.from_angle(a0 + k * TAU * 0.2) * loop_radius)
	waypoints.append(e)
	waypoint = 0

## She has come down the shaft: into her niche; the held-back workers join her.
func _arrive(sim: Simulation, nest: ColonyNest, i: int) -> void:
	var spot := nest.queen_spot()
	sim.pos[i] = spot
	sim.prev_pos[i] = spot
	sim.shown_pos[i] = spot
	sim.heading[i] = nest.queen_heading()
	sim.arrive_tick[i] = sim.tick_count
	_next(sim, Phase.HOME)
	var held := waiting
	waiting = PackedInt32Array()
	for c in held:
		nest.spawn_initial(sim, c)

## Once a tick: shed wings past their time are gone.
func update(sim: Simulation) -> void:
	var k := 0
	while k < wings.size():
		var w := sim.items.get(wings[k]) as Wing
		if w == null or w.carrier >= 0:
			wings.remove_at(k)
			continue
		if sim.time() >= w.gone_at:
			sim.destroy_item(w.id)
			wings.remove_at(k)
			continue
		k += 1

## How the main entrance looks during the landing, for views: [shown (0/1),
## open (0/1), size (share of its full radius)]. Nothing before she digs; a
## hole growing as she digs, open while she goes down. Only asked before
## she is home (after that the entrance is as the nest has it).
func entrance_look() -> Vector3:
	match phase:
		Phase.DIGGING:
			return Vector3(1, 1, lerpf(0.3, 0.8, float(pellets) / maxf(1.0, spoil_pellets)))
		Phase.GOING_DOWN:
			return Vector3(1, 1, 0.8)
	return Vector3(0, 0, 0)

func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedFloat64Array([phase, phase_at, wings_on, waypoint, pellets]).to_byte_array())
	ctx.update(wings.to_byte_array())
