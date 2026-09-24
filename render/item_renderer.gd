class_name ItemRenderer
extends Node2D
## Draws items. Two layers are used: the ground layer (below the ants) draws
## items lying on the ground (debris, dropped items) with a contact shadow;
## the carried layer (above the ants) draws items held in front of their
## carrier's head, rotated with it, with a larger drop shadow since they're
## raised. Procedural items are circles; items with a shape image are drawn
## as that image.

## World-space shadow offsets: carried items are raised, so theirs falls further.
const CARRIED_SHADOW_OFFSET := Vector2(2.0, 3.5)
const GROUND_SHADOW_OFFSET := Vector2(0.8, 1.3)
const SHADOW := Color(0, 0, 0, 0.3)

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
## True: draw items on the ground; false: draw carried items.
var ground_layer: bool = false
## Layer whose items are drawn (carried items: their carrier's layer).
var layer: int = 0
var _textures: Dictionary[int, ImageTexture] = {}
var _drawn_version: int = -1

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	# Carried items move every frame; items on the ground only change when the
	# simulation's item set does.
	if not ground_layer or sim.items_version != _drawn_version:
		_drawn_version = sim.items_version
		queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	for id: int in sim.items:
		var item: Item = sim.items[id]
		var carried := item.carrier >= 0
		if carried == ground_layer or (sim.layer[item.carrier] if carried else item.layer) != layer:
			continue
		var at := item.position
		var rot := item.rotation
		if carried:
			var i := item.carrier
			rot = lerp_angle(sim.prev_heading[i], sim.shown_heading[i], alpha)
			at = sim.prev_pos[i].lerp(sim.shown_pos[i], alpha) + Vector2.from_angle(rot) * sim.caste_of(i).size * Item.HOLD_OFFSET
		var shadow := CARRIED_SHADOW_OFFSET if carried else GROUND_SHADOW_OFFSET
		if item.shape != null:
			var tex: ImageTexture = _textures.get(id)
			if tex == null:
				tex = ImageTexture.create_from_image(item.shape)
				_textures[id] = tex
			var size := Vector2(item.shape.get_size()) * item.pixel_size
			draw_set_transform(at + shadow, rot)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false, SHADOW)
			draw_set_transform(at, rot)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_circle(at + shadow, item.radius, SHADOW)
			draw_circle(at, item.radius, item.color)
	# Forget textures of destroyed items.
	for id: int in _textures.keys():
		if not sim.items.has(id):
			_textures.erase(id)
