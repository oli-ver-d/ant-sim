class_name SceneryRenderer
extends Node2D
## Draws the surface's scenery props. One node per pass: the base pass (the
## parts on the ground: rock and log bodies, plant stems) sits under the ants,
## the canopy pass (plant tops, grass blades) over them.
##
## Placeholder looks for now: flat fills and outlines per prop type. Redrawn
## only when the scenery changes.

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

func bind(simulation: Simulation, pass_kind: Pass = Pass.BASE) -> void:
	sim = simulation
	draw_pass = pass_kind

func _process(_delta: float) -> void:
	if sim != null and sim.scenery.version != _version:
		_version = sim.scenery.version
		queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	for prop in sim.scenery.props:
		var col: Color = COLORS.get(prop.type_id, OTHER_COLOR)
		if draw_pass == Pass.BASE:
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
