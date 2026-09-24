class_name SplitLayout
extends Control
## Split-screen layout of the 1080x1920 frame: the world (the surface) in a
## SubViewport on one part, and a colony's nest full width on the other, so
## the nest reads as continuing underground below the surface.
##
## Scenario: "render": {"layout": {"mode": "split", "colony": 0,
##                                 "surface": "top", "ratio": 0.5}}
## ratio is the surface's share of the frame height; "surface": "bottom" puts
## it below. "mode": "nest" shows only the nest, full screen.
##
## The nest part is the nest's underground layer (NestType.underground_layer)
## in a second SubViewport (nest_viewport), where ScenarioPlayer puts a
## WorldView of that layer and its own CameraDirector (camera keyframes
## "nest"). Nests without an underground layer get no layout (create()
## returns null) and the scenario plays full screen.
##
## The world's WorldView and CameraDirector are moved into surface_viewport by
## ScenarioPlayer, so camera keyframes, clamping and follow work against the
## surface part's size. When the nest names an ant in NestType.highlight_ant
## (e.g. a worker that has just come out), the layout rings it on the surface
## for a moment.

const FRAME := Vector2(1080, 1920)
## Height of the seam drawn where the two parts meet.
const SEAM := 5.0
const SEAM_COLOR := Color(0.06, 0.04, 0.03)
## Seconds a highlighted ant stays ringed.
const HIGHLIGHT_TIME := 3.0

var surface_viewport: SubViewport
## The underground layer's viewport.
var nest_viewport: SubViewport
var surface_rect: Rect2
var underground_rect: Rect2
## The nest part: the container of nest_viewport.
var underground: SubViewportContainer
var nest: NestType
var sim: Simulation
## "split" or "nest" (the nest full screen); see set_mode().
var mode: String = "split"

var _container: SubViewportContainer
var _seam: Control
var _ring: Control
var _ring_ant: int = -1
var _ring_age: float = INF
var _split_surface: Rect2
var _split_under: Rect2
## The nest's readout (NestType.stats_lines) over the nest's view.
var _stats: Control

## Builds the layout for spec's colony, or returns null if its nest has no
## underground layer.
static func create(simulation: Simulation, spec: Dictionary) -> SplitLayout:
	var ratio := clampf(float(spec.get("ratio", 0.5)), 0.2, 0.8)
	var surface_h := roundf(FRAME.y * ratio)
	var on_top := str(spec.get("surface", "top")) != "bottom"
	var surface := Rect2(0, 0 if on_top else FRAME.y - surface_h, FRAME.x, surface_h)
	var below := Rect2(0, surface_h if on_top else 0, FRAME.x, FRAME.y - surface_h)
	var colony_id := int(spec.get("colony", 0))
	if colony_id < 0 or colony_id >= simulation.colonies.size():
		return null
	var nest := simulation.colonies[colony_id].nest
	if nest.underground_layer < 0:
		return null
	var layout := SplitLayout.new()
	var view := SubViewportContainer.new()
	view.position = below.position
	view.size = below.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.nest_viewport = SubViewport.new()
	layout.nest_viewport.size = Vector2i(below.size)
	layout.nest_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layout.nest_viewport.handle_input_locally = false
	view.add_child(layout.nest_viewport)
	layout.sim = simulation
	layout.nest = nest
	layout.surface_rect = surface
	layout.underground_rect = below
	layout._split_surface = surface
	layout._split_under = below
	layout.underground = view
	layout._build(on_top)
	return layout

