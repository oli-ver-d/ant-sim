class_name ItemRenderer
extends Node2D
## Draws items, in one of three passes. GROUND (below the ants) draws items
## lying on the ground (debris, dropped items) with a contact shadow.
## CARRIED_SHADOW (also below the ants) draws the shadows of carried items and
## CARRIED (above the ants) the items themselves, held in front of their
## carrier's head, rotated with it. Carried items are drawn in order of
## Item.carry_height (then id), so one held up high is drawn over one held
## low, and a higher one's shadow falls further. Procedural items are
## circles; items with a shape image are drawn as that image.

enum Pass { GROUND, CARRIED, CARRIED_SHADOW }

## World-space shadow offsets: on the ground, and for an item held at
## carry_height 1 (close to a carrying worker's own drop shadow, ant.gdshader).
## Lower carried items lerp between the two.
const CARRIED_SHADOW_OFFSET := Vector2(1.2, 2.0)
const GROUND_SHADOW_OFFSET := Vector2(0.8, 1.3)
const SHADOW := Color(0, 0, 0, 0.3)

var sim: Simulation
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0
var pass_kind: Pass = Pass.CARRIED
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
	if pass_kind != Pass.GROUND or sim.items_version != _drawn_version:
		_drawn_version = sim.items_version
		queue_redraw()
	# Shed wings fade as they decay.
	elif _has_wings and Engine.get_process_frames() % 30 == 0:
		queue_redraw()

## Carried items in drawing order: by carry height, then by id (stable while
## ids change, so the order doesn't flicker).
static func carried_order(items: Array[Item]) -> Array[Item]:
	var out := items.duplicate()
	out.sort_custom(func(a: Item, b: Item) -> bool:
		return a.id < b.id if a.carry_height == b.carry_height else a.carry_height < b.carry_height)
	return out

## Shadow offset of a carried item held at `height` (Item.carry_height).
static func carried_shadow_offset(height: float) -> Vector2:
	return GROUND_SHADOW_OFFSET.lerp(CARRIED_SHADOW_OFFSET, clampf(height, 0.0, 1.0))

func _draw() -> void:
	if sim == null:
		return
	_has_wings = false
	if pass_kind == Pass.GROUND:
		for id: int in sim.items:
			var item: Item = sim.items[id]
			if item.carrier < 0 and item.layer == layer:
				_draw_item(item, item.position, item.rotation, GROUND_SHADOW_OFFSET, true, true)
	else:
		var carried: Array[Item] = []
		for id: int in sim.items:
			var item: Item = sim.items[id]
			if item.carrier >= 0 and sim.layer[item.carrier] == layer:
				carried.append(item)
		var shadows := pass_kind == Pass.CARRIED_SHADOW
		for item in carried_order(carried):
			var i := item.carrier
			var rot := lerp_angle(sim.prev_heading[i], sim.shown_heading[i], alpha)
			var at := sim.prev_pos[i].lerp(sim.shown_pos[i], alpha) + Vector2.from_angle(rot) * sim.caste_of(i).size * Item.HOLD_OFFSET
			_draw_item(item, at, rot, carried_shadow_offset(item.carry_height), shadows, not shadows)
	draw_set_transform(Vector2.ZERO)
	# Forget textures of destroyed items.
	for id: int in _textures.keys():
		if not sim.items.has(id):
			_textures.erase(id)

func _draw_item(item: Item, at: Vector2, rot: float, shadow: Vector2, with_shadow: bool, with_body: bool) -> void:
	if item is Corpse:
		_draw_corpse(item as Corpse, at, shadow * 0.6 if item.carrier < 0 else shadow, with_shadow, with_body)
	elif item is Wing:
		_has_wings = true
		if with_body:
			_draw_wing(item as Wing, at, rot)
	elif item.shape != null:
		var tex: ImageTexture = _textures.get(item.id)
		if tex == null:
			tex = ImageTexture.create_from_image(item.shape)
			_textures[item.id] = tex
		var size := Vector2(item.shape.get_size()) * item.pixel_size
		if with_shadow:
			draw_set_transform(at + shadow, rot)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false, SHADOW)
		if with_body:
			draw_set_transform(at, rot)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
		draw_set_transform(Vector2.ZERO)
	else:
		if with_shadow:
			draw_circle(at + shadow, item.radius, SHADOW)
		if with_body:
			draw_circle(at, item.radius, item.color)

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
func _draw_corpse(corpse: Corpse, at: Vector2, shadow: Vector2, with_shadow: bool, with_body: bool) -> void:
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
	if with_shadow:
		draw_set_transform(at + shadow)
		draw_texture_rect_region(look[0], rect, src, SHADOW)
	if with_body:
		draw_set_transform(at)
		draw_texture_rect_region(look[0], rect, src, tint)
	draw_set_transform(Vector2.ZERO)
