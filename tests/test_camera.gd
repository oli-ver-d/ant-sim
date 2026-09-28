extends TestCase
## Camera storytelling (CameraDirector / ScenarioPlayer): following one ant
## across layers, "same", brood records through their stages, smoothing and
## time jumps. Render side only: state hashes must not change.

const DIG_DEMO := "res://tests/fixtures/scenarios/dig_demo.json"

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root

## dig_demo without its warmup, one whole tick per frame, played full screen.
func _dig_data(surface_frames: Array, nest_frames: Array = []) -> Dictionary:
	var data := ScenarioLoader.load_data(DIG_DEMO)
	data["warmup"] = 0
	data["ticks_per_frame"] = 1
	data["camera"] = {"surface": surface_frames, "nest": nest_frames}
	data["render"] = {"layout": {"mode": "surface", "colony": 0}}
	return data

func _player(data: Dictionary) -> ScenarioPlayer:
	var player := ScenarioPlayer.new()
	_root().add_child(player)
	player.setup_data(data)
	return player

func _frames(player: ScenarioPlayer, n: int) -> void:
	for f in n:
		player.advance(1.0 / ScenarioPlayer.VIDEO_FPS)

## Frames until ant i is out of its portal (at most `limit`).
func _through_portal(player: ScenarioPlayer, i: int, limit: int = 120) -> void:
	for f in limit:
		if not player.sim.in_transit(i):
			break
		_frames(player, 1)
	_frames(player, 2)

func test_smoothing_per_keyframe() -> void:
	var a := Vector2.ZERO
	var b := Vector2(100, 0)
	check_eq(CameraDirector._smooth(a, b, 1.0 / 60.0, 0.0), b, "0 locks on")
	var fast := CameraDirector._smooth(a, b, 1.0 / 60.0, 0.35)
	var slow := CameraDirector._smooth(a, b, 1.0 / 60.0, 2.0)
	check(slow.x < fast.x and slow.x > 0.0, "larger smoothing moves less (%s vs %s)" % [slow.x, fast.x])

## dig_demo's ants start in the nest: a layout showing it, with nest keyframes.
func _nest_data(nest_frames: Array, layout_mode: String = "nest") -> Dictionary:
	var data := _dig_data([{"t": 0, "pos": [540, 1100], "zoom": 2}], nest_frames)
	data["render"] = {"layout": {"mode": layout_mode, "colony": 0}}
	return data

## The portal between the surface and the nest's layer.
func _entrance(sim: Simulation, nest_layer: int) -> Portal:
	for p in sim.portals:
		if p.connects(0) and p.connects(nest_layer) and p.open:
			return p
	return null

## A follow {"ant": "same"} keeps the ant the previous keyframe chose.
func test_follow_same_ant() -> void:
	var player := _player(_nest_data([
		{"t": 0, "follow": {"near": [640, 640]}, "zoom": 3},
		{"t": 0.2, "follow": {"ant": "same"}, "zoom": 4},
		{"t": 0.4, "follow": {"near": [900, 550]}, "zoom": 4},
	]))
	_frames(player, 30)
	var cam := player.nest_camera
	var first := cam.followed_ant(0)
	check(first >= 0, "first keyframe chose an ant")
	check_eq(cam.followed_ant(1), first, "same ant")
	_frames(player, 15)
	check(cam.followed_ant(2) >= 0 and cam.followed_ant(2) != first, "a later near choice picks another")
	player.queue_free()

