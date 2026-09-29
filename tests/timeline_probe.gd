extends SceneTree
## Headless probe of a scenario's playback schedule (M17g), for placing
## captions and camera keyframes on story beats: integrates its
## ticks_per_frame points (linear ramps, jumps) frame by frame, as
## ScenarioPlayer does, and prints the sim time at the given video times and
## the video time (and speed) at the given sim times. Nothing is simulated.
##
##   godot --headless --path . -s res://tests/timeline_probe.gd -- <scenario> <v1,v2,...> [s:<sim1,sim2,...>]
##
## A sim time skipped by a jump is printed as such, with the video time of
## the jump.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <scenario> <video times> [s:<sim times>]")
		quit(1)
		return
	var data := ScenarioLoader.load_data(args[0])
	var pts: Array[Vector2] = []
	var jumps: Array[Vector2] = []
	var spec: Variant = data.get("ticks_per_frame", 0.5)
	if spec is Array:
		for p: Dictionary in spec:
			if p.has("tpf"):
				pts.append(Vector2(float(p["t"]), float(p["tpf"])))
			if float(p.get("jump", 0.0)) > 0.0:
				jumps.append(Vector2(float(p["t"]), float(p["jump"])))
	else:
		pts.append(Vector2(0.0, float(spec)))
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	jumps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var want: Array[float] = []
	for s: String in str(args[1]).split(",", false):
		want.append(float(s))
	want.sort()
	var sims: Array[float] = []
	if args.size() > 2:
		for s: String in str(args[2]).trim_prefix("s:").split(",", false):
			sims.append(float(s))
	sims.sort()
	var fps := float(ScenarioPlayer.VIDEO_FPS)
	var tick_rate := (load("res://sim/default_config.tres") as SimConfig).tick_rate
	var duration := float(data.get("duration", 60.0))
	var dt := 1.0 / fps
	var v := 0.0
	var sim := 0.0
	var jd := 0
	var wi := 0
	var si := 0
	while v <= duration + 1e-6:
		while jd < jumps.size() and jumps[jd].x <= v + 1e-6:
			var after := sim + jumps[jd].y
			while si < sims.size() and sims[si] <= after:
				print("sim %8.2f  skipped by the jump at V%.2f (sim %.2f -> %.2f)" % [sims[si], v, sim, after])
				si += 1
			sim = after
			jd += 1
		while wi < want.size() and want[wi] <= v + 1e-6:
			print("V%7.2f = sim %8.2f" % [want[wi], sim])
			wi += 1
		var tpf := _tpf(pts, v)
		var next := sim + tpf * fps / tick_rate * dt
		while si < sims.size() and sims[si] <= next:
			print("sim %8.2f = V%7.2f  (tpf %.2f, %.1fx)" % [sims[si], v + dt * (sims[si] - sim) / maxf(1e-9, next - sim), tpf, tpf * fps / tick_rate])
			si += 1
		sim = next
		v += dt
	print("end V%.2f = sim %.2f" % [duration, sim])
	quit()

func _tpf(pts: Array[Vector2], t: float) -> float:
	if t <= pts[0].x:
		return pts[0].y
	for k in range(1, pts.size()):
		if t <= pts[k].x:
			var a := pts[k - 1]
			var b := pts[k]
			return lerpf(a.y, b.y, (t - a.x) / maxf(1e-9, b.x - a.x))
	return pts[pts.size() - 1].y
