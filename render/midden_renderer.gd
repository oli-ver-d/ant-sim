class_name MiddenRenderer
extends Node2D
## Draws a nest's middens (NestType.middens) on the surface, under the nest:
## for each, the ground it has stained and the mound its deposits make
## (midden.gdshader, from a small data texture), then every deposit lying on
## it as a sprite from its kind's RefuseLook ("refuse:<kind>" in the
## Registry), sized by the mass it has left, aged by refuse.gdshader, tinted
## with the caste colour for dead workers. So an old midden is a dark stain
## with a fresh layer of what was last thrown out on top.
##
## Deposits are drawn in chunks by id (CHUNK consecutive ids, each chunk its
## own canvas item): a chunk is redrawn only when a deposit in it arrives or
## is merged into the stain, or, one chunk a frame, when the ageing it shows
## is AGE_STEP seconds old; so a big midden costs little to keep up to date.

const CHUNK := 48
## Sim seconds between redraws of a chunk for ageing, and of the ground.
const AGE_STEP := 20.0
const GROUND_STEP := 5.0
## Stain mass and deposit mass per cell giving about 63% of full darkness /
## height in the data texture.
const STAIN_FULL := 0.35
const HEIGHT_FULL := 0.6
## Frames between wetness checks.
const WET_EVERY := 15

var sim: Simulation
var nest: NestType
var _views: Array[View] = []
var _drawn_middens: int = -1
var _deposit_material: ShaderMaterial
var _frame: int = 0
## Every midden's ground, under all the deposits.
var _grounds: Node2D

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as NestType
	_deposit_material = ShaderMaterial.new()
	_deposit_material.shader = preload("res://render/refuse.gdshader")
	_grounds = Node2D.new()
	add_child(_grounds)

func _process(_delta: float) -> void:
	if nest.middens_version != _drawn_middens:
		_drawn_middens = nest.middens_version
		while _views.size() < nest.middens.size():
			var view := View.new()
			view.setup(self, nest.middens[_views.size()])
			_views.append(view)
			add_child(view)
	var now := sim.time()
	_frame += 1
	if _frame % WET_EVERY == 0 and not sim.rain.is_empty():
		for view in _views:
			view.set_wet(RainRenderer.wetness_at(sim, view.midden.position, now))
	var aged := false
	for view in _views:
		aged = view.refresh(now, not aged) or aged

## The atlas and tint flag of a kind's look (see RefuseLook.atlas_for).
func look(kind: String) -> Array:
	return RefuseLook.atlas_for(sim.registry, kind)

## World radius a deposit of refuse kind `kind` with `mass` dropped and
## `left` of it remaining is drawn at; `caste` for a dead worker (-1 none).
func deposit_radius(kind: String, mass: float, left: float, caste: int) -> float:
	if caste >= 0:
		var castes := sim.colonies[nest.colony_id].species.castes
		if caste < castes.size():
			# A dead worker keeps its size while it dries, then shrivels a little.
			return castes[caste].size * 0.45 * (0.75 + 0.25 * sqrt(left))
	var k: RefuseKind = sim.registry.refuse_kinds.get(kind)
	var r := k.radius_of(mass) if k != null else 4.0 * sqrt(mass)
	return maxf(r * (0.3 + 0.7 * sqrt(left)), 0.8)

## The colour a deposit's sprite is multiplied by (see refuse.gdshader).
func deposit_tint(tinted: bool, caste: int) -> Color:
	if not tinted or caste < 0:
		return Color.WHITE if not tinted else Color(0.3, 0.2, 0.14)
	var castes := sim.colonies[nest.colony_id].species.castes
	return RefuseLook.corpse_tint(castes[caste].color) if caste < castes.size() else Color(0.3, 0.2, 0.14)

## The data texture for midden `m` at sim time `now`: r = stain, g = height of
## the deposits (see midden.gdshader), one texel per stain cell.
static func ground_data(m: Midden, now: float, registry: Registry) -> Image:
	var n := Midden.STAIN_SIZE
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var origin := m.stain_origin()
	for d in m.count():
		var c := ((m.dep_pos[d] - origin) / Midden.STAIN_CELL).floor()
		heights[clampi(int(c.y), 0, n - 1) * n + clampi(int(c.x), 0, n - 1)] += m.mass_left(d, now, registry)
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for i in n * n:
		data[i * 4] = int(255.0 * (1.0 - exp(-m.stain[i] / STAIN_FULL)))
		data[i * 4 + 1] = int(255.0 * (1.0 - exp(-heights[i] / HEIGHT_FULL)))
		data[i * 4 + 3] = 255
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)

