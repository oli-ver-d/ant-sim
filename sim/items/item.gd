class_name Item
extends RefCounted
## Something an ant can carry: a food fragment, a seed, a piece of debris...
## Items are owned by the Simulation (sim.items) and referenced by id from the
## ant arrays. Renderers draw carried items on top of their carrier.

var id: int = -1
var type_id: String = ""
var mass: float = 1.0
## Ant index carrying this item, or -1 when lying on the ground.
var carrier: int = -1
## World position / rotation while on the ground (carried items follow the carrier).
var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
## FoodSource id this came from, or -1.
var source_id: int = -1

## Visual: either a procedural blob (color + radius) or a shape image whose
## pixels are drawn centred on the item, `pixel_size` world units per pixel.
var color: Color = Color(0.8, 0.7, 0.4)
var radius: float = 2.0
var shape: Image = null
var pixel_size: float = 1.0

## Ants riding on this item (generic hitchhiking mechanism).
var riders: PackedInt32Array = []
