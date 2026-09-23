class_name HitchhikeBehaviour
extends Behaviour
## Riding a leaf fragment home. The core keeps the rider glued to the
## fragment (Simulation._sync_riders) and makes it get off when the fragment
## is delivered or dropped; this state just waits for that.
##
## params: on_dismount ("explore")

func tick(sim: Simulation, i: int, _dt: float) -> String:
	if sim.riding[i] < 0:
		# At the nest (or the fragment was dropped): back to work.
		sim.source_age[i] = 0.0
		return sim.state_params(i).get("on_dismount", "explore")
	return ""

func exit(sim: Simulation, i: int) -> void:
	sim.dismount(i)
