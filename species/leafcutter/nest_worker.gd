class_name NestWorker
extends RefCounted
## A render-only worker in NestLifeView: walks a path through the cutaway
## (chamber floors, walls, tunnels) and does one task at a time for the
## brood or the garden. Nothing here touches the simulation.

enum Task { IDLE, MOVE, FEED, GROOM, FREE, CARRY_LEAF }
## What it holds in its mandibles.
enum Carry { NONE, BROOD, FUNGUS, LEAF }

## Seconds for the facing direction to follow a turn.
const TURN_TIME := 0.08

var pos: Vector2
## Smoothed facing direction.
var dir: Vector2 = Vector2.RIGHT
var path: PackedVector2Array = []
var path_i: int = 0
## Pixels per second at real time.
var speed: float = 50.0
var length: float = 12.0
var color: Color
## Head, thorax, gaster length and height scales (see SideAntRenderer.add).
var look: Vector4 = Vector4.ONE
var phase: float = 0.0
## Chamber it's in or heading for (-1 = the surface).
var chamber: int = 0
var is_carrier: bool = false

var task: Task = Task.IDLE
## Brood item the task is about, or -1.
var brood_id: int = -1
var step: int = 0
## Seconds left to stay put (grooming, feeding, resting).
var wait: float = 0.0
var carry: Carry = Carry.NONE
## Seed for the look of what it carries.
var carry_seed: int = 0
## True while it licks or tugs at something (head bobbing).
var working: bool = false

func go(route: PackedVector2Array, to_chamber: int) -> void:
	path = route
	path_i = 0
	chamber = to_chamber

func walking() -> bool:
	return path_i < path.size()

## Walks along the path; `speedup` makes ants hurry in timelapse.
func move(delta: float, speedup: float) -> void:
	if wait > 0.0:
		wait -= delta * speedup
	var budget := speed * speedup * delta
	while budget > 0.0 and path_i < path.size():
		var to := path[path_i]
		var d := to - pos
		var dist := d.length()
		if dist <= budget:
			pos = to
			budget -= dist
			path_i += 1
			phase += dist / length * 2.4
		else:
			pos += d / dist * budget
			phase += budget / length * 2.4
			budget = 0.0
		if dist > 0.5:
			dir = dir.lerp(d / dist, 1.0 - exp(-delta / TURN_TIME)).normalized()
	if working:
		# Licking or tugging: small quick leg shuffles.
		phase += delta * 3.0

## Which way its feet grip (set by the view: down on floors, outward on walls).
var ground: Vector2 = Vector2.DOWN

## Where its mandibles are (for carried things).
func mouth() -> Vector2:
	var d := dir.normalized()
	var down := SideAntRenderer.down_for(d, ground)
	return pos - down * length * 0.2 + d * length * 0.4

## A little bob forward and back while working, added to its drawn position.
func bob(clock: float) -> Vector2:
	return dir * sin(clock * 11.0 + carry_seed) * length * 0.06 if working else Vector2.ZERO
