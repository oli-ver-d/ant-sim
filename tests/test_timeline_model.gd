extends TestCase
## M16g: the timeline model (time mapping, tracks, hit testing, edits), GUI-free.

const DIG_DEMO := "res://tests/fixtures/scenarios/dig_demo.json"
const LIFE := "res://scenarios/leafcutter_life.json"

func check_near(actual: float, expected: float, tol: float, message: String = "") -> void:
	check(absf(actual - expected) <= tol, "%s: %s is not within %s of %s" % [message, actual, tol, expected])

func _map(data: Dictionary) -> TimelineModel.TimeMap:
	return TimelineModel.time_map(data)

func _tpf_data(spec: Variant, warmup: float = 0.0) -> Dictionary:
	return {"ticks_per_frame": spec, "warmup": warmup}

func _track(tracks: Array[Dictionary], id: String) -> Dictionary:
	for tr in tracks:
		if tr["id"] == id:
			return tr
	return {}

# --- time mapping ---------------------------------------------------------------------------

func test_tpf_at_matches_player() -> void:
	var data := ScenarioLoader.load_data(LIFE)
	var player := ScenarioPlayer.new()
	player._parse_tpf(data["ticks_per_frame"])
	var map := _map(data)
	check_eq(map.points.size(), player._tpf_points.size(), "same points")
	check_eq(map.jumps.size(), player._jumps.size(), "same jumps")
	for t: float in [-1.0, 0.0, 5.0, 12.0, 12.25, 12.5, 14.0, 16.25, 19.2, 38.5, 54.5, 55.7, 60.0, 85.0, 150.0, 1e6]:
		check_near(map.tpf_at(t), player.ticks_per_frame_at(t), 1e-9, "tpf at %s" % t)
	player.free()

func test_sim_time_constant_and_warmup() -> void:
	var map := _map(_tpf_data(2.0, 5.0))
	check_near(map.sim_time_at(0.0), 5.0, 1e-9, "warmup at 0")
	check_near(map.sim_time_at(-3.0), 5.0, 1e-9, "before 0")
	# 2 ticks per frame = 120 ticks per video second = 4 sim seconds at 30 Hz.
	check_near(map.sim_time_at(10.0), 5.0 + 40.0, 1e-9)
	check_near(map.video_time_at(45.0), 10.0, 1e-9)
	check_near(map.video_time_at(3.0), 0.0, 1e-9, "inside warmup")

func test_default_tpf_when_absent() -> void:
	var map := TimelineModel.time_map({})
	check_eq(map.points.size(), 1)
	check_near(map.tpf_at(3.0), 0.5, 1e-9)
	check_near(map.sim_time_at(2.0), 2.0, 1e-9, "0.5 tpf is real time")
	check_near(map.duration, 20.0, 1e-9)

func test_sim_time_ramp() -> void:
	# tpf 1 until 2, ramping to 3 at 4, then 3.
	var map := _map(_tpf_data([{"t": 0, "tpf": 1}, {"t": 2, "tpf": 1}, {"t": 4, "tpf": 3}]))
	# integral to 4: 2 + (1+3)/2*2 = 6; to 6: 6 + 6 = 12; to 3: 2 + (1+2)/2*1 = 3.5
	check_near(map.sim_time_at(4.0), 60.0 * 6.0 / 30.0, 1e-9)
	check_near(map.sim_time_at(6.0), 60.0 * 12.0 / 30.0, 1e-9)
	check_near(map.sim_time_at(3.0), 60.0 * 3.5 / 30.0, 1e-9)
	for t: float in [0.5, 2.0, 2.7, 3.0, 3.99, 4.0, 5.5, 9.0]:
		check_near(map.video_time_at(map.sim_time_at(t)), t, 1e-6, "round trip %s" % t)

func test_points_before_first_are_constant() -> void:
	var map := _map(_tpf_data([{"t": 2, "tpf": 4}, {"t": 3, "tpf": 4}]))
	check_near(map.sim_time_at(1.0), 8.0, 1e-9)
	check_near(map.sim_time_at(3.0), 24.0, 1e-9)

