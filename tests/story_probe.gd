extends SceneTree
## Headless probe of a colony's story beats, for placing camera keyframes and
## captions (M17c): runs a scenario and prints the simulated time (and where)
## of the first egg, the first laid egg's larva/pupa/callow/worker, the first
## emergence, the dig up and the entrance opening, the first leaf cut, the first
## fragment underground and planted, the first gongylidia fed to a larva, the
## first major and patrol, debris picked up and cleared off the trail, the first
## worker death and corpse on a midden, population steps, and a summary every
## `every` seconds (where leaf is being cut, middens). Once the nurseries are
## in use: where they are, and the first egg laid after them (and after
## `track_after` sim seconds) through its stages, carries and feeds.
##
##   godot --headless --path . -s res://tests/story_probe.gd -- leafcutter_life [seed] [sim_seconds] [every] [track_after]
##
## Positions are sim coordinates: "surface" ones are the camera's world
## coordinates, "nest" ones the underground layer's (the nest camera's).

const POP_STEPS := [5, 10, 20, 50, 100, 200, 300, 500, 1000, 1500, 2000, 3000, 4000, 5000]

var sim: Simulation
var nest: NestType
var colony: Colony
var _seen: Dictionary = {}
var _hunger: Dictionary = {}  # brood id -> hunger last tick (until the first feed)
var _first_laid: int = -1
var _first_laid_stage: int = -1
var _debris_carried: Dictionary = {}  # item id -> where it was picked up
var _pop_step: int = 0
## The nursery brood item (_check_nursery_brood): tracked from the first egg
## laid after the nurseries are in use and after _track_after sim seconds.
var _track_after: float = 0.0
var _nb_id: int = -1
var _nb_laid_before: int = -1
var _nb_stage: int = 0
var _nb_carried := false
var _nb_hunger: float = INF
var _nb_done := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "leafcutter_life"
	var seed_value := int(args[1]) if args.size() > 1 else -1
	var seconds := float(args[2]) if args.size() > 2 else 3000.0
	var every := float(args[3]) if args.size() > 3 else 300.0
	_track_after = float(args[4]) if args.size() > 4 else 0.0
	var config := load("res://sim/default_config.tres") as SimConfig
	var registry := Registry.create_default()
	sim = ScenarioLoader.load_simulation(scenario, registry, config, seed_value)
	colony = sim.colonies[0]
	nest = colony.nest
	print("story_probe %s seed %d, %d s" % [scenario, sim.rng.seed, roundi(seconds)])
	print("  nest (surface) %s" % _v(nest.position))
	if nest.get("portal") != null:
		var p: Portal = nest.get("portal")
		print("  main entrance: surface %s, nest %s" % [_v(p.pos_a), _v(p.pos_b)])
	if nest is ColonyNest and (nest as ColonyNest).queen_ant >= 0:
		print("  queen (nest) %s" % _v(sim.pos[(nest as ColonyNest).queen_ant]))
	var ticks := roundi(seconds * config.tick_rate)
	var per := roundi(every * config.tick_rate)
	var t0 := Time.get_ticks_msec()
	for t in ticks:
		sim.step()
		_check_tick()
		if (t + 1) % int(config.tick_rate) == 0:
			_check_second()
		if (t + 1) % per == 0:
			_summary()
	print("done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

func _v(p: Vector2) -> String:
	return "(%.0f, %.0f)" % [p.x, p.y]

## Prints a beat the first time it happens.
func _beat(key: String, text: String) -> void:
	if _seen.has(key):
		return
	_seen[key] = sim.time()
	print("t=%7.1f  %s" % [sim.time(), text])

## Every tick: brood changes (feeds last one tick) and debris pick-ups.
func _check_tick() -> void:
	if nest is ColonyNest and (nest as ColonyNest).brood != null:
		_check_brood((nest as ColonyNest).brood)
	for id in sim.ground_clutter():
		var item: Item = sim.items[id]
		if _debris_carried.has(id):
			var from: Vector2 = _debris_carried[id]
			_debris_carried.erase(id)
			var what := "first debris cleared: put down %s, %.0f from where it lay %s" % [_v(item.position), item.position.distance_to(from), _v(from)]
			if not _seen.has("debris_cleared"):
				_beat("debris_cleared", what)
			elif not _seen.has("debris_cleared_3"):
				_seen["debris_n"] = int(_seen.get("debris_n", 1)) + 1
				print("t=%7.1f  debris cleared #%d: %s" % [sim.time(), _seen["debris_n"], _v(item.position)])
				if _seen["debris_n"] >= 5:
					_seen["debris_cleared_3"] = sim.time()
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.carried[i] < 0:
			continue
		var item := sim.item_of(i)
		if item != null and item.obstructs and not _debris_carried.has(item.id):
			_debris_carried[item.id] = item.position
			_beat("debris_picked", "first debris picked up by a %s at %s" % [sim.caste_of(i).id, _v(sim.pos[i])])

func _check_brood(brood: Brood) -> void:
	if brood.eggs_laid > 0 and _first_laid < 0:
		_first_laid = brood.lay_ids[0]
		_first_laid_stage = 0
		var k := brood.index_of(_first_laid)
		_beat("egg", "first egg laid (id %d) at nest %s" % [_first_laid, _v(brood.pos[k]) if brood.care else "?"])
	if _first_laid >= 0 and _first_laid_stage < 4:
		var k := brood.index_of(_first_laid)
		if k >= 0 and brood.stage[k] != _first_laid_stage:
			_first_laid_stage = brood.stage[k]
			_beat("laid_" + Brood.STAGE_KEYS[_first_laid_stage], "first laid egg is now a %s at nest %s" % [Brood.STAGE_KEYS[_first_laid_stage],
					_v(brood.pos[k]) if brood.care else "?"])
		elif k < 0:
			_first_laid_stage = 4
			var ant := brood.emerged_as(_first_laid)
			_beat("laid_worker", "first laid egg ecloses as ant %d%s" % [ant,
					(" (%s) at nest %s" % [sim.caste_of(ant).id, _v(sim.pos[ant])]) if ant >= 0 else " (gone: died or abstract)"])
	_check_nursery_brood(brood)
	if brood.emerged > 0:
		var a := brood.emerge_ants[0]
		_beat("emerged", "first worker ecloses: ant %d%s" % [a, (" at nest %s" % _v(sim.pos[a])) if a >= 0 else ""])
	for s: int in [1, 2, 3]:
		if not _seen.has("any_" + Brood.STAGE_KEYS[s]) and brood.count_stage(s) > 0 and brood.eggs_laid > 0:
			# First of a stage grown from a laid egg (not the initial brood).
			for k in brood.count():
				if brood.stage[k] == s and brood.id[k] >= _first_laid and _first_laid >= 0:
					_beat("any_" + Brood.STAGE_KEYS[s], "first laid brood to reach %s: id %d at nest %s" % [Brood.STAGE_KEYS[s], brood.id[k],
							_v(brood.pos[k]) if brood.care else "?"])
					break
	# Gongylidia: a larva's hunger drops when a nurse feeds it.
	if brood.care and (int(_seen.get("feeds", 0)) < 3 or (_first_laid_stage == Brood.Stage.LARVA and int(_seen.get("laid_feeds", 0)) < 4)):
		var now := {}
		for k in brood.count():
			if brood.stage[k] != Brood.Stage.LARVA:
				continue
			var id := brood.id[k]
			now[id] = brood.hunger[k]
			if _hunger.has(id) and brood.hunger[k] < float(_hunger[id]) - 0.05:
				if id == _first_laid:
					_seen["laid_feeds"] = int(_seen.get("laid_feeds", 0)) + 1
				elif int(_seen.get("feeds", 0)) >= 3:
					continue
				_seen["feeds"] = int(_seen.get("feeds", 0)) + 1
				var feeder := _nearest_ant(brood.pos[k], nest.underground_layer, "nurse")
				print("t=%7.1f  larva %d fed (feed #%d) at nest %s by %s" % [sim.time(), id, _seen["feeds"], _v(brood.pos[k]),
						("ant %d (%s)" % [feeder, sim.caste_of(feeder).id]) if feeder >= 0 else "?"])
		_hunger = now

## Once the nurseries are in use (and after `_track_after`): where they are,
## then the first egg laid from then on through its stages, carries and feeds
## to the ant it becomes (for a lifecycle chapter across the nurseries).
func _check_nursery_brood(brood: Brood) -> void:
	var cn := nest as ColonyNest
	if cn == null or not brood.care or cn.nursery[Brood.Stage.EGG] < 0:
		return
	if not _seen.has("nurseries"):
		var at: Array[String] = []
		for s in 3:
			at.append("%s %s" % [Brood.STAGE_KEYS[s], _v(cn.chambers_layout.list[cn.nursery[s]].centre)])
		_beat("nurseries", "nurseries in use: " + ", ".join(at))
	if sim.time() < _track_after:
		return
	if _nb_id < 0:
		if brood.eggs_laid > _nb_laid_before and _nb_laid_before >= 0:
			_nb_id = brood.lay_ids[(brood.eggs_laid - 1) % Brood.EVENT_LOG]
			var k0 := brood.index_of(_nb_id)
			if k0 >= 0:
				print("t=%7.1f  nursery brood: egg id %d laid at nest %s" % [sim.time(), _nb_id, _v(brood.pos[k0])])
			else:
				_nb_id = -1
		_nb_laid_before = brood.eggs_laid
		return
	if _nb_done:
		return
	var k := brood.index_of(_nb_id)
	if k < 0:
		_nb_done = true
		var ant := brood.emerged_as(_nb_id)
		print("t=%7.1f  nursery brood %d ecloses as ant %d%s" % [sim.time(), _nb_id, ant,
				(" (%s) at nest %s" % [sim.caste_of(ant).id, _v(sim.pos[ant])]) if ant >= 0 else " (gone)"])
		return
	if brood.stage[k] != _nb_stage:
		_nb_stage = brood.stage[k]
		print("t=%7.1f  nursery brood %d is now a %s at nest %s" % [sim.time(), _nb_id, Brood.STAGE_KEYS[_nb_stage], _v(brood.pos[k])])
	var carried := brood.carrier[k] >= 0
	if carried != _nb_carried:
		_nb_carried = carried
		print("t=%7.1f  nursery brood %d %s at nest %s" % [sim.time(), _nb_id, "picked up" if carried else "put down", _v(brood.pos[k])])
	if brood.stage[k] == Brood.Stage.LARVA:
		if brood.hunger[k] < _nb_hunger - 0.05:
			print("t=%7.1f  nursery brood %d fed at nest %s" % [sim.time(), _nb_id, _v(brood.pos[k])])
		_nb_hunger = brood.hunger[k]

func _nearest_ant(at: Vector2, l: int, state_id: String) -> int:
	var best := -1
	var best_d := INF
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.layer[i] != l or (state_id != "" and sim.state_id(i) != state_id):
			continue
		var d := sim.pos[i].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best

## Once a second: states, castes, entrance, leaf line, corpses.
func _check_second() -> void:
	var p: Portal = nest.get("portal")
	var majors := 0
	var patrolling := -1
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != colony.id:
			continue
		var st := sim.state_id(i)
		var caste := str(sim.caste_of(i).id)
		match st:
			"dig":
				if p != null and not p.open:
					_beat("dig", "first digger (%s) at nest %s" % [caste, _v(sim.pos[i])])
			"cut_leaf":
				var src := sim.food_by_id(sim.scratch_i[i])
				_beat("cut", "first leaf cut by a %s at %s (leaf at %s)" % [caste, _v(sim.pos[i]), _v(src.position) if src != null else "?"])
			"hitchhike":
				_beat("hitchhike", "first hitchhiking minim at %s" % _v(sim.pos[i]))
			"carry_down":
				_beat("carry_down", "first fragment carried down, at nest %s" % _v(sim.pos[i]))
			"carry_spent":
				_beat("carry_spent", "first spent garden carried out (%s at layer %d %s)" % [caste, sim.layer[i], _v(sim.pos[i])])
			"carry_corpse":
				_beat("carry_corpse", "first corpse carried (by a %s, layer %d at %s)" % [caste, sim.layer[i], _v(sim.pos[i])])
			"clear_debris":
				_beat("clear_debris", "first major sent to clear debris at %s" % _v(sim.pos[i]))
		if caste == "major":
			majors += 1
			if st == "patrol_trail" and patrolling < 0:
				patrolling = i
	if majors > 0:
		_beat("major", "first major")
	if patrolling >= 0:
		_beat("patrol", "first major patrolling the trail at %s" % _v(sim.pos[patrolling]))
	if p != null and p.open:
		_beat("open", "entrance open: surface %s, nest %s" % [_v(p.pos_a), _v(p.pos_b)])
	var items := int(nest.get("leaf_items")) if nest.get("leaf_items") != null else 0
	if items > 0:
		var where := ""
		var floor: Variant = nest.get("leaf_on_floor")
		if floor is PackedInt32Array and not (floor as PackedInt32Array).is_empty() and sim.items.has(floor[0]):
			where = " at nest %s" % _v(sim.items[floor[0]].position)
		_beat("leaf_under", "first leaf fragment arrives underground" + where)
	# Planted mass also counts the founding queen's manuring: watch it rise
	# after the first fragment arrives.
	if nest.get("planted_mass") != null:
		var planted := float(nest.get("planted_mass"))
		if not _seen.has("leaf_under"):
			_seen["planted_before"] = planted
		elif planted > float(_seen.get("planted_before", 0.0)) + 1e-4:
			_beat("planted", "first leaf pulp planted in the garden")
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.state_id(i) == "garden" and sim.carried[i] >= 0 and _seen.has("leaf_under"):
			_beat("garden_leaf", "first gardener with leaf (pulp) at nest %s" % _v(sim.pos[i]))
			break
	if nest.worker_deaths > 0:
		var where := ""
		if not nest.corpses.is_empty() and sim.items.has(nest.corpses[0]):
			var it: Item = sim.items[nest.corpses[0]]
			where = " at %s" % _v(it.position)
		_beat("death", "first worker dies of age" + where)
	for m in nest.middens:
		var k := m.kinds.find("corpse")
		if k >= 0:
			var d := m.dep_kind.find(k)
			_beat("corpse_midden", "first corpse on a midden (m%d at %s)" % [m.index, _v(m.dep_pos[d]) if d >= 0 else _v(m.position)])
	if nest.dumped_items > 0 and not nest.middens.is_empty():
		_beat("midden", "first load on a midden: m0 at %s" % _v(nest.middens[0].position))
	var founding: Variant = nest.get("founding")
	if founding is Founding:
		var f := founding as Founding
		var names := ["flying", "shedding wings", "walking the site", "digging down", "going down", "home in her niche"]
		_beat("landing_%d" % f.phase, "queen's landing: %s" % names[f.phase])
	var alates: Variant = nest.get("alates")
	if alates is Alates:
		var a := alates as Alates
		if a.raised > 0:
			_beat("alate_egg", "first alate egg laid (of %d)" % a.count)
		if a.raised >= a.count:
			_beat("alate_eggs", "all %d alate eggs laid" % a.count)
		if a.alive_count() > 0:
			_beat("alate_1", "first alate emerged")
			if a.alive_count() >= a.count:
				_beat("alate_all", "all %d alates emerged and waiting" % a.count)
			_beat("alates_%d" % a.alive_count(), "  alates alive %d" % a.alive_count())
		if a.flying:
			_beat("flight", "nuptial flight called (%d alates)" % a.alive_count())
		if a.flying:
			var n := [0, 0, 0, 0]
			for k in a.ants.size():
				n[a.phase[k]] += 1
			print("t=%7.1f    alates waiting %d, going up %d, on the mound %d, taking off %d, flown %d" % [sim.time(), n[0], n[1], n[2], n[3], a.flown])
		if a.launched > 0:
			_beat("take_off", "first alate takes off")
		if a.flown > 0:
			_beat("flown_1", "first alate gone")
		if a.flown >= a.count:
			_beat("flown_all", "all %d alates gone" % a.count)
	var pop := colony.total_population()
	while _pop_step < POP_STEPS.size() and pop >= POP_STEPS[_pop_step]:
		print("t=%7.1f  population %d" % [sim.time(), POP_STEPS[_pop_step]])
		_pop_step += 1

func _summary() -> void:
	var castes := {}
	var surface := 0
	for i in sim.high_water:
		if sim.alive[i] == 0 or sim.colony_id[i] != colony.id:
			continue
		var c := str(sim.caste_of(i).id)
		castes[c] = int(castes.get(c, 0)) + 1
		if sim.layer[i] == 0:
			surface += 1
	var line := "--- t=%5ds pop %d (agents %s, %d on surface)" % [roundi(sim.time()), colony.total_population(), castes, surface]
	if nest is ColonyNest and (nest as ColonyNest).brood != null:
		line += " brood %d" % (nest as ColonyNest).brood.count()
	if nest.get("fungus") != null:
		line += " fungus %.1f leaf items %d" % [float(nest.get("fungus")), int(nest.get("leaf_items"))]
	line += " entrances %d/%d deaths %d dumped %d" % [1 + nest.extra_portals.filter(func(q: Portal) -> bool: return q.open).size(),
			1 + nest.extra_portals.size(), nest.worker_deaths, nest.dumped_items]
	print(line)
	# Leaves being cut now, and middens.
	var cutting := {}
	for i in sim.high_water:
		if sim.alive[i] != 0 and sim.state_id(i) == "cut_leaf":
			cutting[sim.scratch_i[i]] = int(cutting.get(sim.scratch_i[i], 0)) + 1
	for f in sim.food_sources:
		if cutting.has(f.id) or not f.is_depleted():
			print("      leaf %d at %s: %d cutting, %.0f%% left" % [f.id, _v(f.position), int(cutting.get(f.id, 0)),
					100.0 * f.remaining_mass() / maxf(0.001, f.remaining_mass() + f.taken_mass)])
	for m in nest.middens:
		print("      midden m%d at %s: %d deposits" % [m.index, _v(m.position), m.count()])
	for q in nest.extra_portals:
		print("      entrance %s (%s)" % [_v(q.pos_a), "open" if q.open else "digging"])
