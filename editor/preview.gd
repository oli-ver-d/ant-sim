class_name EditorPreview
extends SubViewportContainer
## The editor's static preview: the document built into a Simulation at t = 0
## (ScenarioLoader.build, never stepped) and drawn by a WorldView in a
## SubViewport, with its own pan/zoom camera (wheel zooms about the cursor,
## middle or right drag pans), "fit world" and "fit output frame".
##
## Overlays in world space: the world bounds, the output frame (the
## document's output.size and safe-zone preset) where the first camera
## keyframe puts it, and the selected outline item's bounds.
##
## Rebuilds are debounced (REBUILD_DELAY after the last request) so a burst
## of edits builds once. The status line gets the build time or the error.

signal status_changed(text: String)

## Seconds after the last rebuild request before the preview is rebuilt.
const REBUILD_DELAY := 0.25
const MIN_ZOOM := 0.05
const MAX_ZOOM := 20.0
const WHEEL_STEP := 1.15

var config: SimConfig = preload("res://sim/default_config.tres")
var registry: Registry
var data: Dictionary = {}
var sim: Simulation
var view: WorldView
var camera: Camera2D
var frame := OutputFrame.new()
## World rect of the selected item (Rect2() for none).
var selection := Rect2():
	set(r):
		selection = r
		if _overlay != null:
			_overlay.queue_redraw()
## Milliseconds the last build took.
var build_ms: float = 0.0
var status: String = ""

var _viewport: SubViewport
var _world_root: Node2D
var _overlay: PreviewOverlay
var _rebuild_in: float = -1.0
var _panning := false
## The rect the view was last fitted to, refitted when the preview is resized
## until the user pans or zooms (then Rect2()).
var _fit_rect := Rect2()
var _moved := false

func _init() -> void:
	stretch = true
	focus_mode = Control.FOCUS_CLICK
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = false
	add_child(_viewport)
	_world_root = Node2D.new()
	_viewport.add_child(_world_root)
	camera = Camera2D.new()
	_viewport.add_child(camera)
	_overlay = PreviewOverlay.new()
	_overlay.preview = self
	# Over the world (the WorldView is replaced on every rebuild).
	_overlay.z_index = 100
	_viewport.add_child(_overlay)

func _ready() -> void:
	camera.make_current()
	resized.connect(func() -> void:
		if _fit_rect.has_area():
			fit_rect(_fit_rect))

## Shows `scenario` (rebuilt after REBUILD_DELAY, or now with `now`).
func show_data(scenario: Dictionary, now: bool = false) -> void:
	data = scenario
	if now:
		rebuild()
	else:
		_rebuild_in = REBUILD_DELAY

func rebuild_pending() -> bool:
	return _rebuild_in >= 0.0

func _process(delta: float) -> void:
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			rebuild()

## Builds the document into a new Simulation and view, replacing the old ones.
func rebuild() -> void:
	_rebuild_in = -1.0
	if registry == null:
		registry = Registry.create_default()
		CoreRenderers.register(registry)
	var t0 := Time.get_ticks_usec()
	if not data.get("colonies", []) is Array or not data.get("food", []) is Array:
		_set_status("Not built: colonies and food must be lists")
		return
	var new_sim := ScenarioLoader.build(data, registry, config)
	if new_sim == null:
		_set_status("Build failed (see the log)")
		return
	var new_view := WorldView.new()
	new_view.setup(new_sim, registry, float(new_sim.rng.seed % 100))
	var render: Dictionary = data.get("render", {}) if data.get("render", {}) is Dictionary else {}
	new_view.pheromone_renderer.visible = bool(render.get("pheromones", true))
	if view != null:
		view.queue_free()
	sim = new_sim
	view = new_view
	_world_root.add_child(view)
	frame = OutputFrame.from_scenario(data)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_overlay.queue_redraw()
	_set_status("Built in %d ms: %d colonies, %d food, %d ants" % [roundi(build_ms), sim.colonies.size(),
			sim.food_sources.size(), sim.ant_count])
	if not _moved and not _fit_rect.has_area():
		fit_world()

func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)

# --- camera ------------------------------------------------------------------

func world_size() -> Vector2:
	return Vector2(config.world_size)

func fit_world() -> void:
	fit_rect(Rect2(Vector2.ZERO, world_size()))