func test_jump() -> void:
	var map := _map(_tpf_data([{"t": 0, "tpf": 0.5}, {"t": 10, "tpf": 0.5, "jump": 100}]))
	check_near(map.sim_time_at(9.99), 9.99, 1e-9, "before")
	check_near(map.sim_time_at(10.0), 110.0, 1e-9, "at")
	check_near(map.sim_time_at(12.0), 112.0, 1e-9, "after")
	check_near(map.video_time_at(50.0), 10.0, 1e-9, "inside the jump")
	check_near(map.video_time_at(9.5), 9.5, 1e-9, "before the jump")
	check_near(map.video_time_at(111.0), 11.0, 1e-9, "after the jump")

func test_jump_at_start_counts_in_zero() -> void:
	var map := _map(_tpf_data([{"t": 0, "tpf": 0.5, "jump": 30}], 2.0))
	check_near(map.sim_time_at(0.0), 32.0, 1e-9)
	check_near(map.video_time_at(20.0), 0.0, 1e-9)

func test_round_trip_leafcutter() -> void:
	var map := _map(ScenarioLoader.load_data(LIFE))
	var t := 0.0
	while t < 190.0:
		var s := map.sim_time_at(t)
		var back := map.video_time_at(s)
		# On a jump the smallest video time is the jump's own.
		check(back <= t + 1e-6, "video_time_at(sim_time_at(%s)) = %s is not later" % [t, back])
		check_near(map.sim_time_at(back), s, 1e-6, "same sim time at %s" % t)
		t += 3.37

func test_zero_tpf_tail_is_infinite() -> void:
	var map := _map(_tpf_data([{"t": 0, "tpf": 1}, {"t": 5, "tpf": 1}, {"t": 6, "tpf": 0}]))
	var end := map.sim_time_at(100.0)
	check_near(end, map.sim_time_at(6.0), 1e-9, "stopped")
	check_near(map.video_time_at(end), 6.0, 1e-3, "reaches the plateau (flat end of a quadratic: sqrt-sensitive)")
	check_eq(map.video_time_at(end + 1.0), INF, "never")

func test_zero_tpf_middle() -> void:
	var map := _map(_tpf_data([{"t": 0, "tpf": 1}, {"t": 2, "tpf": 1}, {"t": 2.001, "tpf": 0}, {"t": 4, "tpf": 0}, {"t": 4.001, "tpf": 1}]))
	var s := map.sim_time_at(4.0)
	check_near(map.video_time_at(s), 2.0005, 0.01, "stops at the flat start")
	check(map.video_time_at(s + 0.5) > 4.0, "then continues")

func test_time_map_malformed() -> void:
	var map := _map({"ticks_per_frame": [1, {"tpf": 2}, {"t": "x"}, {"t": 3, "tpf": "a", "jump": "b"}], "warmup": "x", "duration": []})
	check_eq(map.points.size(), 1)
	check_near(map.tpf_at(1.0), 0.5, 1e-9)
	check_eq(map.jumps.size(), 0)
	check_near(map.warmup, 0.0, 1e-9)
	check_near(map.duration, 20.0, 1e-9)

## The model against the real player: warmup, a ramp and a jump.
func test_sim_time_matches_player() -> void:
	var data := ScenarioLoader.load_data(DIG_DEMO)
	data["warmup"] = 1
	data["ticks_per_frame"] = [{"t": 0, "tpf": 0.5}, {"t": 1, "tpf": 0.5}, {"t": 2, "tpf": 4},
			{"t": 2.5, "tpf": 4, "jump": 3}, {"t": 3, "tpf": 1}]
	data["render"] = {"layout": {"mode": "surface", "colony": 0}}
	var map := _map(data)
	var root := (Engine.get_main_loop() as SceneTree).root
	var player := ScenarioPlayer.new()
	root.add_child(player)
	player.setup_data(data)
	var dt := 1.0 / float(map.tick_rate)
	check_near(player.sim.time(), map.sim_time_at(0.0), dt * 1.5, "warmup")
	var tol := 5.0 * dt
	for f in 180:
		player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)
		if f == 89 or f == 149 or f == 179:
			var expected := map.sim_time_at(float(f + 1) / 60.0)
			check_near(player.sim.time(), expected, tol, "frame %d: sim %s vs %s" % [f + 1, player.sim.time(), expected])
	player.queue_free()

# --- tracks ---------------------------------------------------------------------------------

