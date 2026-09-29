extends TestCase
## M16f: editor ground material swatches and the flat materials image.

func _ground(data: Variant) -> GroundMap:
	return GroundMap.from_data(data, Vector2(1080, 1920), 1)

func test_distinct_colours() -> void:
	var seen: Array[Color] = []
	for m: String in GroundMap.MATERIALS:
		check(GroundSwatches.COLORS.has(m), "colour for " + m)
		var c := GroundSwatches.color(m)
		check(not seen.has(c), "distinct colour for " + m)
		seen.append(c)
	check_eq(GroundSwatches.color("nonsense"), Color(1, 0, 1), "unknown is magenta")

func test_icon() -> void:
	var tex := GroundSwatches.icon("moss")
	check_eq(tex.get_width(), 14)
	check_eq(tex.get_height(), 14)
	check(GroundSwatches.icon("moss") == tex, "cached")
	check_eq(GroundSwatches.icon("sand", 20).get_width(), 20)
	var img := tex.get_image()
	var px := img.get_pixel(7, 7)
	var want := GroundSwatches.color("moss")
	check(absf(px.r - want.r) < 0.01 and absf(px.g - want.g) < 0.01 and absf(px.b - want.b) < 0.01, "fill")
	check(img.get_pixel(0, 0) != GroundSwatches.color("moss"), "border differs")

func test_image_base() -> void:
	var g := _ground("sand")
	var img := GroundSwatches.image(g)
	check_eq(img.get_size(), g.size, "one pixel per cell")
	var want := GroundSwatches.color("sand")
	for p: Vector2i in [Vector2i(0, 0), Vector2i(g.size.x / 2, g.size.y / 2), g.size - Vector2i.ONE]:
		var c := img.get_pixelv(p)
		check(absf(c.r - want.r) < 0.01 and absf(c.g - want.g) < 0.01 and absf(c.b - want.b) < 0.01, "sand at %s" % p)

func test_image_region() -> void:
	var g := _ground({"base": "soil", "regions": [
		{"material": "moss", "shape": "circle", "center": [540, 960], "radius": 200, "soft": 0}]})
	var img := GroundSwatches.image(g)
	var moss := GroundSwatches.color("moss")
	var soil := GroundSwatches.color("soil")
	var mid := img.get_pixelv(Vector2i(int(540 / GroundMap.TEXEL), int(960 / GroundMap.TEXEL)))
	check(absf(mid.g - moss.g) < 0.01 and absf(mid.r - moss.r) < 0.01, "moss at centre: %s" % mid)
	var far := img.get_pixelv(Vector2i(2, 2))
	check(absf(far.g - soil.g) < 0.01 and absf(far.r - soil.r) < 0.01, "soil far away: %s" % far)

func test_image_speed() -> void:
	var g := _ground("soil")
	var t := Time.get_ticks_msec()
	GroundSwatches.image(g)
	var ms := Time.get_ticks_msec() - t
	print("GroundSwatches.image 1080x1920: %d ms" % ms)
	check(ms < 100, "image took %d ms" % ms)

func test_is_material_choice() -> void:
	var all := PackedStringArray(GroundMap.MATERIALS)
	check(GroundSwatches.is_material_choice(all), "all")
	var rev := all.duplicate()
	rev.reverse()
	check(GroundSwatches.is_material_choice(rev), "any order")
	check(not GroundSwatches.is_material_choice(PackedStringArray(["soil", "sand"])), "subset")
	check(not GroundSwatches.is_material_choice(PackedStringArray(["a", "b", "c", "d", "e", "f"])), "other names")
