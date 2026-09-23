class_name Item
extends RefCounted
## Something an ant can carry: a food fragment, a seed, a piece of debris...
## Items are owned by the Simulation (sim.items) and referenced by id from the
## ant arrays. Renderers draw carried items on top of their carrier.

## How far ahead of the carrier's centre a carried item is held, in carrier
## body lengths. Shared by the renderer and by rider placement.
const HOLD_OFFSET := 0.4

var id: int = -1
var type_id: String = ""
var mass: float = 1.0
## Ant index carrying this item, or -1 when lying on the ground.
var carrier: int = -1
## World position / rotation while on the ground (carried items follow the carrier).
var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
## FoodSource id this came from, or -1 (e.g. debris).
var source_id: int = -1

## Ant that has claimed this item (e.g. is on its way to pick it up), or -1.
var reserved_by: int = -1

## Ground clutter: while lying on the ground, ants crossing cells within
## `footprint` of it are slowed (see SimConfig.clutter_slowdown).
var obstructs: bool = false
var footprint: float = 0.0

## Visual: either a procedural blob (color + radius) or a shape image whose
## pixels are drawn centred on the item, `pixel_size` world units per pixel.
var color: Color = Color(0.8, 0.7, 0.4)
var radius: float = 2.0
var shape: Image = null
var pixel_size: float = 1.0

## Ants riding on this item (generic hitchhiking mechanism), and where each
## sits in the item's frame (x along the carrier's heading), in world units.
var riders: PackedInt32Array = []
var rider_offsets: PackedVector2Array = []