func _sample() -> Dictionary:
	return {
		"camera": [{"t": 0, "pos": [540, 960], "zoom": 3}, {"t": 4, "follow": {"near": [1, 2]}}, {"t": 6, "fit": "excavation", "zoom": 1.5}],
		"ticks_per_frame": [{"t": 0, "tpf": 0.5}, {"t": 5, "tpf": 2, "jump": 60}, {"t": 6, "jump": 120}, {"t": 7, "tpf": 1, "jump": 0}],
		"render": {
			"layout": {"modes": [{"t": 0, "mode": "surface"}, {"t": 3, "mode": "split"}]},
			"captions": [{"t": 1, "until": 3, "text": "Hello\nsecond line"}, {"t": 8, "text": "A very long caption that goes on and on and on"}],
			"fades": [{"t": 0, "to": 0.5}],
			"grade": [{"t": 2, "brightness": 1.1}],
			"story_marker": [{"t": 2, "until": 6}, {"t": 9}],
		},
		"events": [{"t": 10, "type": "rain"}, {"t": 1, "type": "wind"}],
		"duration": 30,
	}

func test_tracks_ids_and_paths() -> void:
	var data := _sample()
	var tr := TimelineModel.tracks(data, _map(data))
	var ids: Array = tr.map(func(t: Dictionary) -> String: return t["id"])
	check_eq(ids, ["camera", "speed", "layout", "captions", "fades", "grade", "story_marker", "events"])
	check_eq(_track(tr, "camera")["items"].size(), 3)
	check_eq(_track(tr, "camera")["items"][2]["path"], ["camera", 2])
	check_eq(_track(tr, "layout")["items"][1]["path"], ["render", "layout", "modes", 1])
	check_eq(_track(tr, "captions")["list"], ["render", "captions"])
	check_eq(_track(tr, "speed")["kind"], "curve")
	check_eq(_track(tr, "events")["clock"], "sim")
	check_eq(_track(tr, "camera")["clock"], "video")
	check_eq(_track(tr, "speed")["items"].size(), 4)
	check_eq(_track(tr, "grade")["items"].size(), 1)

func test_tracks_labels() -> void:
	var data := _sample()
	var tr := TimelineModel.tracks(data, _map(data))
	var cam: Array = _track(tr, "camera")["items"]
	check_eq(cam[0]["label"], "pos 540,960 ×3")
	check_eq(cam[1]["label"], "follow")
	check_eq(cam[2]["label"], "fit ×1.5")
	var sp: Array = _track(tr, "speed")["items"]
	check_eq(sp[0]["label"], "tpf 0.5")
	check_eq(sp[1]["label"], "tpf 2, jump 60 s")
	check_eq(sp[2]["label"], "jump 120 s")
	check_eq(_track(tr, "layout")["items"][1]["label"], "split")
	var caps: Array = _track(tr, "captions")["items"]
	check_eq(caps[0]["label"], "Hello")
	check(caps[1]["label"].length() <= 40 and caps[1]["label"].ends_with("…"), "cut: %s" % caps[1]["label"])
	check_eq(_track(tr, "fades")["items"][0]["label"], "to 0.5")
	check_eq(_track(tr, "story_marker")["items"][0]["label"], "marker")
	check_eq(_track(tr, "events")["items"][0]["label"], "rain")

func test_tracks_span_untils() -> void:
	var data := _sample()
	var tr := TimelineModel.tracks(data, _map(data))
	var caps: Array = _track(tr, "captions")["items"]
	check_near(caps[0]["until"], 3.0, 1e-9)
	check(caps[0]["has_until"], "explicit until")
	check_near(caps[1]["until"], 12.0, 1e-9, "default t + 4")
	check(not caps[1]["has_until"], "absent until")
	var mk: Array = _track(tr, "story_marker")["items"]
	check_near(mk[1]["until"], 9.0, 1e-9, "marker without until")
	check_near(_track(tr, "camera")["items"][0]["until"], -1.0, 1e-9, "not a span")
	check_near(_track(tr, "camera")["items"][0]["sim_t"], -1.0, 1e-9)

