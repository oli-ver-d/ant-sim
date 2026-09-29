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
var _has_wings: bool = false

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	# Carried items move every frame; items on the ground only change when the
	# simulation's item set does.
	if not ground_layer or sim.items_version != _drawn_version:
		_drawn_version = sim.items_version
		queue_redraw()
	# Shed wings fade as they decay.
	elif _has_wings and Engine.get_process_frames() % 30 == 0:
		queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	_has_wings = false
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
		if item is Corpse:
			_draw_corpse(item as Corpse, at, shadow)
			continue
		elif item is Wing:
			_has_wings = true
			_draw_wing(item as Wing, at, rot)
			continue
		elif item.shape != null:
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
	draw_set_transform(Vector2.ZERO)
	# Forget textures of destroyed items.
	for id: int in _textures.keys():
		if not sim.items.has(id):
			_textures.erase(id)

## A shed pair of wings, lying flat (fore wing over hind wing, a little
## apart), fading over the last third of its time (Wing.gone_at).
func _draw_wing(w: Wing, at: Vector2, rot: float) -> void:
	var left := (w.gone_at - sim.time()) / maxf(1.0, w.gone_at - w.shed_at)
	var fade := clampf(left * 3.0, 0.0, 1.0)
	var c := SHADOW
	c.a *= 0.35 * fade
	draw_set_transform(at + GROUND_SHADOW_OFFSET * 0.5 + Vector2.from_angle(rot) * w.length * 0.5, rot,
			Vector2(w.length * 0.5, w.length * 0.16))
	draw_circle(Vector2.ZERO, 1.0, c)
	draw_set_transform(Vector2.ZERO)
	WingLook.draw_pair(self, at, rot + w.side * 0.12, rot - w.side * 0.1, w.length, -w.side, w.tint, fade)

## A dead worker or larva, drawn with its refuse kind's look (as it will lie
## on the midden, see MiddenRenderer), in its caste's colour.
func _draw_corpse(corpse: Corpse, at: Vector2, shadow: Vector2) -> void:
	var look := RefuseLook.atlas_for(sim.registry, sim.registry.refuse_kind_for(corpse.type_id))
	var tint := Color.WHITE
	var radius := corpse.radius
	if look[1] and corpse.caste_id >= 0 and corpse.colony_id >= 0:
		var def := sim.colonies[corpse.colony_id].species.castes[corpse.caste_id]
		tint = RefuseLook.corpse_tint(def.color)
		radius = def.size * 0.45
	var side := radius / RefuseLook.BODY
	var cell := float(RefuseLook.PX)
	var src := Rect2((corpse.id % RefuseLook.VARIANTS) * cell, 0, cell, cell)
	var rect := Rect2(-side * 0.5, -side * 0.5, side, side)
	draw_set_transform(at + shadow * 0.6)
	draw_texture_rect_region(look[0], rect, src, SHADOW)
	draw_set_transform(at)
	draw_texture_rect_region(look[0], rect, src, tint)
