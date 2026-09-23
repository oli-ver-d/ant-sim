extends Node
## Dev tool: prints FPS and simulation cost every 2 s. Enabled in the main
## scene with --probe=1, e.g. godot --path . -- --probe=1 --ants=3000
var frames := 0

func _process(_delta: float) -> void:
	frames += 1
	if frames % 120 == 0:
		var main := get_parent()
		var sim: Simulation = main.get("sim")
		print("fps %d  sim %.1f ms/frame  ants %d  draw calls %d" % [
			Engine.get_frames_per_second(), main.get("_sim_ms"), sim.ant_count,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