func test_tracks_camera_split() -> void:
	var data := {"camera": {"surface": [{"t": 0}, {"t": 2}], "nest": [{"t": 1, "pos": [1, 2]}], "x": 1}}
	var tr := TimelineModel.tracks(data, _map(data))
	var ids: Array = tr.map(func(t: Dictionary) -> String: return t["id"])
	check_eq(ids.slice(0, 3), ["camera_surface", "camera_nest", "speed"])
	check_eq(tr.size(), 9)
	check_eq(_track(tr, "camera_surface")["label"], "Camera: surface")
	check_eq(_track(tr, "camera_surface")["items"][1]["path"], ["camera", "surface", 1])
	check_eq(_track(tr, "camera_nest")["items"][0]["path"], ["camera", "nest", 0])
	check_eq(_track(tr, "camera_nest")["list"], ["camera", "nest"])

func test_tracks_events_use_the_map() -> void:
	var data := {"ticks_per_frame": [{"t": 0, "tpf": 0.5}, {"t": 10, "tpf": 0.5, "jump": 100}], "events": [{"t": 5, "type": "a"}, {"t": 60, "type": "b"}, {"t": 115, "type": "c"}]}
	var map := _map(data)
	var ev: Array = _track(TimelineModel.tracks(data, map), "events")["items"]
	check_near(ev[0]["t"], 5.0, 1e-9)
	check_near(ev[1]["t"], 10.0, 1e-9, "inside the jump")
	check_near(ev[2]["t"], 15.0, 1e-9)
	check_near(ev[2]["sim_t"], 115.0, 1e-9)

func test_tracks_malformed() -> void:
	var data := {"camera": "x", "ticks_per_frame": 0.5, "events": [1, {"type": "no t"}, {"t": "x"}],
			"render": {"captions": [1, {"text": "no t"}], "layout": 5, "fades": {"t": 1}}}
	var tr := TimelineModel.tracks(data, _map(data))
	check_eq(tr.size(), 8)
	for t in tr:
		check_eq(t["items"].size(), 0, "no items in %s" % t["id"])
	var none := TimelineModel.tracks({"render": "x", "events": 3}, _map({}))
	check_eq(none.size(), 8)

func test_tracks_of_real_scenarios() -> void:
	var data := ScenarioLoader.load_data(LIFE)
	var tr := TimelineModel.tracks(data, _map(data))
	check_eq(tr.size(), 9, "leafcutter_life has split camera tracks")
	check_eq(_track(tr, "speed")["items"].size(), (data["ticks_per_frame"] as Array).size())
	check_eq(_track(tr, "events")["items"].size(), (data["events"] as Array).size())
	var basic := ScenarioLoader.load_data("res://scenarios/basic_forage.json")
	check_eq(TimelineModel.tracks(basic, _map(basic)).size() >= 8, true)

# --- hit testing ----------------------------------------------------------------------------

func _hit_track() -> Dictionary:
	return {"kind": "spans", "items": [
		{"t": 0.0, "until": 10.0}, {"t": 4.0, "until": 6.0}, {"t": 6.05, "until": 9.0},
	]}

func test_hit_until_beats_t() -> void:
	var tr := _hit_track()
	# 6.02 is within 0.1 of item 1's until (6) and item 2's t (6.05): the until edge wins.
	check_eq(TimelineModel.hit(tr, 6.02, 0.1), {"index": 1, "part": "until"})
	check_eq(TimelineModel.hit(tr, 10.05, 0.1), {"index": 0, "part": "until"})

func test_hit_nearest_t() -> void:
	var tr := {"kind": "points", "items": [{"t": 1.0, "until": -1.0}, {"t": 1.5, "until": -1.0}]}
	check_eq(TimelineModel.hit(tr, 1.3, 0.5), {"index": 1, "part": "t"})
	check_eq(TimelineModel.hit(tr, 1.1, 0.5), {"index": 0, "part": "t"})
	check_eq(TimelineModel.hit(tr, 1.25, 0.5), {"index": 1, "part": "t"}, "later wins ties")

func test_hit_body_shortest_and_miss() -> void:
	var tr := _hit_track()
	check_eq(TimelineModel.hit(tr, 5.0, 0.1), {"index": 1, "part": "body"}, "shortest span")
	check_eq(TimelineModel.hit(tr, 8.0, 0.1), {"index": 2, "part": "body"})
	check_eq(TimelineModel.hit(tr, 2.0, 0.1), {"index": 0, "part": "body"})
	check_eq(TimelineModel.hit(tr, 11.0, 0.1), {}, "miss")
	check_eq(TimelineModel.hit({"kind": "points", "items": [{"t": 1.0, "until": -1.0}]}, 5.0, 0.1), {})
	check_eq(TimelineModel.hit({"kind": "spans", "items": []}, 5.0, 0.1), {})

