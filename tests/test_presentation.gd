extends TestCase
## Presentation (render.captions / fades / grade): ramps and caption timing.

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-4

func test_wanted_only_with_presentation_keys() -> void:
	check(not Presentation.wanted({}), "empty render section")
	check(not Presentation.wanted({"pheromones": false}), "other keys only")
	check(Presentation.wanted({"captions": []}), "captions")
	check(Presentation.wanted({"fades": []}), "fades")
	check(Presentation.wanted({"grade": []}), "grade")

func test_caption_fades_in_and_out() -> void:
	var c := {"t": 2.0, "until": 6.0, "fade": 1.0, "text": "x"}
	check_eq(Presentation.caption_alpha(c, 1.9), 0.0, "before")
	check(_near(Presentation.caption_alpha(c, 2.5), 0.5), "half way in")
	check_eq(Presentation.caption_alpha(c, 4.0), 1.0, "held")
	check(_near(Presentation.caption_alpha(c, 5.75), 0.25), "fading out")
	check_eq(Presentation.caption_alpha(c, 6.1), 0.0, "after")

func test_fade_ramps_between_points() -> void:
	var p := Presentation.new()
	p.setup({"fades": [{"t": 4, "to": 1, "ease": "linear"}, {"t": 2, "to": 0}, {"t": 6, "to": 0, "ease": "linear"}]})
	check_eq(float(p.fade_at(0.0)["to"]), 0.0, "before the first point")
	check(_near(float(p.fade_at(3.0)["to"]), 0.5), "linear half way (points sorted)")
	check_eq(float(p.fade_at(4.0)["to"]), 1.0, "at the point")
	check(_near(float(p.fade_at(5.0)["to"]), 0.5), "back down")
	check_eq(float(p.fade_at(9.0)["to"]), 0.0, "after the last point")
	p.free()

func test_grade_carries_missing_keys_and_ramps_arrays() -> void:
	var p := Presentation.new()
	p.setup({"grade": [
		{"t": 0, "tint": [1, 1, 1], "vignette": 0.2},
		{"t": 10, "tint": [1, 0.6, 0.4], "ease": "linear"},
		{"t": 20, "brightness": 0.5, "ease": "linear"},
	]})
	var g := p.grade_at(5.0)
	check(_near(float(g["tint"][1]), 0.8), "tint ramps")
	check(_near(float(g["vignette"]), 0.2), "vignette carried over")
	check(_near(float(g["saturation"]), 1.0), "defaults fill unset keys")
	var late := p.grade_at(15.0)
	check(_near(float(late["tint"][2]), 0.4), "tint carried to the later point")
	check(_near(float(late["brightness"]), 0.75), "brightness ramps")
	p.free()

func test_in_out_easing_is_used_by_default() -> void:
	var p := Presentation.new()
	p.setup({"fades": [{"t": 0, "to": 0}, {"t": 4, "to": 1}]})
	check(float(p.fade_at(1.0)["to"]) < 0.25, "slow start (eased)")
	check(_near(float(p.fade_at(2.0)["to"]), 0.5), "symmetric")
	p.free()

func test_scenario_player_builds_presentation_only_when_asked() -> void:
	var player := ScenarioPlayer.new()
	player.setup("basic_forage")
	check(player.presentation == null, "no presentation without the keys")
	player.free()
