class_name Portal
extends RefCounted
## A way between two layers, e.g. a nest entrance on the surface (side a)
## and the bottom of its shaft underground (side b). An ant within `radius`
## of one end may enter it (Simulation.enter_portal): it walks into the hole
## for `transit_time` seconds, then comes out at the other end. Renderers fade
## ants out while they go in and back in as they come out (see
## Simulation.portal_fade()).
##
## A closed portal (open == false) can't be used from either side, e.g. a
## founding nest sealed until its workers dig the entrance open.
##
## Each portal has a navigation field toward its side-b end ("portal:<id>"),
## which underground ants follow to find their way out.

var id: int = -1
var layer_a: int = 0
var pos_a: Vector2
var layer_b: int = 1
var pos_b: Vector2
## Distance from an end at which an ant can enter.
var radius: float = 10.0
## Closed: can't be used from either side. Setting it counts in `changes`.
var open: bool = true:
	set(value):
		open = value
		changes += 1
## Incremented whenever any portal opens or closes (the native ant kernel
## caches which nests have an open entrance, see NativeAnts).
static var changes: int = 0
var transit_time: float = 0.5
## Ants that have gone into it so far, from either side. Render only (an
## entrance widens as it is used, see NestType.entrance_sites()); not hashed.
var uses: int = 0
## Nav field id of the "portal:<id>" field on layer b.
var nav_field: int = -1

## The end of this portal on `layer` (side a if the portal loops a layer to itself).
func end_on(layer: int) -> Vector2:
	return pos_a if layer == layer_a else pos_b

## The layer an ant on `layer` comes out on.
func other_layer(layer: int) -> int:
	return layer_b if layer == layer_a else layer_a

func connects(layer: int) -> bool:
	return layer == layer_a or layer == layer_b
