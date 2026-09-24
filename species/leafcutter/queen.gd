class_name QueenBehaviour
extends Behaviour
## The queen: stays at her spot in the royal chamber (FungusNest.queen_spot),
## her head into her niche, shifting slowly about it while she lays (LeafcutterBrood lays each egg at
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
	# Rest by her spot, head into her niche (so her abdomen, where she lays,
	# points out into the chamber), shifting and turning a little now and then.
	var spot := nest.queen_spot()
	var drift := Vector2.from_angle(sim.time() * 0.05 + i) * 1.5
	if sim.pos[i].distance_to(spot + drift) > 2.5:
		Steering.move_to(sim, i, spot + drift, sim.speed[i] * 0.4, dt)
	else:
		var facing := nest.queen_heading() + sin(sim.time() * 0.07 + i) * 0.35
		sim.heading[i] = lerp_angle(sim.heading[i], facing, minf(1.0, dt * 0.8))
	return ""
