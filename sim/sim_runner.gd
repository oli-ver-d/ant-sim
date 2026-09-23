class_name SimRunner
extends RefCounted
## Drives a Simulation toward a target time measured in ticks, processing
## partial ticks so the work of one tick is spread over the frames it spans
## (at 30 ticks/s and 60 fps, about half the ants per frame).
##
## Renderers show the last two completed ticks, interpolated by alpha(), so
## what's on screen is one tick behind the simulation in exchange for even
## frame times.

var sim: Simulation
## Target progress in ticks (fractional).
var target: float = 0.0
## If the sim falls further behind than this many ticks (too slow for the
## requested speed), skip ahead instead of trying to catch up forever.
var max_lag_ticks: float = 4.0

func _init(simulation: Simulation) -> void:
	sim = simulation
	target = sim.completed_ticks()

## Current progress in ticks, including the part of the tick in progress.
func progress() -> float:
	return sim.completed_ticks() + sim.tick_fraction()

## Advances the target by `ticks` and does the work needed to reach it.
func advance(ticks: float) -> void:
	target += ticks
	if target - progress() > max_lag_ticks:
		target = progress() + max_lag_ticks
	while progress() < target - 1e-6:
		if not sim.in_tick():
			sim.begin_step()
		var want := target - sim.completed_ticks()
		if want >= 1.0:
			sim.step_ants(sim.capacity)
		else:
			var until := ceili(want * sim.tick_ant_slots())
			var cursor := sim.tick_cursor()
			if not sim.step_ants(maxi(until - cursor, 1)):
				break
		if sim.tick_cursor() >= sim.tick_ant_slots():
			sim.end_step()

## Interpolation factor between the last two completed ticks, in [0, 1].
func alpha() -> float:
	return clampf(target - sim.completed_ticks(), 0.0, 1.0)