## An "across" follow keeps its ant through a portal: the surface camera takes
## it when it comes up (switching the layout to the surface), and back down
## the nest camera has it again (switching back to the nest).
func test_across_follow_through_portals() -> void:
	var player := _player(_nest_data([
		{"t": 0, "follow": {"near": [640, 640], "across": true, "switch_mode": true}, "zoom": 4, "smoothing": 0},
	]))
	check_eq(player.mode(), "nest", "starts in the nest")
	_frames(player, 2)
	var sim := player.sim
	var ant := player.nest_camera.followed_ant(0)
	check(ant >= 0 and sim.layer[ant] == player.nest_layer(), "chose an ant in the nest")
	var portal := _entrance(sim, player.nest_layer())
	check(portal != null, "an open entrance")
	if ant < 0 or portal == null:
		player.queue_free()
		return
	check(sim.enter_portal(ant, portal), "ant goes up")
	_through_portal(player, ant)
	check_eq(int(sim.layer[ant]), 0, "ant on the surface")
	check_eq(player.mode(), "surface", "switched to the surface")
	check_eq(player.camera.carried_ant(), ant, "surface camera took the ant")
	var d := player.camera.position.distance_to(sim.shown_pos[ant])
	check(d < 40.0, "surface camera on the ant (%.1f away)" % d)
	check_eq(player.camera.zoom.x, 4.0, "with the keyframe's zoom")
	check_eq(int(player.camera.story.get("ant", -1)), ant, "the story follows it")
	# And back down.
	# (It may be on its way down by itself already.)
	if sim.in_transit(ant) or sim.enter_portal(ant, portal):
		_through_portal(player, ant)
		check_eq(int(sim.layer[ant]), player.nest_layer(), "ant back in the nest")
		check_eq(player.mode(), "nest", "switched back to the nest")
		check_eq(player.camera.carried_ant(), -1, "surface camera let go")
		d = player.nest_camera.position.distance_to(sim.shown_pos[ant])
		check(d < 40.0, "nest camera on the ant (%.1f away)" % d)
	else:
		check(false, "ant couldn't go back down")
	player.queue_free()

## Without switch_mode the layout stays; in split mode the surface part takes
## the ant while the nest part keeps its keyframe.
func test_across_follow_in_split_hands_to_other_part() -> void:
	var player := _player(_nest_data([{"t": 0, "follow": {"near": [640, 640], "across": true}, "zoom": 3}], "split"))
	_frames(player, 2)
	var sim := player.sim
	var ant := player.nest_camera.followed_ant(0)
	var portal := _entrance(sim, player.nest_layer())
	if ant < 0 or portal == null or not sim.enter_portal(ant, portal):
		check(false, "no ant to send up")
		player.queue_free()
		return
	_through_portal(player, ant)
	check_eq(player.mode(), "split", "layout unchanged")
	check_eq(player.camera.carried_ant(), ant, "surface part took the ant")
	check_eq(player.nest_camera.carried_ant(), -1, "nest part still plays its own keyframes")
	player.queue_free()

## A follow on the nest camera chooses among ants on the nest's layer, by
## state too.
func test_nest_follow_chooses_on_nest_layer() -> void:
	var player := _player(_nest_data([{"t": 0, "follow": {"near": [640, 640], "state": "dig"}, "zoom": 4}]))
	_frames(player, 40)
	var sim := player.sim
	var ant := player.nest_camera.followed_ant(0)
	check(ant >= 0, "chose an ant")
	if ant >= 0:
		check_eq(int(sim.layer[ant]), player.nest_layer(), "on the nest layer")
	player.queue_free()


