extends TestCase
## M15b: ground materials (GroundMap) and ground cover decals
## (GroundCoverRenderer): built from the scenario's "ground" entry, with their
## own seeds, never touching the simulation's RNG or its hash.

var _config: SimConfig = load("res://sim/default_config.tres")
var _registry := Registry.create_default()

const GROUND := {
	"base": "soil",
	"regions": [
		{"material": "sand", "shape": "circle", "center": [300, 400], "radius": 200, "soft": 40},
		{"material": "gravel", "shape": "rect", "rect": [600, 100, 400, 300], "soft": 30},
		{"material": "moss", "shape": "polygon", "points": [[100, 900], [400, 850], [450, 1150], [120, 1200]]},
		{"material": "dry", "shape": "circle", "center": [800, 1000], "radius": 150},
		{"material": "litter", "shape": "rect", "rect": [0, 1400, 1080, 520], "noise": {"scale": 150, "cover": 0.5}},
	],
}

func _data(ground: Variant = GROUND, seed_value: int = 3) -> Dictionary:
	var d := {"seed": seed_value,
		"colonies": [{"species": "leafcutter", "nest": [540, 1300], "population": {"minim": 30, "media": 130, "major": 10}}],
		"food": [{"type": "food_pile", "pos": [540, 850], "radius": 26, "amount": 400}]}
	if ground != null:
		d["ground"] = ground
	return d

func _map() -> GroundMap:
	return GroundMap.from_data(GROUND, Vector2(1080, 1920), 3)

func test_no_ground_entry_means_plain_soil() -> void:
	var sim := ScenarioLoader.build(_data(null), _registry, _config)
	check(sim.ground == null, "no map without a ground entry")
	var sand := ScenarioLoader.build(_data("sand"), _registry, _config)
	check_eq(sand.ground.weight_at("sand", Vector2(10, 10)), 1.0, "string shorthand sets the base")

func test_regions_paint_their_material() -> void:
	var map := _map()
	check_eq(map.weight_at("sand", Vector2(300, 400)), 1.0, "sand at the circle's centre")
	check_eq(map.weight_at("soil", Vector2(300, 400)), 0.0, "no soil under the sand")
	check_eq(map.weight_at("sand", Vector2(300, 700)), 0.0, "no sand well outside it")
	check_eq(map.weight_at("gravel", Vector2(800, 250)), 1.0, "gravel in the rect")
	check_eq(map.weight_at("moss", Vector2(270, 1020)), 1.0, "moss in the polygon")
	check_eq(map.weight_at("dry", Vector2(800, 1000)), 1.0, "dry clay in its circle")
	check_eq(map.weight_at("soil", Vector2(540, 700)), 1.0, "soil elsewhere")
	# Soft edge: partly sand just at the circle's radius.
	var edge := map.weight_at("sand", Vector2(300, 600))
	check(edge > 0.0 and edge < 1.0, "soft edge (%.2f)" % edge)

func test_weights_sum_to_one() -> void:
	var map := _map()
	var worst := 0.0
	for i in map.size.x * map.size.y:
		var s := 0.0
		for m in GroundMap.MATERIALS.size():
			s += map.weights[m][i]
		worst = maxf(worst, absf(s - 1.0))
	check(worst < 1e-4, "weights sum to 1 (worst %.6f)" % worst)

func test_noise_region_covers_its_fraction() -> void:
	var map := GroundMap.from_data({"base": "soil", "regions": [
		{"material": "litter", "noise": {"scale": 150, "cover": 0.3, "soft": 0.0001}}]}, Vector2(1080, 1920), 3)
	var covered := 0
	var n := map.size.x * map.size.y
	for i in n:
		if map.weights[GroundMap.material_index("litter")][i] > 0.5:
			covered += 1
	var frac := float(covered) / n
	check(absf(frac - 0.3) < 0.02, "litter covers ~30%% (%.3f)" % frac)

func test_same_seed_same_map() -> void:
	var a := _map()
	var b := _map()
	for m in GroundMap.MATERIALS.size():
		check_eq(a.weights[m], b.weights[m], "%s weights" % GroundMap.MATERIALS[m])
	var c := GroundMap.from_data(GROUND, Vector2(1080, 1920), 4)
	check(c.weights[4] != a.weights[4], "another seed gives other litter patches")

func test_material_textures() -> void:
	var map := _map()
	var a := map.material_a()
	var b := map.material_b()
	check_eq(a.get_size(), map.size, "texture A size")
	check_eq(a.get_format(), Image.FORMAT_RGBA8, "texture A format")
	check_eq(b.get_format(), Image.FORMAT_R8, "texture B format")
	var at := Vector2i(Vector2(300, 400) / GroundMap.TEXEL)
	check(a.get_pixelv(at).r > 0.99, "sand in A.r")
	at = Vector2i(Vector2(800, 1000) / GroundMap.TEXEL)
	check(b.get_pixelv(at).r > 0.99, "dry in B.r")

## The ground is render-only: same RNG state after loading, same state hash after running.
func test_ground_does_not_touch_the_simulation() -> void:
	var plain := ScenarioLoader.build(_data(null), _registry, _config)
	var ground := ScenarioLoader.build(_data(), _registry, _config)
	check_eq(ground.rng.state, plain.rng.state, "RNG untouched by loading")
	check_eq(ground.world.obstacles, plain.world.obstacles, "no cells changed")
	for t in 300:
		plain.step()
		ground.step()
	check_eq(ground.state_hash(), plain.state_hash(), "same run with a ground map")

func test_cover_is_deterministic_and_follows_materials() -> void:
	var map := _map()
	var a := GroundCoverRenderer.scatter(map)
	var b := GroundCoverRenderer.scatter(map)
	check_eq(a, b, "same decals for the same map")
	check(a.size() % GroundCoverRenderer.STRIDE == 0, "whole instances")
	# Count decals on litter vs. the same area of plain soil.
	var litter_rect := Rect2(0, 1400, 1080, 520)
	var soil_rect := Rect2(0, 560, 1080, 260)
	var on_litter := 0
	var on_soil := 0
	for i in a.size() / GroundCoverRenderer.STRIDE:
		var at := Vector2(a[i * GroundCoverRenderer.STRIDE + 3], a[i * GroundCoverRenderer.STRIDE + 7])
		if litter_rect.has_point(at):
			on_litter += 1
		elif soil_rect.has_point(at):
			on_soil += 1
	# Half the litter rect is litter; the soil rect is half its area.
	check(on_litter > on_soil * 4, "much denser on litter (%d vs %d)" % [on_litter, on_soil])
	check(on_soil > 0, "a few decals on plain soil")

func test_cover_atlas() -> void:
	var img := GroundCoverRenderer.bake_atlas(3)
	var px := GroundCoverRenderer.CELLS * GroundCoverRenderer.CELL_PX
	check_eq(img.get_size(), Vector2i(px, px), "atlas size")
	for i in GroundCoverRenderer.ATLAS.size():
		var ox := (i % GroundCoverRenderer.CELLS) * GroundCoverRenderer.CELL_PX
		var oy := (i / GroundCoverRenderer.CELLS) * GroundCoverRenderer.CELL_PX
		var filled := 0
		for y in GroundCoverRenderer.CELL_PX:
			for x in GroundCoverRenderer.CELL_PX:
				if img.get_pixel(ox + x, oy + y).a > 0.5:
					filled += 1
		check(filled > 20, "sprite %d drawn (%d px)" % [i, filled])
		check_eq(img.get_pixel(ox, oy).a, 0.0, "sprite %d leaves its cell corner clear" % i)
