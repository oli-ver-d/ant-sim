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
##
## Partial rebuilds (M16f): the sim is built in ScenarioLoader's stages, and
## rebuild_kind() compares the document with the one last built. When only
## the ground and scatters changed, the kept sim's scatter props are taken
## away (Scenery.truncate), the ground is remade and the scatters run again,
## which gives the same sim as a full build (tests/test_editor_rebuild.gd)
## without rebuilding the colonies (~0.75 s for a founding nest). When no
## simulated key changed (render, output, camera...), only the view is new.

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
			_redraw_layers()
## Milliseconds the last build took.
var build_ms: float = 0.0
var status: String = ""
## What the last rebuild did: "full", "scatter" (ground and scatters redone on
## the kept sim) or "view" (same sim, new view).
var last_kind: String = ""
## False forces full rebuilds (tests compare the two).
var partial := true
## Each scatter's Scatter.Result by its index in the document's "scenery".
var scatter_results: Dictionary = {}
## Where the last built sim's scenery was before its scatters.
var scatter_mark := Vector2i.ZERO
## Scenery.mark() before each scatter, by its index in "scenery".
var scatter_marks: Dictionary = {}
## The first "scenery" index the last rebuild scattered again (-1: none).
var rescattered_from: int = -1

## The top-level keys ScenarioLoader.build reads: the sim depends on nothing else.
const SIM_KEYS: Array[String] = ["seed", "colonies", "food", "obstacles", "ground", "scenery", "debris",
		"events", "max_agents"]

var _viewport: SubViewport
var _world_root: Node2D
var _overlay: PreviewOverlay
var _rebuild_in: float = -1.0
var _panning := false
## The rect the view was last fitted to, refitted when the preview is resized
## until the user pans or zooms (then Rect2()).
var _fit_rect := Rect2()
var _moved := false
## A deep copy of the document the current sim was built from.
var _built: Dictionary = {}

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

## Adds a world-space layer drawn over the overlays (the canvas gizmos).
func add_layer(layer: Node2D) -> void:
	layer.z_index = 101
	_viewport.add_child(layer)

## Redraws the added layers and overlays (the camera moved).
func _redraw_layers() -> void:
	for c: Node in _viewport.get_children():
		if c is CanvasItem and c != _world_root:
			(c as CanvasItem).queue_redraw()

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
	var kind := rebuild_kind(_built, data) if partial and sim != null else "full"
	var new_sim := sim
	match kind:
		"full":
			new_sim = ScenarioLoader.build_base(data, registry, config)
			if new_sim == null:
				_set_status("Build failed (see the log)")
				return
			scatter_mark = new_sim.scenery.mark()
			scatter_marks = {}
			scatter_results = ScenarioLoader.add_scatters(new_sim, data, 0, scatter_marks)
			rescattered_from = 0
			ScenarioLoader.finish(new_sim, data)
		"scatter":
			# Scatters before the first changed entry are as they were.
			var from := scatter_from(_built, data)
			var cut := Vector2i(-1, -1)
			for k: int in scatter_marks.keys():
				if k >= from:
					var at: Vector2i = scatter_marks[k]
					if cut.x < 0 or at.x < cut.x:
						cut = at
					scatter_marks.erase(k)
					scatter_results.erase(k)
			if cut.x >= 0:
				new_sim.scenery.truncate(cut)
			if not same(_built.get("ground"), data.get("ground")):
				ScenarioLoader.set_ground(new_sim, data)
			scatter_results.merge(ScenarioLoader.add_scatters(new_sim, data, from, scatter_marks))
			rescattered_from = from
		"view":
			rescattered_from = -1
	last_kind = kind
	_built = data.duplicate(true)
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
	_redraw_layers()
	var what: String = {"full": "Built", "scatter": "Rebuilt ground and scenery", "view": "Redrawn"}[kind]
	_set_status("%s in %d ms: %d colonies, %d food, %d ants, %d props%s" % [what, roundi(build_ms),
			sim.colonies.size(), sim.food_sources.size(), sim.ant_count, sim.scenery.props.size(), _dropped_note()])
	if not _moved and not _fit_rect.has_area():
		fit_world()

## The prop built from the hand-placed entry `index` of the built document's
## "scenery" (null for a scatter, an unknown type or a stale index).
func hand_prop(index: int) -> Prop:
	var scenery: Variant = _built.get("scenery", [])
	if sim == null or not scenery is Array or index < 0 or index >= (scenery as Array).size():
		return null
	var entry: Variant = scenery[index]
	if not entry is Dictionary or (entry as Dictionary).has("scatter"):
		return null
	# Props built before the scatters (obstacle looks may add some too) with the
	# entry's params; the nth of them for the nth equal entry.
	var nth := 0
	for e: Variant in (scenery as Array).slice(0, index):
		if same(e, entry):
			nth += 1
	var props := sim.scenery.props
	for i in mini(scatter_mark.x, props.size()):
		if props[i].params == entry:
			if nth == 0:
				return props[i]
			nth -= 1
	return null

## ", N blocking props dropped by scatters" (they would have cut a colony off).
func _dropped_note() -> String:
	var n := 0
	for r: Scatter.Result in scatter_results.values():
		n += r.dropped
	return ", %d blocking props dropped by scatters" % n if n > 0 else ""

## How to get from the sim built from `old` to one for `new`: "full",
## "scatter" (only the ground and scatter entries differ; the hand-placed
## props, which colonies and food may react to, are the same), or "view"
## (nothing the sim reads differs).
static func rebuild_kind(old: Dictionary, new: Dictionary) -> String:
	if old.is_empty():
		return "full"
	var kind := "view"
	for key: String in SIM_KEYS:
		if same(old.get(key), new.get(key)):
			continue
		if key == "ground":
			kind = "scatter"
		elif key == "scenery" and old.get(key) is Array and new.get(key) is Array \
				and same(hand_props(old[key]), hand_props(new[key])):
			kind = "scatter"
		else:
			return "full"
	return kind

## For a "scatter" rebuild: the first "scenery" index whose scatter must run
## again (0 when the ground changed, since scatters follow the materials).
static func scatter_from(old: Dictionary, new: Dictionary) -> int:
	if not same(old.get("ground"), new.get("ground")):
		return 0
	var a: Array = old.get("scenery", []) if old.get("scenery") is Array else []
	var b: Array = new.get("scenery", []) if new.get("scenery") is Array else []
	for i in mini(a.size(), b.size()):
		if not same(a[i], b[i]):
			return i
	return mini(a.size(), b.size())

## The "scenery" entries that aren't scatters, in order.
static func hand_props(scenery: Array) -> Array:
	return scenery.filter(func(e: Variant) -> bool: return not (e is Dictionary and (e as Dictionary).has("scatter")))

## Deep equality that tells types apart (and never errors on mixed types).
static func same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

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
	_redraw_layers()

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
		_redraw_layers()
		accept_event()

## Zooms by `factor`, keeping the world point under `local` where it is.
func zoom_about(local: Vector2, factor: float) -> void:
	var before := to_world(local)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.position += before - to_world(local)
	_fit_rect = Rect2()
	_moved = true
	_redraw_layers()

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
