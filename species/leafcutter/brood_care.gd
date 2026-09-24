class_name BroodCare
extends RefCounted
## Brood care work, shared by nurses and a founding queen (see
## LeafcutterBrood's care notes). An ant takes the most urgent unclaimed task
## and works it through:
##
##   FREE   a callow at the end of its stage: help it out of the casing
##   CARRY  an egg just laid by the queen, or brood lying away from its
##          stage's pile: pick it up and carry it there
##   FEED   a hungry larva: fetch gongylidia (a bite of fungus) from the
##          garden, bring it, feed it
##   GROOM  dirty brood: lick it clean
##
## Per-ant state (the ant's state is free to use these while it cares):
## scratch_i = brood id, scratch_f1 = task * 4 + step, scratch_f0 = seconds
## into the current bit of work (or, with no task, until the next look for
## one), target = where it is going.

enum Task { NONE, CARRY, FEED, GROOM, FREE }
const HARVEST_TIME := 1.2
const FEED_TIME := 1.6
const GROOM_TIME := 2.2
const FREE_TIME := 2.8
## A larva this hungry gets fed; brood this dirty gets groomed.
const HUNGRY := 0.55
const DIRTY := 0.45
## Brood this dirty is groomed before anything but freeing callows and
## taking eggs from the queen (at 1 it stops developing).
const FILTHY := 0.75
## Seconds between looks for work when there is none.
const LOOK_EVERY := 1.0

const Stage := LeafcutterBrood.Stage
const Pile := LeafcutterBrood.Pile

## One tick of care. Returns false if the ant has no task (none was found).
## only_chamber >= 0 limits it to brood in that chamber (the queen stays home).
static func tick(sim: Simulation, i: int, dt: float, nest: FungusNest, move_speed: float,
		only_chamber: int = -1) -> bool:
	var brood := nest.brood
	var code := int(sim.scratch_f1[i])
	if code >> 2 == Task.NONE:
		sim.scratch_f0[i] -= dt
		if sim.scratch_f0[i] > 0.0 or not _pick(sim, i, nest, only_chamber):
			if sim.scratch_f0[i] <= 0.0:
				sim.scratch_f0[i] = LOOK_EVERY
			return false
		code = int(sim.scratch_f1[i])
	var task := code >> 2
	var step := code & 3
	var k := brood.index_of(sim.scratch_i[i])
	if k < 0 or brood.claimed[k] != i:
		abandon(sim, i, nest)
		return true
	match task:
		Task.CARRY:
			if step == 0:
				if _walk(sim, i, nest, brood.pos[k], move_speed, dt, 2.5):
					brood.pick_up(k, i)
					_set_task(sim, i, task, 1)
			elif _walk(sim, i, nest, nest.pile_centre(LeafcutterBrood.home_pile(brood.stage[k])), move_speed * 0.85, dt, 4.0):
				brood.put_down(k, sim.pos[i], nest)
				_finish(sim, i, k)
		Task.FEED:
			if step == 0:
				if _walk(sim, i, nest, sim.target[i], move_speed, dt, 2.5):
					_set_task(sim, i, task, 1)
			elif step == 1:
				_work(sim, i, dt, sim.target[i] + Vector2(1, 0))
				if sim.scratch_f0[i] >= HARVEST_TIME:
					var m := nest.take_fungus_at(sim.target[i], brood.feed_mass(nest))
					if m <= 0.0:
						# Too little here: try another spot next time.
						abandon(sim, i, nest)
						return true
					var bite := sim.create_item("gongylidia", m)
					bite.radius = 1.3
					bite.color = Color(0.95, 0.94, 0.86)
					sim.pick_up(i, bite)
					_set_task(sim, i, task, 2)
			elif step == 2:
				if _walk(sim, i, nest, brood.pos[k], move_speed, dt, 3.0):
					_set_task(sim, i, task, 3)
			else:
				_work(sim, i, dt, brood.pos[k])
				if sim.scratch_f0[i] >= FEED_TIME:
					var item := sim.item_of(i)
					brood.feed(k, item.mass / brood.feed_mass(nest) if item != null else 1.0)
					if item != null:
						sim.carried[i] = -1
						item.carrier = -1
						sim.destroy_item(item.id)
					_finish(sim, i, k)
		Task.GROOM, Task.FREE:
			if step == 0:
				if _walk(sim, i, nest, brood.pos[k], move_speed, dt, 3.0):
					_set_task(sim, i, task, 1)
			else:
				_work(sim, i, dt, brood.pos[k])
				if sim.scratch_f0[i] >= (GROOM_TIME if task == Task.GROOM else FREE_TIME):
					if task == Task.GROOM:
						brood.groom(k)
						_finish(sim, i, k)
					else:
						brood.claimed[k] = -1
						_clear(sim, i)
						brood.free_callow(sim, nest, k, nest.first_state(sim, brood.caste[k]))
	return true