## A brood follow keeps the same record through its stages, then follows
## the ant it becomes.
func test_follow_brood_through_stages_to_ant() -> void:
	var data := ScenarioLoader.load_data("colony_founding")
	var brood_params: Dictionary = data["colonies"][0]["nest_params"]["brood"]
	brood_params.merge({"egg": 3, "larva": 5, "pupa": 4, "callow": 1, "initial": {"egg": 2}}, true)
	var sim := ScenarioLoader.build(data, _registry, _config)
	var nest := sim.colonies[0].nest as ColonyNest
	var brood := nest.brood
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	_root().add_child(vp)
	var cam := CameraDirector.new()
	vp.add_child(cam)
	cam.setup(sim, [{"t": 0, "follow": {"brood": "first", "stage": "egg"}, "zoom": 4, "smoothing": 0}], nest.underground_layer)
	var dt := 1.0 / ScenarioPlayer.VIDEO_FPS
	cam.update_camera(0.0, dt)
	var id := cam.followed_brood(0)
	check(id >= 0, "chose a brood record")
	check_eq(brood.stage[brood.index_of(id)], Brood.Stage.EGG, "an egg")
	check_eq(int(cam.story.get("brood", -1)), id, "the story follows it")
	var stages := {}
	var ant := -1
	var t := 0.0
	for tick in 60 * 30:
		sim.step()
		t += 1.0 / 30.0
		cam.update_camera(t, 1.0 / 30.0)
		var rec := brood.index_of(id)
		if rec >= 0:
			check_eq(cam.followed_brood(0), id, "same id")
			stages[int(brood.stage[rec])] = true
			var d := cam.position.distance_to(brood.pos[rec])
			if d > 60.0 and brood.carrier[rec] < 0:
				check(false, "camera %.0f away from the brood" % d)
				break
		elif cam.followed_ant(0) >= 0:
			ant = cam.followed_ant(0)
			break
	check(stages.has(Brood.Stage.LARVA) and stages.has(Brood.Stage.PUPA), "seen as larva and pupa (%s)" % [stages.keys()])
	check(ant >= 0, "followed the ant it became")
	if ant >= 0:
		check_eq(brood.emerged_as(id), ant, "the emergence log's ant")
		check_eq(cam.followed_brood(0), -1, "no longer brood")
		check_eq(int(cam.story.get("ant", -1)), ant, "story now the ant")
	check_eq(brood.emerged_as(-5), Brood.NOT_EMERGED, "unknown id")
	vp.queue_free()

## A "jump" on a ticks_per_frame point runs that many sim seconds in one frame.
func test_time_jump() -> void:
	var data := _dig_data([{"t": 0, "pos": [540, 1100], "zoom": 2}])
	data["ticks_per_frame"] = [{"t": 0, "tpf": 1}, {"t": 0.5, "tpf": 1, "jump": 10}]
	var player := _player(data)
	_frames(player, 29)
	check_eq(player.sim.completed_ticks(), 29, "before the jump")
	_frames(player, 1)
	check_eq(player.sim.completed_ticks(), 30 + 300, "jumped 10 s")
	_frames(player, 30)
	check_eq(player.sim.completed_ticks(), 360, "once")
	player.queue_free()

## Story cameras (across, same, brood, jump) don't change the simulation.
func test_story_camera_keeps_hashes() -> void:
	var data := _nest_data([
		{"t": 0, "follow": {"near": [640, 640], "across": true, "switch_mode": true}, "zoom": 4},
		{"t": 0.5, "follow": {"ant": "same", "across": true}, "zoom": 3, "smoothing": 1.5},
	], "split")
	data["camera"]["surface"] = [{"t": 0, "follow": {"ant": "same"}, "zoom": 4}]
	data["ticks_per_frame"] = [{"t": 0, "tpf": 1}, {"t": 1, "tpf": 1, "jump": 2}]
	var player := _player(data)
	_frames(player, 90)
	var plain := ScenarioLoader.build(data, _registry, _config)
	for t in player.sim.completed_ticks():
		plain.step()
	check_eq(player.sim.completed_ticks(), 90 + 60, "ran with the jump")
	check_eq(player.sim.state_hash(), plain.state_hash(), "same hash as a plain run")
	player.queue_free()

func test_story_marker_alpha() -> void:
	var w := StoryMarker.parse([{"t": 10, "until": 20, "fade": 2.0}])
	check_eq(StoryMarker.alpha_at(w, 9.0), 0.0, "0 before t")
	check_eq(StoryMarker.alpha_at(w, 21.0), 0.0, "0 after until")
	check_eq(StoryMarker.alpha_at(w, 15.0), 1.0, "1 in the middle")
	check(absf(StoryMarker.alpha_at(w, 11.0) - 0.5) < 0.001, "0.5 halfway up the fade in")
	check(absf(StoryMarker.alpha_at(w, 19.0) - 0.5) < 0.001, "0.5 halfway down the fade out")
	var two := StoryMarker.parse([{"t": 10, "until": 20, "fade": 2.0}, {"t": 12, "until": 30, "fade": 2.0}])
	check_eq(StoryMarker.alpha_at(two, 19.0), 1.0, "overlapping windows take the max")
	var open := StoryMarker.parse([{"t": 5, "fade": 1.0}])
	check_eq(StoryMarker.alpha_at(open, 1000.0), 1.0, "no until is open-ended")
	check_eq(StoryMarker.alpha_at(open, 4.0), 0.0, "but not before t")
	check_eq(StoryMarker.parse(null).size(), 0, "no spec, no windows")

