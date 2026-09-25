class_name Prop
extends RefCounted
## One piece of surface scenery (a rock, a log, a plant...), as built by its
## PropType from the scenario's data. Render-side geometry is in world units.
## Nothing here is simulation state: only the claimed `cells` reach the World.

## Unique within its Scenery, in the order props were added.
var id: int = 0
## Registry.scenery_types id, e.g. "rock".
var type_id: String = ""
## Optional name from the scenario, for "remove_scenery" events.
var name: String = ""
var position: Vector2 = Vector2.ZERO
## Radians.
var rotation: float = 0.0
var scale: float = 1.0
## The scenario entry this prop was built from (a copy).
var params: Dictionary = {}
## Seed of the prop's own RandomNumberGenerator (from the scenario seed and id).
var prop_seed: int = 0
## True if its footprint blocks ants (stamped into the World as WALL).
var blocks: bool = false
## Blocking footprint: {} (none), {"shape": "circle", "center": Vector2, "radius": r},
## {"shape": "polygon", "points": PackedVector2Array} or
## {"shape": "polyline", "points": PackedVector2Array, "width": w}.
var footprint: Dictionary = {}
## Outline of the part on the ground, drawn under the ants (base pass).
var outline: PackedVector2Array = []
## Outline of the part over the ants (canopy pass); empty for none.
var canopy: PackedVector2Array = []
## Everything the prop draws, in world units.
var bounds: Rect2 = Rect2()
## Cells claimed in World.prop_mask (see World.add_prop_cells).
var cells: PackedInt32Array = []

## True if `at` is inside the prop's base or canopy outline.
func contains(at: Vector2) -> bool:
	return (outline.size() >= 3 and Geometry2D.is_point_in_polygon(at, outline)) \
			or (canopy.size() >= 3 and Geometry2D.is_point_in_polygon(at, canopy))