func _build(surface_on_top: bool) -> void:
	size = FRAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container = SubViewportContainer.new()
	_container.position = surface_rect.position
	_container.size = surface_rect.size
	# Input is handled by the scene (see ScenarioPlayer.screen_to_world).
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_viewport = SubViewport.new()
	surface_viewport.size = Vector2i(surface_rect.size)
	surface_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface_viewport.handle_input_locally = false
	_container.add_child(surface_viewport)
	add_child(_container)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.position = surface_rect.position
	_ring.size = surface_rect.size
	_ring.clip_contents = true
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	add_child(underground)
	_seam = Control.new()
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seam.position = Vector2(0, (surface_rect.end.y if surface_on_top else underground_rect.end.y) - SEAM * 0.5)
	_seam.size = Vector2(FRAME.x, SEAM)
	_seam.draw.connect(_draw_seam)
	add_child(_seam)
	_stats = Control.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.draw.connect(_draw_stats)
	add_child(_stats)

## "split": surface and nest; "nest": the nest full screen.
func set_mode(new_mode: String) -> void:
	mode = new_mode
	var full := mode == "nest"
	surface_rect = Rect2() if full else _split_surface
	underground_rect = Rect2(Vector2.ZERO, FRAME) if full else _split_under
	_container.visible = not full
	surface_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if full else SubViewport.UPDATE_ALWAYS
	_ring.visible = not full
	_seam.visible = not full
	underground.position = underground_rect.position
	underground.size = underground_rect.size
	nest_viewport.size = Vector2i(underground_rect.size)

func _process(delta: float) -> void:
	if not visible:
		return
	if nest.highlight_ant != _ring_ant:
		_ring_ant = nest.highlight_ant
		_ring_age = 0.0
	_ring_age += delta
	_ring.queue_redraw()
	_stats.queue_redraw()

## A soft ring around the highlighted ant, fading out.
func _draw_ring() -> void:
	if _ring_ant < 0 or _ring_age > HIGHLIGHT_TIME or sim.alive[_ring_ant] == 0 or sim.layer[_ring_ant] != 0:
		return
	var at := surface_viewport.canvas_transform * sim.shown_pos[_ring_ant]
	var zoom := surface_viewport.canvas_transform.get_scale().x
	var a := clampf(_ring_age / 0.3, 0.0, 1.0) * clampf((HIGHLIGHT_TIME - _ring_age) / 0.8, 0.0, 1.0)
	var r := (14.0 + 3.0 * sin(_ring_age * 6.0)) * zoom
	_ring.draw_arc(at, r + 3.0, 0.0, TAU, 48, Color(0, 0, 0, 0.35 * a), 4.0, true)
	_ring.draw_arc(at, r, 0.0, TAU, 48, Color(1.0, 0.93, 0.7, 0.9 * a), 3.0, true)

func _draw_seam() -> void:
	# A dark band with a faint light edge on the surface side.
	_seam.draw_rect(Rect2(Vector2.ZERO, _seam.size), SEAM_COLOR)
	_seam.draw_rect(Rect2(0, 0, _seam.size.x, 1.0), Color(1, 1, 1, 0.12))

## True if a screen point (frame pixels) is on the surface part.
func is_on_surface(screen: Vector2) -> bool:
	return surface_rect.has_point(screen)

## World position under a screen point (frame pixels) on the surface part.
func screen_to_world(screen: Vector2) -> Vector2:
	return surface_viewport.canvas_transform.affine_inverse() * (screen - surface_rect.position)

## Position on the nest's layer under a screen point (frame pixels).
func screen_to_nest(screen: Vector2) -> Vector2:
	return nest_viewport.canvas_transform.affine_inverse() * (screen - underground_rect.position)

## The nest's readout, top left of the nest part inside the TikTok/Reels
## safe area (see Overlays.SafeZones).
func _draw_stats() -> void:
	var lines := nest.stats_lines(sim)
	if lines.is_empty():
		return
	var font := ThemeDB.fallback_font
	var at := Vector2(40, maxf(underground_rect.position.y, Overlays.SafeZones.TOP) + 24)
	var sizes: PackedInt32Array = [46, 28]
	for n in lines.size():
		var fs := sizes[mini(n, 1)]
		at.y += fs
		_stats.draw_string_outline(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.05, 0.03, 0.02, 0.8))
		_stats.draw_string(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9, 0.95))
		at.y += 10