## Drops whatever task the ant has: brood it carries is put down where it
## is, fungus it carries goes back to the garden.
static func abandon(sim: Simulation, i: int, nest: FungusNest) -> void:
	var brood := nest.brood
	var k := brood.index_of(sim.scratch_i[i]) if int(sim.scratch_f1[i]) >> 2 != Task.NONE else -1
	if k >= 0:
		if brood.carrier[k] == i:
			brood.put_down(k, sim.pos[i], nest)
		if brood.claimed[k] == i:
			brood.claimed[k] = -1
	var item := sim.item_of(i)
	if item != null and item.type_id == "gongylidia":
		nest.return_fungus(sim.pos[i], item.mass)
		sim.carried[i] = -1
		item.carrier = -1
		sim.destroy_item(item.id)
	_clear(sim, i)

static func has_task(sim: Simulation, i: int) -> bool:
	return int(sim.scratch_f1[i]) >> 2 != Task.NONE

## Claims the most urgent unclaimed task (nearest first among equals).
static func _pick(sim: Simulation, i: int, nest: FungusNest, only_chamber: int) -> bool:
	var brood := nest.brood
	var at := sim.pos[i]
	var best := -1
	var best_task := Task.NONE
	var best_rank := 0
	var best_d := INF
	var can_feed := nest.fungus > nest.reserve()
	for k in brood.count():
		if brood.claimed[k] >= 0 or brood.carrier[k] >= 0:
			continue
		if only_chamber >= 0 and nest.chambers_layout.chamber_at(brood.pos[k]) != only_chamber:
			continue
		var task := Task.NONE
		var rank := 0
		if brood.callow_ready(k):
			task = Task.FREE
			rank = 6
		elif brood.pile[k] == Pile.QUEEN:
			task = Task.CARRY
			rank = 5
		elif brood.dirt[k] >= FILTHY:
			# Nearly too dirty to develop: nothing else helps it until groomed.
			task = Task.GROOM
			rank = 4
		elif brood.stage[k] == Stage.LARVA and brood.hunger[k] >= HUNGRY and can_feed:
			task = Task.FEED
			rank = 3
		elif not brood.is_home(k, nest):
			task = Task.CARRY
			rank = 2
		elif brood.dirt[k] >= DIRTY:
			task = Task.GROOM
			rank = 1
		else:
			continue
		var d := at.distance_squared_to(brood.pos[k])
		if rank > best_rank or (rank == best_rank and d < best_d):
			best = k
			best_task = task
			best_rank = rank
			best_d = d
	if best < 0:
		return false
	brood.claimed[best] = i
	sim.scratch_i[i] = brood.id[best]
	_set_task(sim, i, best_task, 0)
	if best_task == Task.FEED:
		sim.target[i] = nest.harvest_point(sim, brood.pos[best])
	return true

static func _set_task(sim: Simulation, i: int, task: int, step: int) -> void:
	sim.scratch_f1[i] = float(task * 4 + step)
	sim.scratch_f0[i] = 0.0

static func _clear(sim: Simulation, i: int) -> void:
	sim.scratch_f1[i] = 0.0
	sim.scratch_f0[i] = 0.0
	sim.scratch_i[i] = -1

static func _finish(sim: Simulation, i: int, k: int) -> void:
	nest_brood_release(sim, i, k)
	_clear(sim, i)

static func nest_brood_release(sim: Simulation, i: int, k: int) -> void:
	var nest := sim.colonies[sim.colony_id[i]].nest as FungusNest
	if nest.brood.claimed[k] == i:
		nest.brood.claimed[k] = -1

## Walks toward `goal` in the nest; true once within `reach`.
static func _walk(sim: Simulation, i: int, nest: FungusNest, goal: Vector2, move_speed: float, dt: float, reach: float) -> bool:
	return Travel.go(sim, i, nest.underground_layer, goal, nest.field_toward(goal), move_speed, dt, reach,
			nest.direct_range(goal) * 0.9)

## A tick of handling something at `at`: face it and work the jaws.
static func _work(sim: Simulation, i: int, dt: float, at: Vector2) -> void:
	sim.scratch_f0[i] += dt
	var aim := (at - sim.pos[i]).angle() + sin(sim.scratch_f0[i] * 9.0) * 0.2
	sim.heading[i] = lerp_angle(sim.heading[i], aim, minf(1.0, dt * 8.0))
	sim.anim_phase[i] += dt * 0.8
