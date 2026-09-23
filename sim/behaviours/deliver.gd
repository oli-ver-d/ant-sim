class_name DeliverBehaviour
extends Behaviour
## At the nest: hand the carried item to the nest, turn around, and go back
## out via `next`.
##
## params: next ("explore")

func tick(sim: Simulation, i: int, _dt: float) -> String:
	sim.deliver_item(i)
	sim.source_age[i] = 0.0
	sim.heading[i] = wrapf(sim.heading[i] + PI, -PI, PI)
	return sim.state_params(i).get("next", "explore")
