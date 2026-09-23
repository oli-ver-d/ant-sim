class_name ItemRenderer
extends Node2D
## Draws items: carried ones held in front of the carrier's head and rotated
## with it, others where they lie. Procedural items are circles; items with a
## shape image are drawn as that image.

## How far ahead of the carrier's centre an item is held, in body lengths.
const HOLD_OFFSET := 0.4
## World-space offset of carried items' drop shadow (held items are raised, so
## their shadow falls further than the ant's own).
const SHADOW_OFFSET := Vector2(2.0, 3.5)
const SHADOW := Color(0, 0, 0, 0.3)

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
var _textures: Dictionary[int, ImageTexture] = {}

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	for id: int in sim.items:
		var item: Item = sim.items[id]
		var at := item.position
		var rot := item.rotation
		if item.carrier >= 0:
			var i := item.carrier
			rot = lerp_angle(sim.prev_heading[i], sim.shown_heading[i], alpha)
			at = sim.prev_pos[i].lerp(sim.shown_pos[i], alpha) + Vector2.from_angle(rot) * sim.caste_of(i).size * HOLD_OFFSET
		if item.shape != null:
			var tex: ImageTexture = _textures.get(id)
			if tex == null:
				tex = ImageTexture.create_from_image(item.shape)
				_textures[id] = tex
			var size := Vector2(item.shape.get_size()) * item.pixel_size
			if item.carrier >= 0:
				draw_set_transform(at + SHADOW_OFFSET, rot)
				draw_texture_rect(tex, Rect2(-size * 0.5, size), false, SHADOW)
			draw_set_transform(at, rot)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
			draw_set_transform(Vector2.ZERO)
		else:
			if item.carrier >= 0:
				draw_circle(at + SHADOW_OFFSET, item.radius, SHADOW)
			draw_circle(at, item.radius, item.color)
	# Forget textures of destroyed items.
	for id: int in _textures.keys():
		if not sim.items.has(id):
			_textures.erase(id)
