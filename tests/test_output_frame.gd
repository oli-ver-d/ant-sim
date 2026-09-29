extends TestCase
## M16b: the output frame (OutputFrame) and the frame maths of the renderers
## that used to assume 1080x1920: safe zones, split layout, captions and the
## nest readout. The default frame must give exactly the old rects.

func _frame(w: int, h: int, zones: String = "tiktok") -> OutputFrame:
	return OutputFrame.new(Vector2i(w, h), zones)

func test_defaults() -> void:
	var f := OutputFrame.from_scenario({})
	check_eq(f.size, Vector2i(1080, 1920), "default size")
	check_eq(f.safe_zones, "tiktok", "default safe zones")
	check_eq(f.scale(), 1.0, "default scale")
	check(not f.is_landscape(), "portrait")

func test_output_section() -> void:
	var f := OutputFrame.from_scenario({"output": {"size": [1920, 1080], "safe_zones": "none"}})
	check_eq(f.size, Vector2i(1920, 1080), "size from output")
	check_eq(f.safe_zones, "none", "safe zones from output")
	check(f.is_landscape(), "landscape")
	# JSON numbers are floats.
	f = OutputFrame.from_scenario({"output": {"size": [1080.0, 1080.0]}})
	check_eq(f.size, Vector2i(1080, 1080), "float size")
	check_eq(f.safe_zones, "tiktok", "safe zones default")

func test_size_override() -> void:
	var data := {"output": {"size": [1080, 1080], "safe_zones": "youtube_shorts"}}
	var f := OutputFrame.from_scenario(data, "1920x1080")
	check_eq(f.size, Vector2i(1920, 1080), "override wins")
	check_eq(f.safe_zones, "youtube_shorts", "override keeps safe zones")
	check_eq(OutputFrame.from_scenario({}, "landscape").size, Vector2i(1920, 1080), "preset name")
	check_eq(OutputFrame.from_scenario({}, "2160X3840").size, Vector2i(2160, 3840), "upper-case X")

func test_bad_values_fall_back() -> void:
	check_eq(OutputFrame.from_scenario({}, "1081x1920").size, Vector2i(1080, 1920), "odd width")
	check_eq(OutputFrame.from_scenario({}, "32x32").size, Vector2i(1080, 1920), "too small")
	check_eq(OutputFrame.from_scenario({}, "abc").size, Vector2i(1080, 1920), "not a size")
	check_eq(OutputFrame.from_scenario({"output": {"size": [1080]}}).size, Vector2i(1080, 1920), "one number")
	var f := OutputFrame.from_scenario({"output": {"size": [1920, 1080]}}, "99x99")
	check_eq(f.size, Vector2i(1920, 1080), "bad override keeps the scenario's size")
	check_eq(OutputFrame.from_scenario({"output": {"safe_zones": "myspace"}}).safe_zones, "tiktok", "unknown preset")
	check_eq(OutputFrame.parse_size("1920x"), Vector2i.ZERO, "parse_size of a half size")
	check(OutputFrame.valid_size(Vector2i(1080, 1350)), "4:5 is valid")
	check(not OutputFrame.valid_size(Vector2i(10000, 1080)), "too large")

## The TikTok zones on the default frame, as the old hard-coded SafeZones.
func test_default_safe_zones_unchanged() -> void:
	var f := OutputFrame.new()
	var m := f.margins()
	check_eq(m["top"], 150.0, "top")
	check_eq(m["bottom"], 400.0, "bottom")
	check_eq(m["right"], 120.0, "right")
	check_eq(m["left"], 0.0, "left")
	check_eq(f.safe_rect(), Rect2(0, 150, 960, 1370), "safe rect")
	var rects := f.unsafe_rects()
	check_eq(rects.size(), 3, "three shaded areas")
	check_eq(rects[0], Rect2(0, 0, 1080, 150), "top area")
	check_eq(rects[1], Rect2(0, 1520, 1080, 400), "bottom area")
	check_eq(rects[2], Rect2(960, 150, 120, 1370), "right area")

func test_safe_zone_presets() -> void:
	check_eq(_frame(1080, 1920, "youtube_shorts").safe_rect(), Rect2(0, 120, 890, 1440), "shorts portrait")
	check_eq(_frame(1920, 1080).safe_rect(), Rect2(0, 150, 1800, 530), "tiktok landscape (same pixels)")
	check_eq(_frame(1080, 1080).safe_rect(), Rect2(0, 150, 960, 530), "tiktok square")
	var none := _frame(1920, 1080, "none")
	check(none.unsafe_rects().is_empty(), "none: nothing shaded")
	check_eq(none.safe_rect(), Rect2(0, 0, 1920, 1080), "none: the whole frame")

func test_scale_by_short_side() -> void:
	check_eq(_frame(1920, 1080).scale(), 1.0, "landscape")
	check_eq(_frame(1080, 1080).scale(), 1.0, "square")
	check_eq(_frame(2160, 3840).scale(), 2.0, "4k portrait")
	check_eq(_frame(3840, 2160).scale(), 2.0, "4k landscape")
	check_eq(_frame(2160, 3840).safe_rect(), Rect2(0, 300, 1920, 2740), "4k safe rect scaled")

