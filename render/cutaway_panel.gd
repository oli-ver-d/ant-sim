class_name CutawayPanel
extends Control
## An inset panel showing a nest's cutaway view, placed anywhere on screen
## (screen pixels of the 1080x1920 frame). The view itself comes from the
## Registry: the renderer registered as "cutaway:<nest type>" (a Control with
## bind(sim, nest)); nests without one get no panel (see create()).
##
## Scenario: "render": {"cutaway": {"colony": 0, "rect": [x, y, w, h],
##                                   "from": 2.0, "to": 18.0}}
## "from"/"to" are video seconds; the panel fades in and out around them.

const BORDER := 4.0
const FADE := 0.6
const FRAME := Color(0.72, 0.6, 0.45)
const SHADOW := Color(0, 0, 0, 0.45)

var from_time: float = -INF
var to_time: float = INF

## Builds a panel for the colony's nest, or returns null if its nest type has
## no cutaway renderer.
static func create(sim: Simulation, registry: Registry, colony_id: int, rect: Rect2) -> CutawayPanel:
	var view := create_view(sim, registry, colony_id,
			Rect2(Vector2(BORDER, BORDER), rect.size - Vector2(BORDER, BORDER) * 2.0))
	if view == null:
		return null
	var panel := CutawayPanel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)
	return panel

## Builds just the bound cutaway view (no frame) at `rect`, or null if the
## colony's nest type has none. Also used full width by SplitLayout.
static func create_view(sim: Simulation, registry: Registry, colony_id: int, rect: Rect2) -> Control:
	if colony_id < 0 or colony_id >= sim.colonies.size():
		return null
	var nest := sim.colonies[colony_id].nest
	var script: Script = registry.renderers.get("cutaway:" + nest.type_id)
	if script == null:
		return null
	var view: Control = script.new()
	view.position = rect.position
	view.size = rect.size
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.call("bind", sim, nest)
	return view

## Shows the panel according to its from/to times at video time `t`.
func update_visibility(t: float) -> void:
	var a := clampf((t - from_time) / FADE, 0.0, 1.0) * clampf((to_time - t) / FADE, 0.0, 1.0)
	modulate.a = a
	visible = a > 0.0

func _draw() -> void:
	# Drop shadow, then a thin light frame around the view.
	draw_rect(Rect2(Vector2(6, 8), size), SHADOW)
	draw_rect(Rect2(Vector2.ZERO, size), FRAME)
