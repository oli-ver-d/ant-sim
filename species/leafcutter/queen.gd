class_name QueenBehaviour
extends Behaviour
## The queen: stays at her spot in the royal chamber (FungusNest.queen_spot),
## shifting slowly about it while she lays (LeafcutterBrood lays each egg at
## the tip of her abdomen). While the colony has no workers yet (a founding
## queen, FungusNest.queen_cares) she tends her brood herself, within the
## royal chamber, at her slow pace.

func exit(sim: Simulation, i: int) -> void:
	BroodCare.abandon(sim, i, sim.colonies[sim.colony_id[i]].nest as FungusNest)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var nest := sim.colonies[sim.colony_id[i]].nest as FungusNest
	if nest.chambers_layout == null:
		return ""
	if nest.queen_cares(sim):
		if BroodCare.tick(sim, i, dt, nest, sim.speed[i], 0):
			return ""
	elif BroodCare.has_task(sim, i):
		BroodCare.abandon(sim, i, nest)
	# Rest by her spot, turning now and then.
	var spot := nest.queen_spot()
	var drift := Vector2.from_angle(sim.time() * 0.05 + i) * 3.0
	if sim.pos[i].distance_to(spot + drift) > 1.5:
		Steering.move_to(sim, i, spot + drift, sim.speed[i] * 0.4, dt)
	return ""
