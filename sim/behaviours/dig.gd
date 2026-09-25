class_name DigBehaviour
extends Behaviour
## Dig for the nest's excavation plan (NestType.excavation_plan(), see
## ExcavationPlan): take an open job, go down to the underground if needed,
## walk to the job's origin and on to its digging face, and bite soil there
## for `dig_time` seconds per bite. Each bite comes out as a spoil pellet to
## carry up (-> `on_spoil`); while the nest has no open entrance the soil is
## pressed into the walls instead and the ant keeps digging. With no job to
## take, or after `give_up_after` seconds without a bite -> `on_idle` (and the
## plan hears of it: a job everyone gives up on is abandoned, see
## ExcavationPlan.report_stall).
##
## params: dig_time (s, 2.5), on_spoil ("carry_spoil"), on_idle ("linger"),
##         speed_factor (1.0), give_up_after (s, 90)
## scratch_i: the job id (its digger count is held while in this state)
## scratch_f0: seconds spent on the current bite
## target: centre of the cell being bitten

func enter(sim: Simulation, i: int) -> void:
	sim.scratch_i[i] = -1
	sim.scratch_f0[i] = 0.0

func exit(sim: Simulation, i: int) -> void:
	_release(sim, i)

func tick(sim: Simulation, i: int, dt: float) -> String:
	var colony := sim.colonies[sim.colony_id[i]]
	var p := colony.params_for(sim.caste_id[i], sim.state[i])
	var nest := colony.nest
	var plan := nest.excavation_plan()
	if plan == null:
		return p.get("on_idle", "linger")
	var job := plan.job_by_id(sim.scratch_i[i])
	if job == null or job.done:
		_release(sim, i)
		job = plan.pick_job()
		if job == null:
			return p.get("on_idle", "linger")
		job.diggers += 1
		sim.scratch_i[i] = job.id
		sim.scratch_f0[i] = 0.0
	if sim.timer[i] > float(p.get("give_up_after", 90.0)):
		# No bite for a long while: tell the plan (a job nobody can dig is abandoned).
		plan.report_stall(job)
		return p.get("on_idle", "linger")

	var move_speed := sim.speed[i] * float(p.get("speed_factor", 1.0))
	if sim.layer[i] != plan.layer:
		Travel.go(sim, i, plan.layer, job.origin, job.nav_field, move_speed, dt)
		return ""
	var at := sim.pos[i]
	var step := plan.face_step(job, at)
	if step == Vector2.INF:
		# Not near the face yet: to the job's origin first.
		Travel.go(sim, i, plan.layer, job.origin, job.nav_field, move_speed, dt, 2.0)
		return ""
	if step != at:
		Steering.move_to(sim, i, step, move_speed, dt)
		sim.scratch_f0[i] = 0.0
		return ""
	# The cell to bite is chosen when a bite starts (a weighted random pick,
	# see ExcavationPlan.bite_cell) and kept while it lasts.
	var cell := plan.world.cell_at(sim.target[i])
	if sim.scratch_f0[i] == 0.0 or not plan.is_job_cell(job, cell) or sim.target[i].distance_squared_to(at) > 4.0 * plan.world.cell_size * plan.world.cell_size:
		cell = plan.bite_cell(job, at, sim.rng)
		sim.scratch_f0[i] = 0.0
		if cell >= 0:
			sim.target[i] = plan.world.cell_center(cell)
	if cell < 0:
		# The face moved on (someone else finished this spot): step toward where it heads.
		Steering.move_to(sim, i, job.face_target, move_speed * 0.5, dt)
		return ""
	# Bite: face the soil, working the head from side to side.
	var biting := sim.scratch_f0[i] + dt
	sim.scratch_f0[i] = biting
	var aim := (plan.world.cell_center(cell) - at).angle() + sin(biting * 17.0) * 0.3
	sim.heading[i] = lerp_angle(sim.heading[i], aim, minf(1.0, dt * 10.0))
	sim.anim_phase[i] += dt * 1.5
	if biting < float(p.get("dig_time", 2.5)):
		return ""
	sim.scratch_f0[i] = 0.0
	var dug := plan.dig_cell(job, cell)
	if dug <= 0.0:
		return ""
	sim.timer[i] = 0.0
	if nest.has_entrance():
		sim.pick_up(i, nest.make_spoil(sim, dug))
		return p.get("on_spoil", "carry_spoil")
	nest.packed_spoil += dug
	return ""

## Gives up the ant's job (and its place among the job's diggers).
func _release(sim: Simulation, i: int) -> void:
	var plan := sim.colonies[sim.colony_id[i]].nest.excavation_plan()
	if plan != null:
		var job := plan.job_by_id(sim.scratch_i[i])
		if job != null:
			job.diggers = maxi(0, job.diggers - 1)
	sim.scratch_i[i] = -1
