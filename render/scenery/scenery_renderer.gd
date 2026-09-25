class_name SceneryRenderer
extends Node2D
## Draws the surface's scenery props. One node per pass: the base pass (the
## parts on the ground: rock and log bodies, plant stems) sits under the ants,
## the canopy pass (plant tops, grass blades) over them.
##
## Props whose type has a painter ("prop:<type>" in the Registry's renderers,
## e.g. RockLook) are baked once by PropBaker when they appear: the base pass
## draws every prop's shadow first, then the bodies, so a shadow never falls
## across a neighbouring rock. Others get placeholder outlines for now.

enum Pass { BASE, CANOPY }

const COLORS := {
	"rock": Color(0.52, 0.5, 0.46),
	"log": Color(0.45, 0.32, 0.2),
	"plant": Color(0.3, 0.55, 0.22),
	"grass": Color(0.45, 0.62, 0.25),
}
const OTHER_COLOR := Color(0.7, 0.4, 0.6)

var sim: Simulation
var draw_pass: Pass = Pass.BASE
var _version: int = -1
## Baked textures per prop id: {"body": Texture2D, "body_rect", "shadow", "shadow_rect"}.
var _baked: Dictionary[int, Dictionary] = {}
var _painters: Dictionary[String, Object] = {}

func bind(simulation: Simulation, pass_kind: Pass = Pass.BASE) -> void:
	sim = simulation
	draw_pass = pass_kind
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(_delta: float) -> void:
	if sim != null and sim.scenery.version != _version:
		_version = sim.scenery.version
		if draw_pass == Pass.BASE:
			_bake_new()
		queue_redraw()

func _bake_new() -> void:
	var live: Dictionary[int, bool] = {}
	for prop in sim.scenery.props:
		live[prop.id] = true
		if _baked.has(prop.id):
			continue
		var painter := _painter(prop.type_id)
		if painter == null:
			continue
		var b := PropBaker.bake(prop, painter, float(sim.world.cell_size), sim.ground)
		if b.is_empty():
			continue
		_baked[prop.id] = {
			"body": ImageTexture.create_from_image(b["body"]), "body_rect": b["body_rect"],
			"shadow": ImageTexture.create_from_image(b["shadow"]), "shadow_rect": b["shadow_rect"],
		}
	for id: int in _baked.keys():
		if not live.has(id):
			_baked.erase(id)

func _painter(type_id: String) -> Object:
	if not _painters.has(type_id):
		var script: Script = sim.registry.renderers.get("prop:" + type_id)
		_painters[type_id] = script.new() if script != null else null
	return _painters[type_id]

func _draw() -> void:
	if sim == null:
		return
	if draw_pass == Pass.BASE:
		for prop in sim.scenery.props:
			if _baked.has(prop.id):
				var b := _baked[prop.id]
				draw_texture_rect(b["shadow"], b["shadow_rect"], false)
	for prop in sim.scenery.props:
		var col: Color = COLORS.get(prop.type_id, OTHER_COLOR)
		if draw_pass == Pass.BASE:
			if _baked.has(prop.id):
				var b := _baked[prop.id]
				draw_texture_rect(b["body"], b["body_rect"], false)
			else:
				_shape(prop.outline, Color(col, 0.85), col.darkened(0.45), 1.5)
		else:
			_shape(prop.canopy, Color(col, 0.18), Color(col.lightened(0.2), 0.7), 1.0)

func _shape(outline: PackedVector2Array, fill: Color, line: Color, line_width: float) -> void:
	if outline.size() < 3:
		return
	# Skip the fill for outlines that don't triangulate (e.g. a sharply bent log).
	if not Geometry2D.triangulate_polygon(outline).is_empty():
		draw_colored_polygon(outline, fill)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, line, line_width, true)