# --- edits ----------------------------------------------------------------------------------

func test_moved_plain() -> void:
	var data := _sample()
	var map := _map(data)
	var it := TimelineModel.moved(data, ["camera", 0], 2.345, map)
	check_near(it["t"], 2.35, 1e-9)
	check_eq(it["pos"], [540, 960])
	check_eq(it["zoom"], 3)
	check_eq(it.keys(), ["t", "pos", "zoom"], "key order kept")
	check_eq(data["camera"][0]["t"], 0, "data untouched")
	var whole := TimelineModel.moved(data, ["camera", 0], 3.0, map)
	check_eq(typeof(whole["t"]), TYPE_INT, "whole numbers stay ints")
	check_eq(TimelineModel.moved(data, ["camera", 0], -5.0, map)["t"], 0, "clamped")
	check_eq(TimelineModel.moved(data, ["camera", 9], 1.0, map), {}, "no such item")

func test_moved_span_keeps_length() -> void:
	var data := _sample()
	var map := _map(data)
	var it := TimelineModel.moved(data, ["render", "captions", 0], 5.0, map)
	check_near(it["t"], 5.0, 1e-9)
	check_near(it["until"], 7.0, 1e-9)
	var no_until := TimelineModel.moved(data, ["render", "captions", 1], 2.0, map)
	check(not no_until.has("until"), "an absent until stays absent")
	var clamped := TimelineModel.moved(data, ["render", "captions", 0], -3.0, map)
	check_near(clamped["t"], 0.0, 1e-9)
	check_near(clamped["until"], 2.0, 1e-9)

func test_moved_event_uses_sim_time() -> void:
	var data := {"ticks_per_frame": [{"t": 0, "tpf": 0.5}, {"t": 10, "tpf": 0.5, "jump": 100}], "events": [{"t": 5, "type": "rain", "duration": 6}]}
	var map := _map(data)
	var it := TimelineModel.moved(data, ["events", 0], 20.0, map)
	check_near(it["t"], 120.0, 1e-9)
	check_eq(it["type"], "rain")

func test_resized() -> void:
	var data := _sample()
	var it := TimelineModel.resized(data, ["render", "captions", 0], 6.5)
	check_near(it["until"], 6.5, 1e-9)
	check_eq(it["text"], "Hello\nsecond line")
	check_near(TimelineModel.resized(data, ["render", "captions", 0], 0.0)["until"], 1.1, 1e-9, "min length")
	check_near(TimelineModel.resized(data, ["render", "captions", 1], 20.0)["until"], 20.0, 1e-9, "adds until")
	check_eq(TimelineModel.resized(data, ["camera", 0], 6.0), {}, "not a span")
	check_eq(TimelineModel.resized(data, ["render", "fades", 0], 6.0), {}, "not a span")

func test_new_item_lists_and_defaults() -> void:
	var data := _sample()
	var map := _map(data)
	var cam := TimelineModel.new_item("camera", data, 7.0, map)
	check_eq(cam, {"path": ["camera"], "value": {"t": 7, "pos": [540, 960], "zoom": 1}, "insert": true})
	var sp := TimelineModel.new_item("speed", data, 2.5, map)
	check_eq(sp["path"], ["ticks_per_frame"])
	check_eq(sp["insert"], true)
	check_near(sp["value"]["tpf"], map.tpf_at(2.5), 0.01)
	check_eq(TimelineModel.new_item("layout", data, 1.0, map)["value"], {"t": 1, "mode": "split"})
	var cap := TimelineModel.new_item("captions", data, 1.5, map)
	check_eq(cap["path"], ["render", "captions"])
	check_eq(cap["value"], {"t": 1.5, "until": 5.5, "text": "Caption"})
	check_eq(TimelineModel.new_item("fades", data, 1.0, map)["value"], {"t": 1, "to": 1})
	check_eq(TimelineModel.new_item("grade", data, 1.0, map)["value"], {"t": 1, "brightness": 1})
	check_eq(TimelineModel.new_item("story_marker", data, 1.0, map)["value"], {"t": 1, "until": 6})
	var ev := TimelineModel.new_item("events", data, 4.0, map)
	check_eq(ev["path"], ["events"])
	check_eq(ev["value"], {"t": 8.8, "type": "rain", "duration": 6}, "sim time of the ramp: 2 * (2 + 0.15 * 16)")
	check_eq(TimelineModel.new_item("nope", data, 4.0, map), {})

