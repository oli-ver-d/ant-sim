extends TestCase
## M16i: the scene checks of the scenario validator (SceneChecks).

func _issues(data: Dictionary, sim: Simulation = null) -> Array[Dictionary]:
	return SceneChecks.issues(data, Registry.create_default(), sim)

## Issues whose path starts with `prefix`.
func _at(issues: Array[Dictionary], prefix: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in issues:
		var path: Array = it["path"]
		if path.size() >= prefix.size() and path.slice(0, prefix.size()) == prefix:
			out.append(it)
	return out

func _shipped(name: String) -> void:
	var data := ScenarioLoader.load_data(name)
	var registry := Registry.create_default()
	var config: SimConfig = load("res://sim/default_config.tres")
	var sim := ScenarioLoader.build(data, registry, config)
	var issues := SceneChecks.issues(data, registry, sim)
	check_eq(issues.size(), 0, "%s has no scene issues: %s" % [name, issues])
	check_eq(SceneChecks.issues(data, registry).size(), 0, "%s without a sim: no issues" % name)

# --- checks ---------------------------------------------------------------------------------

func test_nest_and_food_outside_world() -> void:
	var data := {"colonies": [{"species": "x", "nest": [2400, 300]}, {"species": "x", "nest": [500, 500]}],
			"food": [{"type": "food_pile", "pos": [100, 100]}, {"type": "food_pile", "pos": [-5, 100]},
			{"type": "food_pile", "pos": [100, 5000]}]}
	var issues := _issues(data)
	check_eq(issues.size(), 3, "three outside")
	check_eq(_at(issues, ["colonies", 0]).size(), 1, "nest 0")
	check_eq(_at(issues, ["colonies", 1]).size(), 0, "nest 1 fine")
	check_eq(_at(issues, ["food", 0]).size(), 0, "food 0 fine")
	check_eq(_at(issues, ["food", 1, "pos"]).size(), 1, "food 1")
	check_eq(_at(issues, ["food", 2, "pos"]).size(), 1, "food 2")
	for it in issues:
		check_eq(it["severity"], "error")
	check("outside the world" in str(_at(issues, ["colonies", 0])[0]["message"]), "message names the problem")

func test_malformed_data_is_skipped() -> void:
	var data := {"colonies": [3, {"nest": "x"}, {"nest": [1]}, {"nest": ["a", 2]}], "food": [null, {"pos": {}}],
			"events": [1, {"t": "soon"}], "camera": "no", "duration": "long",
			"render": {"captions": [5, {"text": 3, "pos": []}], "fades": {}, "layout": 4}, "output": 9}
	var issues := _issues(data)
	check_eq(issues.size(), 0, "nothing to report, no crash")
	check_eq(_issues({"colonies": 1, "food": "x", "events": 3, "render": 7}).size(), 0, "wrong container types")

func test_inside_wall() -> void:
	var data := {"obstacles": [{"shape": "polyline", "points": [[100, 500], [400, 500]], "width": 40}],
			"food": [{"type": "food_pile", "pos": [250, 500]}, {"type": "food_pile", "pos": [250, 700]}]}
	var sim := ScenarioLoader.build(data, Registry.create_default(), load("res://sim/default_config.tres"))
	check(sim.world.is_blocked(Vector2(250, 500)), "test setup: the wall is there")
	var issues := _issues(data, sim)
	check_eq(issues.size(), 1, "one in a wall")
	check_eq(_at(issues, ["food", 0, "pos"]).size(), 1, "food in the wall")
	check_eq(issues[0]["severity"], "error")
	check("wall" in str(issues[0]["message"]), "message says wall")
	check_eq(_issues(data).size(), 0, "without a sim the wall check is skipped")

func test_world_size_from_sim() -> void:
	var data := {"food": [{"type": "food_pile", "pos": [500, 500]}]}
	var config: SimConfig = (load("res://sim/default_config.tres") as SimConfig).duplicate()
	config.world_size = Vector2i(400, 400)
	var sim := Simulation.new(config, Registry.create_default(), 1)
	check_eq(_issues(data, sim).size(), 1, "outside a 400x400 world")
	check_eq(_issues(data).size(), 0, "inside the default world")

func test_event_after_video_end() -> void:
	# 1 tick per frame: 60 ticks per video second, 2 sim seconds per video second at 30 Hz.
	var data := {"duration": 10, "ticks_per_frame": 1, "events": [{"t": 5, "type": "rain"}, {"t": 19, "type": "rain"},
			{"t": 25, "type": "rain"}]}
	var issues := _issues(data)
	check_eq(issues.size(), 1, "only the late event")
	check_eq(issues[0]["path"], ["events", 2, "t"])
	check_eq(issues[0]["severity"], "warning")
	data["ticks_per_frame"] = 2
	check_eq(_issues(data).size(), 0, "faster playback reaches sim time 25")

func test_video_items_after_duration() -> void:
	var data := {"duration": 20, "camera": [{"t": 0, "pos": [1, 1]}, {"t": 25, "pos": [2, 2]}],
			"render": {"captions": [{"t": 1, "until": 5, "text": "a"}, {"t": 30, "until": 34, "text": "b"}],
			"fades": [{"t": 21, "to": 1}], "grade": [{"t": 20, "brightness": 1}],
			"layout": {"modes": [{"t": 22, "mode": "split"}]}, "story_marker": [{"t": 40}]}}
	var issues := _issues(data)
	var paths: Array = []
	for it in issues:
		paths.append(it["path"])
		check_eq(it["severity"], "warning")
	check_eq(paths.size(), 5, "five late items: %s" % [paths])
	for p: Array in [["camera", 1, "t"], ["render", "captions", 1, "t"], ["render", "fades", 0, "t"],
			["render", "layout", "modes", 0, "t"], ["render", "story_marker", 0, "t"]]:
		check(paths.has(p), "flagged %s" % [p])
	# The two-list camera form.
	var d2 := {"duration": 10, "camera": {"surface": [{"t": 12, "pos": [1, 1]}], "nest": [{"t": 3, "pos": [1, 1]}]}}
	var i2 := _issues(d2)
	check_eq(i2.size(), 1)
	check_eq(i2[0]["path"], ["camera", "surface", 0, "t"])

func test_colonies_overlap() -> void:
	var data := {"colonies": [{"species": "x", "nest": [500, 500]}, {"species": "x", "nest": [520, 510]},
			{"species": "x", "nest": [900, 900]}]}
	var issues := _issues(data)
	check_eq(issues.size(), 1)
	check_eq(issues[0]["path"], ["colonies", 1], "warns on the later colony")
	check_eq(issues[0]["severity"], "warning")
	data["colonies"][1]["nest"] = [700, 500]
	check_eq(_issues(data).size(), 0, "far enough apart")

func test_captions_safe_zone() -> void:
	# tiktok: 400 px unsafe at the bottom of a 1080x1920 frame; "middle" is safe, "bottom" is placed
	# inside the safe area, and a caption wide enough to reach the right margin is not.
	var ok := {"render": {"captions": [{"t": 1, "text": "Hello", "pos": "bottom"},
			{"t": 2, "text": "Hi", "pos": "middle", "style": "title"}, {"t": 3, "text": "Top", "pos": "top"}]}}
	check_eq(_issues(ok).size(), 0, "default placements are safe")
	# A youtube_shorts frame has a 190 px right column; the caption column reaches 950 of 1080.
	var wide := {"output": {"safe_zones": "youtube_shorts"},
			"render": {"captions": [{"t": 1, "text": "A very long caption line that fills the column to its edges of the frame"}]}}
	var issues := _issues(wide)
	check_eq(issues.size(), 1, "reaches the button column")
	check_eq(issues[0]["path"], ["render", "captions", 0])
	check_eq(issues[0]["severity"], "warning")
	# No safe zones: nothing is unsafe.
	wide["output"] = {"safe_zones": "none"}
	check_eq(_issues(wide).size(), 0, "the 'none' preset has no margins")

# --- shipped scenarios ----------------------------------------------------------------------

func test_shipped_a() -> void:
	for n: String in ["basic_forage", "chaos_to_highway", "fungus_farm", "harvester_founding"]:
		_shipped(n)

func test_shipped_b() -> void:
	for n: String in ["leaf_strip", "leafcutter_life", "maze", "meadow_forage"]:
		_shipped(n)

func test_shipped_c() -> void:
	for n: String in ["nuptial_flight", "queen_landing", "rain_reset", "trunk_trail", "twig_bridge", "two_species"]:
		_shipped(n)

func test_shipped_colony_founding() -> void:
	_shipped("colony_founding")