func test_story_pos_follows_story() -> void:
	var player := _player(_nest_data([
		{"t": 0, "follow": {"near": [640, 640]}, "zoom": 3, "smoothing": 0},
	]))
	_frames(player, 30)
	var cam := player.nest_camera
	var ant := cam.followed_ant(0)
	check(ant >= 0, "followed an ant")
	var p: Variant = cam.story_pos()
	check(p != null, "story_pos on the nest camera")
	if p != null and ant >= 0:
		var sim := player.sim
		var expect: Vector2 = sim.prev_pos[ant].lerp(sim.shown_pos[ant], cam.alpha)
		check((p as Vector2).distance_to(expect) < 1.0, "close to the ant (%.2f away)" % (p as Vector2).distance_to(expect))
	check(player.camera.story_pos() == null, "null on the surface camera (other layer)")
	player.queue_free()

func test_story_pos_follows_brood() -> void:
	var data := ScenarioLoader.load_data("colony_founding")
	var brood_params: Dictionary = data["colonies"][0]["nest_params"]["brood"]
	brood_params.merge({"egg": 3, "larva": 5, "pupa": 4, "callow": 1, "initial": {"egg": 2}}, true)
	var sim := ScenarioLoader.build(data, _registry, _config)
	var nest := sim.colonies[0].nest as ColonyNest
	var brood := nest.brood
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	_root().add_child(vp)
	var cam := CameraDirector.new()
	vp.add_child(cam)
	cam.setup(sim, [{"t": 0, "follow": {"brood": "first", "stage": "egg"}, "zoom": 4, "smoothing": 0}], nest.underground_layer)
	cam.update_camera(0.0, 1.0 / ScenarioPlayer.VIDEO_FPS)
	var id := cam.followed_brood(0)
	check(id >= 0, "chose a brood record")
	var rec := brood.index_of(id)
	var p: Variant = cam.story_pos()
	check(p != null, "story_pos for brood")
	if p != null and rec >= 0 and brood.carrier[rec] < 0:
		check_eq(p as Vector2, brood.pos[rec], "the tracked brood position")
	vp.queue_free()

func test_story_marker_created() -> void:
	var data := _nest_data([{"t": 0, "pos": [640, 640], "zoom": 3}], "surface")
	data["render"]["story_marker"] = [{"t": 1, "until": 5}]
	var player := _player(data)
	check_eq(player.markers.size(), 1, "one marker after setup")
	player.set_mode("nest")
	check_eq(player.markers.size(), 2, "two once the nest layout is on")
	check_eq(player.layout.highlight, true, "highlight defaults on")
	player.queue_free()

	var plain := _player(_nest_data([{"t": 0, "pos": [640, 640], "zoom": 3}]))
	check_eq(plain.markers.size(), 0, "no key, no markers")
	plain.queue_free()

	var d2 := _nest_data([{"t": 0, "pos": [640, 640], "zoom": 3}])
	d2["render"]["layout"]["highlight"] = false
	var off := _player(d2)
	check(off.layout != null and off.layout.highlight == false, "layout.highlight false")
	off.queue_free()

## The layout schedule still switches modes at its points.
func test_mode_schedule_applies_at_points() -> void:
	var data := _dig_data([{"t": 0, "pos": [540, 1100], "zoom": 2}])
	data["render"] = {"layout": {"colony": 0, "modes": [{"t": 0, "mode": "split"}, {"t": 0.5, "mode": "nest"}]}}
	var player := _player(data)
	_frames(player, 10)
	check_eq(player.mode(), "split", "first point")
	player.set_mode("surface")
	_frames(player, 5)
	check_eq(player.mode(), "surface", "held between points")
	_frames(player, 30)
	check_eq(player.mode(), "nest", "next point")
	player.queue_free()