func test_default_split_unchanged() -> void:
	var size := Vector2(1080, 1920)
	for spec: Dictionary in [{}, {"surface": "top", "ratio": 0.5}]:
		var r := SplitLayout.split_rects(size, spec)
		check_eq(r[0], Rect2(0, 0, 1080, 960), "surface on top %s" % spec)
		check_eq(r[1], Rect2(0, 960, 1080, 960), "nest below %s" % spec)
		check_eq(SplitLayout.seam_rect(r[0], r[1]), Rect2(0, 957.5, 1080, 5), "seam %s" % spec)
	var b := SplitLayout.split_rects(size, {"surface": "bottom", "ratio": 0.4})
	check_eq(b[0], Rect2(0, 1152, 1080, 768), "surface at the bottom")
	check_eq(b[1], Rect2(0, 0, 1080, 1152), "nest on top")
	check_eq(SplitLayout.seam_rect(b[0], b[1]), Rect2(0, 1149.5, 1080, 5), "seam, surface at the bottom")
	check_eq(SplitLayout.split_rects(size, {"ratio": 0.95})[0].size.y, 1536.0, "ratio clamped to 0.8")
	check_eq(SplitLayout.split_rects(size, {"ratio": 0.05})[0].size.y, 384.0, "ratio clamped to 0.2")

func test_side_by_side_split() -> void:
	var size := Vector2(1920, 1080)
	var l := SplitLayout.split_rects(size, {"surface": "left"})
	check_eq(l[0], Rect2(0, 0, 960, 1080), "surface left")
	check_eq(l[1], Rect2(960, 0, 960, 1080), "nest right")
	check_eq(SplitLayout.seam_rect(l[0], l[1]), Rect2(957.5, 0, 5, 1080), "vertical seam")
	var r := SplitLayout.split_rects(size, {"surface": "right", "ratio": 0.4})
	check_eq(r[0], Rect2(1152, 0, 768, 1080), "surface right, 40% of the width")
	check_eq(r[1], Rect2(0, 0, 1152, 1080), "nest left")
	check_eq(SplitLayout.seam_rect(r[0], r[1]), Rect2(1149.5, 0, 5, 1080), "seam, surface right")
	var t := SplitLayout.split_rects(size, {"surface": "top"})
	check_eq(t[0], Rect2(0, 0, 1920, 540), "stacked in landscape")
	check_eq(t[1], Rect2(0, 540, 1920, 540), "nest below in landscape")

func test_default_captions_unchanged() -> void:
	var f := OutputFrame.new()
	check_eq(Presentation.caption_column(f), Vector2(130, 820), "caption column")
	check_eq(Presentation.caption_top(f, "top", 100.0), 210.0, "top")
	check_eq(Presentation.caption_top(f, "bottom", 100.0), 1370.0, "bottom")
	check_eq(Presentation.caption_top(f, "middle", 100.0), 910.0, "middle")

func test_captions_in_other_frames() -> void:
	var land := _frame(1920, 1080)
	check_eq(Presentation.caption_column(land), Vector2(550, 820), "landscape: portrait width, centred")
	check_eq(Presentation.caption_top(land, "bottom", 100.0), 1080.0 - 400.0 - 50.0 - 100.0, "landscape bottom")
	check_eq(Presentation.caption_column(_frame(1080, 1080)), Vector2(130, 820), "square")
	var big := _frame(2160, 3840)
	check_eq(Presentation.caption_column(big), Vector2(260, 1640), "4k: scaled")
	check_eq(Presentation.caption_top(big, "top", 100.0), 420.0, "4k top")
	var none := _frame(1080, 1920, "none")
	check_eq(Presentation.caption_top(none, "top", 100.0), 60.0, "no safe zones: top")
	check_eq(Presentation.caption_top(none, "bottom", 100.0), 1770.0, "no safe zones: bottom")

func test_stats_origin() -> void:
	var f := OutputFrame.new()
	check_eq(SplitLayout.stats_origin(f, Rect2(0, 960, 1080, 960)), Vector2(40, 984), "split, nest below")
	check_eq(SplitLayout.stats_origin(f, Rect2(0, 0, 1080, 1920)), Vector2(40, 174), "nest full screen")
	check_eq(SplitLayout.stats_origin(_frame(1920, 1080), Rect2(960, 0, 960, 1080)), Vector2(1000, 174), "nest on the right")

func test_window_size() -> void:
	check_eq(_frame(1080, 1920).window_size(Vector2i(1920, 1032)), Vector2i(540, 960), "portrait: half")
	check_eq(_frame(1920, 1080).window_size(Vector2i(1920, 1032)), Vector2i(960, 540), "landscape: half")
	check_eq(_frame(1080, 1920).window_size(Vector2i(800, 600)), Vector2i(338, 600), "shrunk to fit")
	check_eq(_frame(2160, 3840).window_size(Vector2i(2560, 1400)), Vector2i(788, 1400), "4k fits the height")
	check_eq(_frame(1080, 1920).window_size(Vector2i.ZERO), Vector2i(540, 960), "unknown screen")

## The frame is render only: the same run whatever the output size.
func test_frame_does_not_change_the_run() -> void:
	var config: SimConfig = load("res://sim/default_config.tres")
	var registry := Registry.create_default()
	var data := ScenarioLoader.load_data("basic_forage")
	var framed := data.duplicate(true)
	framed["output"] = {"size": [1920, 1080], "safe_zones": "none"}
	var a := ScenarioLoader.build(data, registry, config)
	var b := ScenarioLoader.build(framed, registry, config)
	for t in 20:
		a.step()
		b.step()
	check_eq(b.state_hash(), a.state_hash(), "state hash with an output section")
