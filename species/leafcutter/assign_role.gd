class_name AssignRoleBehaviour
extends Behaviour
## Minims' starting state: each new minim becomes either a hitchhiker (goes
## out to ride fragments home) or a nest-stayer, with probability
## `hitchhiker_fraction` (species tunable). Decided once, on the first tick.
##
## params: hitchhiker ("explore"), stayer ("linger")

func tick(sim: Simulation, i: int, _dt: float) -> String:
	var p := sim.state_params(i)
	var fraction: float = sim.colony_of(i).params.get(&"hitchhiker_fraction", 0.5)
	return p.get("hitchhiker", "explore") if sim.rng.randf() < fraction else p.get("stayer", "linger")
