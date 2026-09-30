class_name Profiler
extends RefCounted
## Opt-in timers for the measurement tools (tests/bench.gd --by-state and
## --load-times, tests/frame_probe.gd). Off by default: code calls
##   var t := Profiler.start()
##   ...work...
##   Profiler.stop("key", t)
## and while `on` is false start() returns 0 and stop() returns at once,
## recording nothing. Only put these round code that runs a few times per
## tick or frame (nest updates, renderers, load stages), never per ant:
## per-ant timing has its own separate code path (Simulation, AntKernel).

static var on: bool = false
## Microseconds and calls per key since the last reset().
static var usec: Dictionary[String, int] = {}
static var calls: Dictionary[String, int] = {}

static func start() -> int:
	return Time.get_ticks_usec() if on else 0

static func stop(key: String, t0: int) -> void:
	if not on:
		return
	usec[key] = usec.get(key, 0) + Time.get_ticks_usec() - t0
	calls[key] = calls.get(key, 0) + 1

static func reset() -> void:
	usec.clear()
	calls.clear()

## Keys sorted by time, the largest first.
static func ranked() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(usec.keys())
	keys.sort_custom(func(a: String, b: String) -> bool: return usec[a] > usec[b])
	return keys