func test_new_item_extra_and_split_camera() -> void:
	var data := {"camera": {"surface": [{"t": 0}]}}
	var map := _map(data)
	var s := TimelineModel.new_item("camera_surface", data, 3.0, map, {"zoom": 2, "smooth": 1})
	check_eq(s["path"], ["camera", "surface"])
	check_eq(s["insert"], true)
	check_eq(s["value"]["zoom"], 2)
	check_eq(s["value"]["smooth"], 1)
	var n := TimelineModel.new_item("camera_nest", data, 3.0, map)
	check_eq(n["path"], ["camera", "nest"])
	check_eq(n["insert"], false)
	check_eq(n["value"], [{"t": 3, "pos": [540, 960], "zoom": 1}])

func test_new_item_missing_lists() -> void:
	var data := {"ticks_per_frame": 2.0}
	var map := _map(data)
	var sp := TimelineModel.new_item("speed", data, 5.0, map)
	check_eq(sp["insert"], false)
	check_eq(sp["path"], ["ticks_per_frame"])
	check_eq(sp["value"], [{"t": 0, "tpf": 2}, {"t": 5, "tpf": 2}])
	var sp0 := TimelineModel.new_item("speed", data, 0.0, map)
	check_eq(sp0["value"], [{"t": 0, "tpf": 2}], "at 0 no duplicate point")
	var bare := TimelineModel.new_item("speed", {}, 5.0, _map({}))
	check_eq(bare["value"], [{"t": 0, "tpf": 0.5}, {"t": 5, "tpf": 0.5}])
	var cam := TimelineModel.new_item("camera", {}, 2.0, _map({}))
	check_eq(cam["insert"], false)
	check_eq(cam["value"], [{"t": 2, "pos": [540, 960], "zoom": 1}])
	var cap := TimelineModel.new_item("captions", {"render": "x"}, 2.0, _map({}))
	check_eq(cap["insert"], false)
	check_eq(cap["path"], ["render", "captions"])
	check_eq(cap["value"].size(), 1)

func test_camera_key_here() -> void:
	var k := TimelineModel.camera_key_here(Vector2(300.4, 700.6), Vector2(540, 960), Vector2(1080, 1920), 1.234)
	check_eq(k, {"t": 1.23, "pos": [300, 701], "zoom": 2})
	var wide := TimelineModel.camera_key_here(Vector2(0, 0), Vector2(1000, 500), Vector2(1080, 1920), 0.0)
	check_near(wide["zoom"], 3.84, 1e-9, "the larger ratio, so the frame fits inside the view")
	var third := TimelineModel.camera_key_here(Vector2(0, 0), Vector2(900, 1600), Vector2(1080, 1920), 0.0)
	check_near(third["zoom"], 1.2, 1e-9)
	check_near(TimelineModel.camera_key_here(Vector2(0, 0), Vector2(0, 0), Vector2(1080, 1920), 0.0)["zoom"], 1.0, 1e-9)

func test_tick_step() -> void:
	check_near(TimelineModel.tick_step(700.0), 0.1, 1e-9)
	check_near(TimelineModel.tick_step(100.0), 1.0, 1e-9)
	check_near(TimelineModel.tick_step(10.0), 10.0, 1e-9)
	check_near(TimelineModel.tick_step(1.0), 120.0, 1e-9)
	check_near(TimelineModel.tick_step(0.001), 600.0, 1e-9, "the last when none fits")
	check_near(TimelineModel.tick_step(20.0, 100.0), 5.0, 1e-9)

func test_snap_time() -> void:
	check_near(TimelineModel.snap_time(1.26, 0.5), 1.5, 1e-9)
	check_near(TimelineModel.snap_time(1.2, 0.5), 1.0, 1e-9)
	check_near(TimelineModel.snap_time(1.234, 0.0), 1.234, 1e-9)
	check_near(TimelineModel.snap_time(1.234, -1.0), 1.234, 1e-9)
