extends Node
## Dev tool: prints FPS and where frame time goes, every 2 s. Enabled in the
## main scene with --probe=1, e.g. godot --path . -- --probe=1 --ants=3000
##   sim:     ms per frame spent advancing the simulation
##   process: ms per frame in all _process() calls (sim + renderers' updates)
##   render:  ms per frame the renderer spent on the CPU / GPU (Godot's measure)
##   items:   items in existence (carried or on the ground)
var frames := 0

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(_delta: float) -> void:
	frames += 1
	if frames % 120 == 0:
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
