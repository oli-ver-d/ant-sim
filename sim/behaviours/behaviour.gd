class_name Behaviour
extends RefCounted
## Base class for behaviour states. One shared instance per state id lives in
## the Registry; all per-ant state is kept in the Simulation's packed arrays,
## so behaviours must never store per-ant data on themselves.
##
## Transitions happen only through tick()'s return value.

## Called once when an ant switches into this state.
func enter(_sim: RefCounted, _ant: int) -> void:
	pass

## Advance one ant by dt seconds. Return the next state id, or "" to stay.
func tick(_sim: RefCounted, _ant: int, _dt: float) -> String:
	return ""

## Called once when an ant leaves this state (before the next state's enter()).
func exit(_sim: RefCounted, _ant: int) -> void:
	pass
