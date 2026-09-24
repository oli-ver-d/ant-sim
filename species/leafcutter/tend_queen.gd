class_name TendQueenBehaviour
extends Behaviour
## The queen's retinue: walk to her and circle her slowly, stopping now and
## then to groom her (FungusNest.queen_groomed_at; a queen left ungroomed
## lays more slowly). After `stint` seconds -> `on_done`.
##
## params: stint (s, 70), on_done ("nest_role")
## scratch_f0: angle around the queen; scratch_f1: grooming timer

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_f0[i] = sim.rng.randf() * TAU
	sim.scratch_f1[i] = 0.0

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest as FungusNest
	if sim.timer[i] > float(p.get("stint", 70.0)):
		return p.get("on_done", "nest_role")
	var q := nest.queen_ant
	if q < 0 or sim.alive[q] == 0:
		return p.get("on_done", "nest_role")
	var queen_at := sim.pos[q]
	var reach := sim.caste_of(q).size * 0.62
	var spot := queen_at + Vector2.from_angle(sim.scratch_f0[i]) * Vector2(reach * 1.25, reach * 0.8).rotated(sim.heading[q])
	if sim.layer[i] != nest.underground_layer or sim.pos[i].distance_to(queen_at) > reach * 2.5:
		Travel.go(sim, i, nest.underground_layer, spot, nest.field_toward(queen_at), sim.speed[i], dt, 2.0,
				nest.direct_range(queen_at) * 0.9)
		return ""
	# Groom a while, then move on round her.
	if sim.scratch_f1[i] > 0.0:
		sim.scratch_f1[i] -= dt
		var aim := (queen_at - sim.pos[i]).angle() + sin(sim.timer[i] * 7.0) * 0.25
		sim.heading[i] = lerp_angle(sim.heading[i], aim, minf(1.0, dt * 6.0))
		sim.anim_phase[i] += dt * 0.6
		nest.queen_groomed_at = sim.time()
		return ""
	if sim.pos[i].distance_to(spot) < 1.5:
		sim.scratch_f1[i] = sim.rng.randf_range(1.5, 3.5)
		sim.scratch_f0[i] += sim.rng.randf_range(0.4, 1.1) * (1.0 if i % 2 == 0 else -1.0)
		return ""
	Steering.move_to(sim, i, spot, sim.speed[i] * 0.5, dt)
	return ""
