class_name FoodSource
extends RefCounted
## Base interface for anything ants forage from. Subclasses are registered in
## the Registry by type id and created per placement via Simulation.add_food_source().
## Rendering is hooked up by registering a renderer under "food:<type_id>".

var id: int = -1
var type_id: String = ""
var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
## How far beyond its edge an ant can sense this source.
var sense_radius: float = 60.0
## Total mass handed out so far (for mass-conservation checks).
var taken_mass: float = 0.0
## Incremented whenever the visual state changes, so renderers can redraw lazily.
var version: int = 0

## Called once after creation with scenario parameters.
func setup(_sim: Simulation, params: Dictionary) -> void:
	sense_radius = params.get("sense_radius", sense_radius)

## True if an ant of this colony at pos notices the source.
func is_sensed_at(pos: Vector2, _colony: Colony) -> bool:
	return pos.distance_to(nearest_access_point(pos)) <= sense_radius

## Distance from `position` beyond which is_sensed_at() is always false, with
## a little to spare (lets callers skip sources quickly). INF if unknown.
func sense_bound() -> float:
	return INF

## Closest point an ant can stand at to take from the source.
func nearest_access_point(_pos: Vector2) -> Vector2:
	return position

## Removes a portion for the ant and returns it as an Item (already registered
## with the simulation), or null if nothing can be taken.
func take(_sim: Simulation, _ant: int) -> Item:
	return null

func is_depleted() -> bool:
	return true

## Mass not yet taken.
func remaining_mass() -> float:
	return 0.0
