extends Node
## Dev tool: prints FPS and where frame time goes, every 2 s (120 frames).
## Enabled in the main scene with --probe=1, e.g.
##   godot --path . -- --scenario=colony_founding --at=62 --layout=split --probe=1
## Line 1 (whole frame):
##   sim:     ms per frame spent advancing the simulation
##   process: ms per frame in all _process() calls (sim + renderers' updates)
##   render:  ms per frame the renderer spent on the CPU / GPU (root viewport)
##   items:   items in existence (carried or on the ground)
##   draw calls: Godot's global monitor
## Then one "viewport" line per viewport (the root and every SubViewport, e.g.
## the split layout's surface and nest views): render cpu / gpu ms as Godot
## measures them, plus draw calls and objects from the viewport's render info.
## (For 2D canvas items the render info may read 0; the global draw-call
## monitor above still counts them.)
## Finally the 12 most expensive Profiler keys over the window (renderers'
## _process/_draw, see Profiler), as ms per frame and calls per frame.
## --probe=N with N > 1 quits after N reports (for scripted baselines; the
## first report includes the start-up bakes, so use a few).
const EVERY := 120
const TOP := 12

var frames := 0
var _reports_left := 0
## Viewports whose render time measuring is on, by RID.
var _measured: Dictionary[RID, bool] = {}

func _ready() -> void:
	Profiler.on = true
	Profiler.reset()
	_measure(get_viewport())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			var n := int(a.get_slice("=", 1))
			_reports_left = n if n > 1 else 0

func _measure(vp: Viewport) -> void:
	var rid := vp.get_viewport_rid()
	if not _measured.has(rid):
		_measured[rid] = true
		RenderingServer.viewport_set_measure_render_time(rid, true)

func _viewports() -> Array[Viewport]:
	var out: Array[Viewport] = [get_tree().root]
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is SubViewport:
				out.append(child as SubViewport)
			stack.append(child)
	return out

func _process(_delta: float) -> void:
	frames += 1
	if frames % EVERY != 0:
		return
	var main := get_parent()
	var sim: Simulation = main.get("sim")
	var vp := get_viewport().get_viewport_rid()
	print("fps %d  sim %.1f ms  process %.1f ms  render cpu %.1f gpu %.1f ms  ants %d  items %d  draw calls %d" % [
		Engine.get_frames_per_second(), main.get("_sim_ms"),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		sim.ant_count, sim.items.size(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	for v in _viewports():
		var rid := v.get_viewport_rid()
		if not _measured.has(rid):
			# Measured from the next report on (the first reading would be empty).
			_measure(v)
			continue
		print("  viewport %-40s cpu %.2f gpu %.2f ms  draw calls %d  objects %d" % [
			"root" if v == get_tree().root else String(v.name),
			RenderingServer.viewport_get_measured_render_time_cpu(rid),
			RenderingServer.viewport_get_measured_render_time_gpu(rid),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])
	var ranked := Profiler.ranked()
	for k in mini(TOP, ranked.size()):
		var key := ranked[k]
		print("  %-44s %6.2f ms/frame  %5.1f calls/frame" % [
			key, Profiler.usec[key] / float(EVERY) / 1000.0, Profiler.calls[key] / float(EVERY)])
	Profiler.reset()
	if _reports_left > 0:
		_reports_left -= 1
		if _reports_left == 0:
			get_tree().quit()
