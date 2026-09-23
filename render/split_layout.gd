class_name SplitLayout
extends Control
## Split-screen layout of the 1080x1920 frame: the world (the surface) in a
## SubViewport on one part, and a colony's nest cutaway view full width on the
## other, so the nest reads as continuing underground below the surface.
##
## Scenario: "render": {"layout": {"mode": "split", "colony": 0,
##                                 "surface": "top", "ratio": 0.5}}
## ratio is the surface's share of the frame height; "surface": "bottom" puts
## it below. Optional "view": {"<property>": value} sets properties the
## cutaway view declares. The cutaway is the nest type's "cutaway:<type>"
## renderer (see CutawayPanel.create_view); nests without one get no layout
## (create() returns null) and the scenario plays full screen as usual.
##
## The world's WorldView and CameraDirector are moved into surface_viewport by
## ScenarioPlayer, so camera keyframes, clamping and follow work against the
## surface part's size. The cutaway view may declare these optional
## properties, which the layout keeps up to date every frame:
##   entrance_x: float  screen x (view pixels) of the nest entrance on the
##                      surface, so the view can line its entrance up with it
##   safe_rect: Rect2   the part of the view not covered by TikTok/Reels UI
##                      (Overlays.SafeZones), to keep key action inside
## and it may name an ant (index) for the layout to ring on the surface for
## a moment, e.g. a worker that has just come out of the nest:
##   highlight_ant: int  (-1 = none; ringed each time it changes)

const FRAME := Vector2(1080, 1920)
## Height of the seam drawn where the two parts meet.
const SEAM := 5.0
const SEAM_COLOR := Color(0.06, 0.04, 0.03)
## Seconds a highlighted ant stays ringed.
const HIGHLIGHT_TIME := 3.0

var surface_viewport: SubViewport
var surface_rect: Rect2
var underground_rect: Rect2
var underground: Control
var nest: NestType
var sim: Simulation

var _container: SubViewportContainer
var _seam: Control
var _ring: Control
var _ring_ant: int = -1
var _ring_age: float = INF

## Builds the layout for spec's colony, or returns null if its nest has no
## cutaway view.
static func create(simulation: Simulation, registry: Registry, spec: Dictionary) -> SplitLayout:
	var ratio := clampf(float(spec.get("ratio", 0.5)), 0.2, 0.8)
	var surface_h := roundf(FRAME.y * ratio)
	var on_top := str(spec.get("surface", "top")) != "bottom"
	var surface := Rect2(0, 0 if on_top else FRAME.y - surface_h, FRAME.x, surface_h)
	var below := Rect2(0, surface_h if on_top else 0, FRAME.x, FRAME.y - surface_h)
	var colony_id := int(spec.get("colony", 0))
	var view := CutawayPanel.create_view(simulation, registry, colony_id, below)
	if view == null:
		return null
	var layout := SplitLayout.new()
	layout.sim = simulation
	layout.nest = simulation.colonies[colony_id].nest
	layout.surface_rect = surface
	layout.underground_rect = below
	layout.underground = view
	var props: Dictionary = spec.get("view", {})
	for key: String in props:
		if key in view:
			view.set(key, props[key])
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
	if "safe_rect" in underground:
		var safe := Rect2(0, Overlays.SafeZones.TOP, FRAME.x - Overlays.SafeZones.RIGHT,
				FRAME.y - Overlays.SafeZones.TOP - Overlays.SafeZones.BOTTOM)
		var r := safe.intersection(underground_rect)
		underground.set("safe_rect", Rect2(r.position - underground_rect.position, r.size))

func _process(delta: float) -> void:
	if not visible:
		return
	if "entrance_x" in underground:
		var at := surface_viewport.canvas_transform * nest.entrance_position()
		underground.set("entrance_x", at.x)
	if "highlight_ant" in underground:
		var ant: int = underground.get("highlight_ant")
		if ant != _ring_ant:
			_ring_ant = ant
			_ring_age = 0.0
	_ring_age += delta
	_ring.queue_redraw()

## A soft ring around the highlighted ant, fading out.
func _draw_ring() -> void:
	if _ring_ant < 0 or _ring_age > HIGHLIGHT_TIME or sim.alive[_ring_ant] == 0:
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