## One midden: its ground and its deposit chunks.
class View extends Node2D:
	var owner_renderer: MiddenRenderer
	var midden: Midden
	var ground: Node2D
	var ground_material: ShaderMaterial
	var ground_texture: ImageTexture
	var chunks: Dictionary[int, Chunk] = {}
	var drawn_version: int = -1
	var ground_at: float = -INF
	var wet: float = 0.0

	func setup(renderer: MiddenRenderer, m: Midden) -> void:
		owner_renderer = renderer
		midden = m
		ground = Node2D.new()
		ground_material = ShaderMaterial.new()
		ground_material.shader = preload("res://render/midden.gdshader")
		ground_material.set_shader_parameter("origin", m.stain_origin())
		ground_material.set_shader_parameter("span", Midden.STAIN_CELL * Midden.STAIN_SIZE)
		ground.material = ground_material
		ground.draw.connect(_draw_ground)
		renderer._grounds.add_child(ground)

	func set_wet(w: float) -> void:
		if absf(w - wet) < 0.02 and not (w == 0.0 and wet > 0.0):
			return
		wet = w
		ground_material.set_shader_parameter("wet", wet)
		for chunk: Chunk in chunks.values():
			(chunk.material as ShaderMaterial).set_shader_parameter("wet", wet)

	## Brings the drawing up to date; may redraw one chunk for ageing if
	## `may_age`. True if it did.
	func refresh(now: float, may_age: bool) -> bool:
		var changed := midden.version != drawn_version
		if changed or now - ground_at >= GROUND_STEP:
			ground_at = now
			var img := MiddenRenderer.ground_data(midden, now, owner_renderer.sim.registry)
			if ground_texture == null:
				ground_texture = ImageTexture.create_from_image(img)
				ground_material.set_shader_parameter("data", ground_texture)
				ground.queue_redraw()
			else:
				ground_texture.update(img)
		if changed:
			drawn_version = midden.version
			_sync_chunks(now)
		if not may_age:
			return false
		for chunk: Chunk in chunks.values():
			if now - chunk.drawn_at >= AGE_STEP:
				chunk.drawn_at = now
				chunk.queue_redraw()
				return true
		return false

	## Makes a chunk for every id range with deposits in it, frees emptied
	## ones and redraws those whose deposits changed.
	func _sync_chunks(now: float) -> void:
		var counts: Dictionary[int, int] = {}
		for d in midden.count():
			var c := midden.dep_id[d] / CHUNK
			counts[c] = counts.get(c, 0) + 1
		for c: int in chunks.keys():
			if not counts.has(c):
				chunks[c].queue_free()
				chunks.erase(c)
		for c: int in counts:
			var chunk: Chunk = chunks.get(c)
			if chunk == null:
				chunk = Chunk.new()
				chunk.view = self
				chunk.first_id = c * CHUNK
				chunk.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				chunk.material = owner_renderer._deposit_material.duplicate()
				(chunk.material as ShaderMaterial).set_shader_parameter("wet", wet)
				chunks[c] = chunk
				add_child(chunk)
			if counts[c] != chunk.count or c == midden.dep_id[midden.count() - 1] / CHUNK:
				chunk.count = counts[c]
				chunk.drawn_at = now
				chunk.queue_redraw()

	func _draw_ground() -> void:
		var span := Midden.STAIN_CELL * Midden.STAIN_SIZE
		ground.draw_texture_rect(ground_texture, Rect2(midden.stain_origin(), Vector2(span, span)), false)

## Deposits with ids first_id .. first_id + CHUNK - 1 of a midden.
class Chunk extends Node2D:
	var view: View
	var first_id: int = 0
	var count: int = 0
	var drawn_at: float = 0.0

	func _draw() -> void:
		var r := view.owner_renderer
		var m := view.midden
		var now := r.sim.time()
		var reg := r.sim.registry
		var d := m.dep_id.bsearch(first_id)
		var cell := float(RefuseLook.PX)
		while d < m.count() and m.dep_id[d] < first_id + CHUNK:
			var kind := m.kinds[m.dep_kind[d]]
			var look: Array = r.look(kind)
			var left := m.mass_left(d, now, reg)
			var share := left / maxf(m.dep_mass[d], 1e-6)
			var id := m.dep_id[d]
			var variant := (id * 2654435761) % RefuseLook.VARIANTS
			var radius := r.deposit_radius(kind, m.dep_mass[d], share, m.dep_extra[d])
			# Loads differ a little in size even when their mass doesn't.
			var side := radius / RefuseLook.BODY * (0.8 + 0.4 * float((id * 40503) % 97) / 96.0)
			var tint := r.deposit_tint(look[1], m.dep_extra[d])
			# How far it has rotted: 0 fresh, 1 about to merge into the stain.
			tint.a = clampf((1.0 - share) / (1.0 - Midden.MERGE_BELOW), 0.0, 1.0)
			# Not turned: the shadow is cast in the sprite's own frame (the
			# variants lie every which way instead).
			draw_set_transform(m.dep_pos[d])
			draw_texture_rect_region(look[0], Rect2(-side * 0.5, -side * 0.5, side, side),
					Rect2(variant * cell, 0, cell, cell), tint)
			d += 1
		draw_set_transform(Vector2.ZERO)