func fit_frame() -> void:
	fit_rect(frame_world_rect(data, frame, world_size()))

func fit_rect(r: Rect2) -> void:
	_fit_rect = r
	_moved = false
	camera.position = r.get_center()
	var z := fit_zoom(r, size, 24.0)
	camera.zoom = Vector2.ONE * clampf(z, MIN_ZOOM, MAX_ZOOM)
	_overlay.queue_redraw()

## World position under a point of this control.
func to_world(local: Vector2) -> Vector2:
	return camera.position + (local - size / 2.0) / camera.zoom.x

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var f := WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP
			zoom_about(mb.position, f)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			accept_event()
	var mm := event as InputEventMouseMotion
	if mm != null and _panning:
		camera.position -= mm.relative / camera.zoom.x
		_fit_rect = Rect2()
		_moved = true
		_overlay.queue_redraw()
		accept_event()

## Zooms by `factor`, keeping the world point under `local` where it is.
func zoom_about(local: Vector2, factor: float) -> void:
	var before := to_world(local)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.position += before - to_world(local)
	_fit_rect = Rect2()
	_moved = true
	_overlay.queue_redraw()

# --- pure helpers (tested) -----------------------------------------------------

## Zoom (view pixels per world unit) that fits `r` plus `margin` view pixels
## on each side into a view of `view_size`.
static func fit_zoom(r: Rect2, view_size: Vector2, margin: float = 0.0) -> float:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return 1.0
	var avail := (view_size - Vector2.ONE * margin * 2.0).max(Vector2.ONE)
	return minf(avail.x / r.size.x, avail.y / r.size.y)

## The world rect the output frame shows at the first camera keyframe (the
## surface track of a {surface, nest} camera): centred on its "pos" (or a
## follow's "near"), frame size / zoom. Without a usable position it is
## centred on the world; a "fit" keyframe shows the whole world.
static func frame_world_rect(scenario: Dictionary, out: OutputFrame, world: Vector2) -> Rect2:
	var cams: Variant = scenario.get("camera", [])
	if cams is Dictionary:
		cams = cams.get("surface", [])
	var centre := world / 2.0
	var z := 1.0
	if cams is Array and not (cams as Array).is_empty() and cams[0] is Dictionary:
		var first: Dictionary = cams[0]
		for k: Dictionary in cams:
			if k is Dictionary and float(k.get("t", 0.0)) < float(first.get("t", 0.0)):
				first = k
		z = maxf(float(first.get("zoom", 1.0)), 0.01)
		var at: Variant = first.get("pos")
		if at == null and first.get("follow") is Dictionary:
			at = first["follow"].get("near")
		if at is Array and (at as Array).size() == 2:
			centre = Vector2(float(at[0]), float(at[1]))
		elif first.has("fit"):
			z = minf(out.size_f().x / world.x, out.size_f().y / world.y)
	var size_world := out.size_f() / z
	return Rect2(centre - size_world / 2.0, size_world)

## Draws the overlays in world space, over the WorldView.
class PreviewOverlay extends Node2D:
	const BOUNDS := Color(1, 1, 1, 0.35)
	const FRAME := Color(0.35, 0.8, 1.0, 0.95)
	const SHADE := Color(1.0, 0.2, 0.25, 0.18)
	const SELECT := Color(1.0, 0.85, 0.2, 1.0)
	var preview: EditorPreview

	func _draw() -> void:
		if preview == null or preview.sim == null:
			return
		var px := 1.0 / preview.camera.zoom.x
		draw_rect(Rect2(Vector2.ZERO, preview.world_size()), BOUNDS, false, 2.0 * px)
		var f := preview.frame
		var r := EditorPreview.frame_world_rect(preview.data, f, preview.world_size())
		var s := r.size.x / f.size_f().x
		for u: Rect2 in f.unsafe_rects():
			draw_rect(Rect2(r.position + u.position * s, u.size * s), SHADE)
		draw_rect(r, FRAME, false, 2.0 * px)
		draw_string(ThemeDB.fallback_font, r.position + Vector2(4, -6) * px, "output %dx%d (%s)" % [f.size.x,
				f.size.y, f.safe_zones], HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(14 * px), 1), FRAME)
		if preview.selection.has_area():
			draw_rect(preview.selection.grow(6 * px), SELECT, false, 2.0 * px)
