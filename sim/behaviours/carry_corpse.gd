class_name CarryCorpseBehaviour
extends Behaviour
## Take a dead nestmate (or dead larva) out to a midden: walk to the corpse,
## pick it up, carry it up to the surface and drop it on a midden
## (NestType.refuse_target / drop_refuse), then go back to the state the ant
## was sent from. Ants are sent by their nest (NestType.update_corpses),
## which sets the scratch slots after entering this state.
##
## scratch_i: the corpse's item id
## scratch_f1: state index to go back to
## scratch_f0: 0 on the way to the corpse, 1 carrying it, 2 drop point
##             chosen (in target)

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = 0.0

func exit(sim: Simulation, i: int) -> void:
	var item: Item = sim.items.get(sim.scratch_i[i])
	if item != null and item.reserved_by == i:
		item.reserved_by = -1

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var nest := colony.nest
	var back := sim.behaviour_ids[int(sim.scratch_f1[i])]
	var item: Item = sim.items.get(sim.scratch_i[i])
	if sim.scratch_f0[i] == 0.0:
		if item == null or item.carrier >= 0 or sim.carried[i] >= 0:
			return back
		if nest.walk_to(sim, i, item.layer, item.position, sim.speed[i], dt, 3.0):
			sim.pick_up(i, item)
			item.reserved_by = -1
			nest.corpses_taken += 1
			sim.scratch_f0[i] = 1.0
		return ""
	if item == null or item.carrier != i:
		return back
	var move_speed := sim.speed[i] / (1.0 + item.mass * colony.carry_mass_slowdown)
	if sim.layer[i] != 0:
		Travel.go(sim, i, 0, nest.dump_position(), -1, move_speed, dt)
		return ""
	if sim.scratch_f0[i] == 1.0:
		sim.target[i] = nest.refuse_target(sim, sim.rng.randf(), sim.rng.randf())
		sim.scratch_f0[i] = 2.0
	if Travel.go(sim, i, 0, sim.target[i], -1, move_speed, dt, 4.0):
		var dropped := sim.drop_item(i)
		nest.drop_refuse(sim, dropped, sim.target[i])
		sim.destroy_item(dropped.id)
		return back
	return ""
