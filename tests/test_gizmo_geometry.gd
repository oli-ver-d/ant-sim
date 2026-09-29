extends TestCase
## M16e: the canvas gizmo geometry (shapes, handles, hit testing, edits), GUI-free.

func _kinds(shp: Array[Dictionary]) -> Array:
	return shp.map(func(s: Dictionary) -> String: return s["kind"])

func _roles(shp: Array[Dictionary]) -> Array:
	return shp.map(func(s: Dictionary) -> String: return s["role"])

# --- item_paths ---------------------------------------------------------------------------

func test_item_paths_order_and_cameras() -> void:
	var data := {
		"colonies": [{}, {}], "food": [{}], "obstacles": [{}],
		"ground": {"regions": [{}, {}]}, "scenery": [{}], "debris": [{}], "events": [{}],
		"camera": [{}, {}],
	}
	check_eq(GizmoGeometry.item_paths(data), [["colonies", 0], ["colonies", 1], ["food", 0], ["obstacles", 0],
			["ground", "regions", 0], ["ground", "regions", 1], ["scenery", 0], ["debris", 0], ["events", 0],
			["camera", 0], ["camera", 1]])

func test_item_paths_camera_tracks_and_ground_string() -> void:
	var data := {"ground": "sand", "camera": {"surface": [{}, {}], "nest": [{}]}, "food": "oops"}
	check_eq(GizmoGeometry.item_paths(data), [["camera", "surface", 0], ["camera", "surface", 1], ["camera", "nest", 0]])
	check_eq(GizmoGeometry.item_paths({}), [])

# --- shapes ---------------------------------------------------------------------------------

func test_shapes_colony_and_food() -> void:
	var data := {"colonies": [{"nest": [540, 1500]}, {}], "food": [{"pos": [10, 20], "radius": 22}, {"pos": [1, 2]}, {"pos": "x"}]}
	var c := GizmoGeometry.shapes(data, ["colonies", 0])
	check_eq(c.size(), 1)
	check_eq(c[0]["center"], Vector2(540, 1500))
	check_eq(c[0]["center_key"], "nest")
	check_eq(c[0]["radius"], EditorOutline.NEST_HALF)
	check_eq(c[0]["radius_key"], "")
	check_eq(GizmoGeometry.shapes(data, ["colonies", 1]).size(), 0)
	var f := GizmoGeometry.shapes(data, ["food", 0])
	check_eq(f[0]["radius"], 22.0)
	check_eq(f[0]["radius_key"], "radius")
	check_eq(GizmoGeometry.shapes(data, ["food", 1])[0]["radius"], 30.0)
	check_eq(GizmoGeometry.shapes(data, ["food", 2]).size(), 0)
	check_eq(GizmoGeometry.shapes(data, ["food", 9]).size(), 0)
	check_eq(GizmoGeometry.shapes(data, []).size(), 0)

func test_shapes_obstacles() -> void:
	var data := {"obstacles": [
		{"shape": "circle", "center": [1, 2], "radius": 5},
		{"shape": "rect", "rect": [1, 2, 3, 4]},
		{"shape": "polyline", "points": [[0, 0], [10, 0]]},
		{"shape": "polygon", "points": [[0, 0], [10, 0], [5, 5]]},
		{"points": [[0, 0], [10, 0]], "width": 8},
		{"rect": [0, 0, 5, 5]},
		{"center": [3, 3], "radius": 2},
		{"shape": "circle", "center": "bad"},
		{"shape": "polyline", "points": [[0, 0], ["a", 1]]},
	]}
	var expected := ["circle", "rect", "polyline", "polygon", "polyline", "rect", "circle"]
	for i: int in expected.size():
		var s := GizmoGeometry.shapes(data, ["obstacles", i])
		check_eq(s.size(), 1, "obstacle %d" % i)
		check_eq(s[0]["kind"], expected[i], "obstacle %d kind" % i)
		check_eq(s[0]["role"], "body")
	check_eq(GizmoGeometry.shapes(data, ["obstacles", 2])[0]["width"], 16.0)
	check_eq(GizmoGeometry.shapes(data, ["obstacles", 4])[0]["width"], 8.0)
	check_eq(GizmoGeometry.shapes(data, ["obstacles", 1])[0]["rect"], Rect2(1, 2, 3, 4))
	check_eq(GizmoGeometry.shapes(data, ["obstacles", 7]).size(), 0)
	check_eq(GizmoGeometry.shapes(data, ["obstacles", 8]).size(), 0)

func test_shapes_ground_regions() -> void:
	var data := {"ground": {"regions": [
		{"material": "moss", "shape": "circle", "center": [5, 5], "radius": 9, "soft": 60},
		{"material": "moss", "shape": "rect", "rect": [0, 0, 5, 5]},
		{"material": "moss"},
	]}}
	var a := GizmoGeometry.shapes(data, ["ground", "regions", 0])
	check_eq(a[0]["soft"], 60.0)
	check_eq(GizmoGeometry.shapes(data, ["ground", "regions", 1])[0]["soft"], 40.0)
	check_eq(GizmoGeometry.shapes(data, ["ground", "regions", 2]).size(), 0)

func test_shapes_scenery_props() -> void:
	var data := {"scenery": [
		{"type": "rock", "center": [5, 6], "radius": 40},
		{"type": "plant", "pos": [7, 8]},
		{"type": "log", "points": [[1, 2], [3, 4]]},
		{"type": "log", "points": [[1, 2], [3, 4]], "width": 12},
		{"type": "x"},
	]}
	var rock := GizmoGeometry.shapes(data, ["scenery", 0])[0]
	check_eq(rock["kind"], "circle")
	check_eq(rock["radius"], 40.0)
	check_eq(rock["center_key"], "center")
	var plant := GizmoGeometry.shapes(data, ["scenery", 1])[0]
	check_eq(plant["center_key"], "pos")
	check_eq(plant["radius"], 20.0)
	check_eq(plant["radius_key"], "radius")
	check_eq(GizmoGeometry.shapes(data, ["scenery", 2])[0]["width"], 30.0)
	check_eq(GizmoGeometry.shapes(data, ["scenery", 3])[0]["width"], 12.0)
	check_eq(GizmoGeometry.shapes(data, ["scenery", 4]).size(), 0)

func _scatter_data() -> Dictionary:
	return {"scenery": [{"scatter": {"rect": [0, 0, 500, 400], "clear": [
		{"shape": "polyline", "points": [[10, 10], [100, 10]], "width": 60},
		{"points": [[10, 50], [100, 50]], "reserve": true},
		{"shape": "circle", "center": [50, 50], "radius": 20},
		{"shape": "rect", "rect": [5, 5, 10, 10]},
	]}}]}

func test_shapes_scatter() -> void:
	var s := GizmoGeometry.shapes(_scatter_data(), ["scenery", 0])
	check_eq(_kinds(s), ["rect", "polyline", "polyline", "circle", "rect"])
	check_eq(_roles(s), ["area", "clear", "clear", "clear", "clear"])
	check_eq(s[0]["path"], ["scenery", 0, "scatter"])
	check_eq(s[1]["path"], ["scenery", 0, "scatter", "clear", 0])
	check_eq(s[1]["hard"], true)
	check_eq(s[1]["width"], 60.0)
	check_eq(s[2]["hard"], false)
	check_eq(s[2]["width"], 40.0, "default clear width")
	check_eq(GizmoGeometry.shapes({"scenery": [{"scatter": {}}]}, ["scenery", 0]).size(), 0)
	check_eq(GizmoGeometry.shapes({"scenery": [{"scatter": 5}]}, ["scenery", 0]).size(), 0)

func test_shapes_debris() -> void:
	var data := {"debris": [{"type": "twig", "pos": [1, 2], "length": 50}, {"pos": [1, 2]}, {"type": "pebble", "pos": [3, 4]},
			{"type": "pebble", "pos": [3, 4], "radius": 9}, {"type": "twig"}]}
	var t := GizmoGeometry.shapes(data, ["debris", 0])[0]
	check_eq(t["radius"], 25.0)
	check_eq(t["radius_key"], "")
	check_eq(GizmoGeometry.shapes(data, ["debris", 1])[0]["radius"], 17.0)
	var p := GizmoGeometry.shapes(data, ["debris", 2])[0]
	check_eq(p["radius"], 5.0)
	check_eq(p["radius_key"], "radius")
	check_eq(GizmoGeometry.shapes(data, ["debris", 3])[0]["radius"], 9.0)
	check_eq(GizmoGeometry.shapes(data, ["debris", 4]).size(), 0)

func test_shapes_events_rain_and_spawn() -> void:
	var data := {"events": [
		{"type": "rain", "area": {"center": [300, 300], "radius": 100}},
		{"type": "rain", "area": {"rect": [0, 0, 50, 60]}},
		{"type": "rain"},
		{"type": "spawn_food", "food": {"pos": [5, 6], "radius": 12}},
		{"type": "remove_scenery", "at": [9, 9]},
		{"type": "add_colony", "colony": {"nest": [100, 200]}},
	]}
	var r := GizmoGeometry.shapes(data, ["events", 0])[0]
	check_eq(r["role"], "area")
	check_eq(r["path"], ["events", 0, "area"])
	check_eq(r["radius"], 100.0)
	var rr := GizmoGeometry.shapes(data, ["events", 1])[0]
	check_eq(rr["kind"], "rect")
	check_eq(rr["rect"], Rect2(0, 0, 50, 60))
	check_eq(GizmoGeometry.shapes(data, ["events", 2]).size(), 0)
	var f := GizmoGeometry.shapes(data, ["events", 3])[0]
	check_eq(f["path"], ["events", 3, "food"])
	check_eq(f["radius"], 12.0)
	var at := GizmoGeometry.shapes(data, ["events", 4])[0]
	check_eq(at["kind"], "point")
	check_eq(at["center_key"], "at")
	var col := GizmoGeometry.shapes(data, ["events", 5])[0]
	check_eq(col["path"], ["events", 5, "colony"])
	check_eq(col["center_key"], "nest")

func test_shapes_events_obstacle_scenery_debris() -> void:
	var data := {"events": [
		{"type": "add_obstacle", "obstacle": {"shape": "circle", "center": [1, 1], "radius": 4}},
		{"type": "remove_obstacle", "obstacle": {"shape": "rect", "rect": [1, 1, 4, 4]}},
		{"type": "add_scenery", "scenery": {"type": "rock", "center": [5, 5]}},
		{"type": "add_scenery", "scenery": [{"type": "rock", "center": [5, 5]}, {"type": "log", "points": [[0, 0], [9, 9]]}]},
		{"type": "add_scenery", "scenery": {"scatter": {"rect": [0, 0, 10, 10], "clear": [{"points": [[0, 0], [5, 5]]}]}}},
		{"type": "drop_debris", "scatter": {"near": [545, 790]}, "debris": [{"type": "twig", "pos": [1, 2]}, {"type": "pebble", "pos": [3, 4]}]},
	]}
	check_eq(GizmoGeometry.shapes(data, ["events", 0])[0]["path"], ["events", 0, "obstacle"])
	check_eq(GizmoGeometry.shapes(data, ["events", 1])[0]["kind"], "rect")
	check_eq(GizmoGeometry.shapes(data, ["events", 2])[0]["path"], ["events", 2, "scenery"])
	var list := GizmoGeometry.shapes(data, ["events", 3])
	check_eq(list.size(), 2)
	check_eq(list[1]["path"], ["events", 3, "scenery", 1])
	var sc := GizmoGeometry.shapes(data, ["events", 4])
	check_eq(_roles(sc), ["area", "clear"])
	check_eq(sc[1]["path"], ["events", 4, "scenery", "scatter", "clear", 0])
	var dd := GizmoGeometry.shapes(data, ["events", 5])
	check_eq(dd.size(), 3)
	check_eq(dd[0]["role"], "area")
	check_eq(dd[0]["radius"], 150.0)
	check_eq(dd[0]["path"], ["events", 5, "scatter"])
	check_eq(dd[0]["center_key"], "near")
	check_eq(dd[1]["path"], ["events", 5, "debris", 0])
	check_eq(dd[2]["radius_key"], "radius")

func test_shapes_camera() -> void:
	var data := {"camera": {"surface": [{"t": 0, "pos": [540, 960]}, {"t": 1, "follow": {"ant": 0, "near": [10, 20]}},
			{"t": 2, "follow": {"ant": 0}}, {"t": 3}]}}
	var a := GizmoGeometry.shapes(data, ["camera", "surface", 0])[0]
	check_eq(a["kind"], "point")
	check_eq(a["center"], Vector2(540, 960))
	check_eq(a["center_key"], "pos")
	var b := GizmoGeometry.shapes(data, ["camera", "surface", 1])[0]
	check_eq(b["path"], ["camera", "surface", 1, "follow"])
	check_eq(b["center_key"], "near")
	check_eq(GizmoGeometry.shapes(data, ["camera", "surface", 2]).size(), 0)
	check_eq(GizmoGeometry.shapes(data, ["camera", "surface", 3]).size(), 0)

func test_every_shipped_scenario() -> void:
	for f: String in DirAccess.get_files_at(ScenarioLoader.SCENARIO_DIR):
		if not f.ends_with(".json"):
			continue
		var data := ScenarioLoader.load_data(f.get_basename())
		var total := 0
		for ip: Array in GizmoGeometry.item_paths(data):
			var shp := GizmoGeometry.shapes(data, ip)
			total += shp.size()
			for s: Dictionary in shp:
				check(s["path"].slice(0, ip.size()) == ip, "%s: shape path under item %s" % [f, ip])
				check(GizmoGeometry.shape_bounds(s).size.is_finite(), f + ": finite bounds")
				GizmoGeometry.handles(s)
			var b := GizmoGeometry.item_bounds(data, ip)
			if ip[0] == "colonies" or ip[0] == "food":
				var ob := EditorOutline.item_bounds(data, ip)
				check_eq(b.get_center(), ob.get_center(), "%s: %s centre agrees with outline" % [f, ip])
				check_eq(b.size, ob.size, "%s: %s size agrees with outline" % [f, ip])
		check(total > 0, f + " has shapes")

# --- bounds, contains -------------------------------------------------------------------------

func test_bounds() -> void:
	var data := {"obstacles": [
		{"shape": "circle", "center": [100, 100], "radius": 20},
		{"shape": "polyline", "points": [[0, 0], [100, 0]], "width": 10},
		{"shape": "polygon", "points": [[0, 0], [10, 0], [5, 8]]},
	], "camera": [{"pos": [5, 6]}], "colonies": [{}]}
	check_eq(GizmoGeometry.item_bounds(data, ["obstacles", 0]), Rect2(80, 80, 40, 40))
	check_eq(GizmoGeometry.item_bounds(data, ["obstacles", 1]), Rect2(-5, -5, 110, 10))
	check_eq(GizmoGeometry.item_bounds(data, ["obstacles", 2]), Rect2(0, 0, 10, 8))
	check_eq(GizmoGeometry.item_bounds(data, ["camera", 0]), Rect2(5, 6, 0, 0))
	check_eq(GizmoGeometry.item_bounds(data, ["colonies", 0]), Rect2())
	var sc := _scatter_data()
	check_eq(GizmoGeometry.item_bounds(sc, ["scenery", 0]), Rect2(-20, -20, 520, 420), "union of area and clear (polyline grown by half width)")

func test_contains_circle_rect_point() -> void:
	var circle := {"kind": "circle", "center": Vector2(10, 10), "radius": 5.0}
	check(GizmoGeometry.shape_contains(circle, Vector2(15, 10), 0.0), "on the edge")
	check(not GizmoGeometry.shape_contains(circle, Vector2(16, 10), 0.0), "outside")
	check(GizmoGeometry.shape_contains(circle, Vector2(16, 10), 1.0), "tolerance")
	var rect := {"kind": "rect", "rect": Rect2(0, 0, 10, 10)}
	check(GizmoGeometry.shape_contains(rect, Vector2(5, 5), 0.0), "inside")
	check(not GizmoGeometry.shape_contains(rect, Vector2(11, 5), 0.0), "outside")
	check(GizmoGeometry.shape_contains(rect, Vector2(11, 5), 2.0), "grown by tol")
	var pt := {"kind": "point", "center": Vector2(3, 3)}
	check(GizmoGeometry.shape_contains(pt, Vector2(4, 3), 1.0), "point within tol")
	check(not GizmoGeometry.shape_contains(pt, Vector2(6, 3), 1.0), "point outside tol")

func test_contains_polyline_polygon() -> void:
	var line := {"kind": "polyline", "points": PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)]), "width": 20.0}
	check(GizmoGeometry.shape_contains(line, Vector2(50, 9), 0.0), "within half width")
	check(not GizmoGeometry.shape_contains(line, Vector2(50, 11), 0.0), "beyond half width")
	check(GizmoGeometry.shape_contains(line, Vector2(50, 13), 3.0), "tolerance")
	check(GizmoGeometry.shape_contains(line, Vector2(100, 50), 0.0), "second segment")
	check(not GizmoGeometry.shape_contains(line, Vector2(0, 50), 0.0), "not the closing segment")
	var poly := {"kind": "polygon", "points": PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(50, 80)])}
	check(GizmoGeometry.shape_contains(poly, Vector2(50, 30), 0.0), "inside")
	check(not GizmoGeometry.shape_contains(poly, Vector2(50, -5), 0.0), "outside")
	check(GizmoGeometry.shape_contains(poly, Vector2(50, -5), 6.0), "edge tolerance")
	check(GizmoGeometry.shape_contains(poly, Vector2(25, 40), 2.0), "closing edge tolerance")

# --- hit_item ----------------------------------------------------------------------------------

func test_hit_item_smallest_and_later() -> void:
	var data := {
		"obstacles": [{"shape": "circle", "center": [100, 100], "radius": 80}, {"shape": "circle", "center": [100, 100], "radius": 20}],
		"food": [{"pos": [100, 100], "radius": 20}],
		"debris": [{"type": "pebble", "pos": [300, 300]}],
		"camera": [{"pos": [300, 300]}],
	}
	check_eq(GizmoGeometry.hit_item(data, Vector2(100, 100), 0.0), ["obstacles", 1],"tie with equal circles: obstacles draw after food")
	check_eq(GizmoGeometry.hit_item(data, Vector2(170, 100), 0.0), ["obstacles", 0], "only the big one")
	check_eq(GizmoGeometry.hit_item(data, Vector2(300, 300), 2.0), ["camera", 0], "points beat areas")
	check_eq(GizmoGeometry.hit_item(data, Vector2(-500, -500), 5.0), null)
	check_eq(GizmoGeometry.hit_item({}, Vector2.ZERO, 5.0), null)

func test_hit_item_nested_shapes() -> void:
	var data := {
		"scenery": [{"scatter": {"rect": [0, 0, 1000, 1000]}}, {"type": "rock", "center": [500, 500], "radius": 30}],
		"obstacles": [{"shape": "rect", "rect": [400, 400, 200, 200]}],
	}
	check_eq(GizmoGeometry.hit_item(data, Vector2(500, 500), 0.0), ["scenery", 1])
	check_eq(GizmoGeometry.hit_item(data, Vector2(420, 420), 0.0), ["obstacles", 0])
	check_eq(GizmoGeometry.hit_item(data, Vector2(50, 50), 0.0), ["scenery", 0])

# --- handles -----------------------------------------------------------------------------------

func test_handles() -> void:
	var circle := {"kind": "circle", "center": Vector2(10, 10), "radius": 5.0, "radius_key": "radius"}
	var h := GizmoGeometry.handles(circle)
	check_eq(h.size(), 2)
	check_eq(h[0], {"role": "center", "index": 0, "pos": Vector2(10, 10)})
	check_eq(h[1], {"role": "radius", "index": 0, "pos": Vector2(15, 10)})
	circle["radius_key"] = ""
	check_eq(GizmoGeometry.handles(circle).size(), 1, "no radius handle for a fixed radius")
	check_eq(GizmoGeometry.handles({"kind": "point", "center": Vector2(1, 2)}).size(), 1)
	var rh := GizmoGeometry.handles({"kind": "rect", "rect": Rect2(0, 0, 10, 20)})
	check_eq(rh.map(func(x: Dictionary) -> Vector2: return x["pos"]), [Vector2(0, 0), Vector2(10, 0), Vector2(10, 20), Vector2(0, 20)])
	check_eq(rh.map(func(x: Dictionary) -> String: return x["role"]), ["corner", "corner", "corner", "corner"])
	var ph := GizmoGeometry.handles({"kind": "polygon", "points": PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)])})
	check_eq(ph.size(), 3)
	check_eq(ph[2], {"role": "point", "index": 2, "pos": Vector2(2, 0)})

func test_hit_handle() -> void:
	var data := {"food": [{"pos": [100, 100], "radius": 40}], "obstacles": [{"shape": "polyline", "points": [[0, 0], [50, 0], [50, 50]]}],
			"scenery": [{"type": "rock", "center": [100, 100]}]}
	var h := GizmoGeometry.hit_handle(data, ["food", 0], Vector2(138, 101), 6.0)
	check_eq(h["role"], "radius")
	check_eq(h["shape"], 0)
	check_eq(h["pos"], Vector2(140, 100))
	check_eq(GizmoGeometry.hit_handle(data, ["food", 0], Vector2(101, 99), 6.0)["role"], "center")
	check(GizmoGeometry.hit_handle(data, ["food", 0], Vector2(120, 100), 6.0).is_empty(), "nothing near")
	var p := GizmoGeometry.hit_handle(data, ["obstacles", 0], Vector2(52, 49), 6.0)
	check_eq(p["role"], "point")
	check_eq(p["index"], 2)
	check(GizmoGeometry.hit_handle(data, ["nothing", 0], Vector2.ZERO, 5.0).is_empty(), "missing item")

func test_hit_handle_prefers_radius_over_center_at_equal_distance() -> void:
	# A circle whose radius is 0 has both handles at the centre.
	var data := {"obstacles": [{"shape": "circle", "center": [10, 10], "radius": 0}]}
	check_eq(GizmoGeometry.hit_handle(data, ["obstacles", 0], Vector2(10, 10), 5.0)["role"], "radius")

func test_hit_handle_second_shape_index() -> void:
	var h := GizmoGeometry.hit_handle(_scatter_data(), ["scenery", 0], Vector2(100, 50), 4.0)
	check_eq(h["shape"], 2)
	check_eq(h["role"], "point")
	check_eq(h["index"], 1)

# --- moved -------------------------------------------------------------------------------------

func test_moved_rounds_to_ints() -> void:
	var data := {"a": 1, "food": [{"pos": [10.0, 20.0], "type": "food_pile"}]}
	var item := GizmoGeometry.moved(data, ["food", 0], Vector2(0.4, 0.0))
	check_eq(item["pos"], [10, 20])
	check_eq(typeof(item["pos"][0]), TYPE_INT)
	check_eq(typeof(item["pos"][1]), TYPE_INT)
	check_eq(item["type"], "food_pile")
	check_eq(data["food"][0]["pos"], [10.0, 20.0], "data untouched")
	check_eq(typeof(data["food"][0]["pos"][0]), TYPE_FLOAT)

func test_moved_keeps_key_order_and_other_keys() -> void:
	var data := {"colonies": [{"species": "leafcutter", "nest": [100, 100], "ants": 30, "nest_params": {"brood": 1}}]}
	var item := GizmoGeometry.moved(data, ["colonies", 0], Vector2(5, -5))
	check_eq(item.keys(), ["species", "nest", "ants", "nest_params"])
	check_eq(item["nest"], [105, 95])
	check_eq(item["nest_params"], {"brood": 1})
	check_eq(data["colonies"][0]["nest"], [100, 100])

func test_moved_scatter_with_clear_shapes() -> void:
	var data := _scatter_data()
	var before := data.duplicate(true)
	var item := GizmoGeometry.moved(data, ["scenery", 0], Vector2(10, 20))
	check_eq(item["scatter"]["rect"], [10, 20, 500, 400])
	check_eq(item["scatter"]["clear"][0]["points"], [[20, 30], [110, 30]])
	check_eq(item["scatter"]["clear"][1]["points"], [[20, 70], [110, 70]])
	check_eq(item["scatter"]["clear"][2]["center"], [60, 70])
	check_eq(item["scatter"]["clear"][3]["rect"], [15, 25, 10, 10])
	check_eq(item["scatter"]["clear"][0]["width"], 60, "width kept")
	check_eq(item["scatter"]["clear"][1]["reserve"], true)
	check_eq(data, before, "data untouched")

func test_moved_rain_rect_area_and_drop_debris() -> void:
	var data := {"events": [
		{"t": 5, "type": "rain", "area": {"rect": [100, 200, 300, 400]}, "intensity": 2},
		{"t": 6, "type": "drop_debris", "scatter": {"count": 9, "near": [545, 790], "radius": 150}, "debris": [{"type": "twig", "pos": [1, 2]}]},
		{"t": 7, "type": "rain"},
	]}
	var rain := GizmoGeometry.moved(data, ["events", 0], Vector2(-50, 25))
	check_eq(rain["area"]["rect"], [50, 225, 300, 400])
	check_eq(rain.keys(), ["t", "type", "area", "intensity"])
	var drop := GizmoGeometry.moved(data, ["events", 1], Vector2(10, 10))
	check_eq(drop["scatter"]["near"], [555, 800])
	check_eq(drop["scatter"]["radius"], 150)
	check_eq(drop["debris"][0]["pos"], [11, 12])
	check_eq(GizmoGeometry.moved(data, ["events", 2], Vector2(10, 10)), data["events"][2], "no shape: unchanged copy")
	check_eq(GizmoGeometry.moved(data, ["events", 9], Vector2(1, 1)), {}, "missing item")

func test_moved_camera_follow_near_and_polyline() -> void:
	var data := {"camera": [{"t": 1, "follow": {"ant": 0, "near": [10, 20]}}], "obstacles": [{"shape": "polyline", "points": [[0, 0], [10, 0]], "width": 8}]}
	check_eq(GizmoGeometry.moved(data, ["camera", 0], Vector2(1, 2))["follow"], {"ant": 0, "near": [11, 22]})
	check_eq(GizmoGeometry.moved(data, ["obstacles", 0], Vector2(3, 3))["points"], [[3, 3], [13, 3]])

# --- dragged ---------------------------------------------------------------------------------------

func test_dragged_center_and_radius() -> void:
	var data := {"food": [{"type": "f", "pos": [100, 100], "radius": 40}], "scenery": [{"type": "plant", "center": [50, 50]}]}
	var h := GizmoGeometry.hit_handle(data, ["food", 0], Vector2(101, 100), 5.0)
	var item := GizmoGeometry.dragged(data, ["food", 0], h, Vector2(121, 90))
	check_eq(item["pos"], [121, 90], "centre moves by the drag delta")
	check_eq(item["radius"], 40)
	var r := GizmoGeometry.hit_handle(data, ["food", 0], Vector2(140, 100), 5.0)
	var item2 := GizmoGeometry.dragged(data, ["food", 0], r, Vector2(100, 160.4))
	check_eq(item2["radius"], 60)
	check_eq(item2["pos"], [100, 100])
	check_eq(typeof(item2["radius"]), TYPE_INT)
	check_eq(GizmoGeometry.dragged(data, ["food", 0], r, Vector2(100, 100))["radius"], 1, "radius at least 1")
	# A plant without "radius": the key is added, after the existing ones.
	var rp := GizmoGeometry.hit_handle(data, ["scenery", 0], Vector2(70, 50), 3.0)
	check_eq(rp["role"], "radius")
	var plant := GizmoGeometry.dragged(data, ["scenery", 0], rp, Vector2(80, 50))
	check_eq(plant.keys(), ["type", "center", "radius"])
	check_eq(plant["radius"], 30)
	check(not data["scenery"][0].has("radius"), "data untouched")

func test_dragged_fixed_radius_ignored() -> void:
	var data := {"colonies": [{"nest": [100, 100]}]}
	var fake := {"shape": 0, "role": "radius", "index": 0, "pos": Vector2(160, 100)}
	check_eq(GizmoGeometry.dragged(data, ["colonies", 0], fake, Vector2(300, 100)), {"nest": [100, 100]})

func test_dragged_rect_corners() -> void:
	var data := {"obstacles": [{"shape": "rect", "rect": [100, 100, 200, 100]}]}
	var expect := [
		[Vector2(80, 90), [80, 90, 220, 110]],
		[Vector2(320, 90), [100, 90, 220, 110]],
		[Vector2(320, 230), [100, 100, 220, 130]],
		[Vector2(80, 230), [80, 100, 220, 130]],
	]
	var starts := [Vector2(100, 100), Vector2(300, 100), Vector2(300, 200), Vector2(100, 200)]
	for i: int in 4:
		var h := GizmoGeometry.hit_handle(data, ["obstacles", 0], starts[i], 4.0)
		check_eq(h["role"], "corner")
		check_eq(h["index"], i)
		check_eq(GizmoGeometry.dragged(data, ["obstacles", 0], h, expect[i][0])["rect"], expect[i][1], "corner %d" % i)

func test_dragged_corner_past_opposite_normalises() -> void:
	var data := {"obstacles": [{"shape": "rect", "rect": [100, 100, 200, 100]}]}
	var h := GizmoGeometry.hit_handle(data, ["obstacles", 0], Vector2(100, 100), 4.0)
	check_eq(GizmoGeometry.dragged(data, ["obstacles", 0], h, Vector2(350, 260))["rect"], [300, 200, 50, 60])
	check_eq(GizmoGeometry.dragged(data, ["obstacles", 0], h, Vector2(300, 200))["rect"], [300, 200, 1, 1], "size at least 1")

func test_dragged_polyline_point() -> void:
	var data := {"obstacles": [{"shape": "polyline", "points": [[0, 0], [50, 0], [50, 50]], "width": 12}]}
	var h := GizmoGeometry.hit_handle(data, ["obstacles", 0], Vector2(50, 0), 4.0)
	var item := GizmoGeometry.dragged(data, ["obstacles", 0], h, Vector2(60.6, -9.2))
	check_eq(item["points"], [[0, 0], [61, -9], [50, 50]])
	check_eq(item["width"], 12)

func test_dragged_scatter_clear_point_and_rect() -> void:
	var data := _scatter_data()
	var h := GizmoGeometry.hit_handle(data, ["scenery", 0], Vector2(100, 10), 3.0)
	check_eq(h["shape"], 1)
	var item := GizmoGeometry.dragged(data, ["scenery", 0], h, Vector2(120, 30))
	check_eq(item["scatter"]["clear"][0]["points"], [[10, 10], [120, 30]])
	check_eq(item["scatter"]["rect"], [0, 0, 500, 400])
	var corner := GizmoGeometry.hit_handle(data, ["scenery", 0], Vector2(500, 400), 3.0)
	check_eq(corner["shape"], 0)
	check_eq(GizmoGeometry.dragged(data, ["scenery", 0], corner, Vector2(600, 500))["scatter"]["rect"], [0, 0, 600, 500])

func test_dragged_bad_handle() -> void:
	var data := {"food": [{"pos": [1, 2]}]}
	check_eq(GizmoGeometry.dragged(data, ["food", 0], {}, Vector2(9, 9)), {"pos": [1, 2]})
	check_eq(GizmoGeometry.dragged(data, ["food", 3], {"shape": 0, "role": "center", "index": 0, "pos": Vector2()}, Vector2(9, 9)), {})

# --- insert / remove --------------------------------------------------------------------------------

func test_insert_point_polyline() -> void:
	var data := {"obstacles": [{"shape": "polyline", "points": [[0, 0], [100, 0], [100, 100]], "width": 8}]}
	var item := GizmoGeometry.with_point_inserted(data, ["obstacles", 0], 0, Vector2(50, 3))
	check_eq(item["points"], [[0, 0], [50, 3], [100, 0], [100, 100]])
	var item2 := GizmoGeometry.with_point_inserted(data, ["obstacles", 0], 0, Vector2(104, 60))
	check_eq(item2["points"], [[0, 0], [100, 0], [104, 60], [100, 100]])
	# A polyline has no closing segment: near the far end it still lands on a real one.
	var item3 := GizmoGeometry.with_point_inserted(data, ["obstacles", 0], 0, Vector2(0, 90))
	check_eq(item3["points"].size(), 4)
	check_eq(item3["points"][1], [0, 90], "nearest real segment is the first")
	check_eq(data["obstacles"][0]["points"].size(), 3, "data untouched")

func test_insert_point_polygon_closing_segment() -> void:
	var data := {"obstacles": [{"shape": "polygon", "points": [[0, 0], [100, 0], [50, 80]]}]}
	var item := GizmoGeometry.with_point_inserted(data, ["obstacles", 0], 0, Vector2(20, 45))
	check_eq(item["points"], [[0, 0], [100, 0], [50, 80], [20, 45]])
	check_eq(GizmoGeometry.with_point_inserted(data, ["obstacles", 0], 3, Vector2(1, 1)), {}, "bad shape index")
	var data2 := {"obstacles": [{"shape": "circle", "center": [1, 1], "radius": 3}]}
	check_eq(GizmoGeometry.with_point_inserted(data2, ["obstacles", 0], 0, Vector2(1, 1)), {}, "not a polyline")

func test_remove_point_limits() -> void:
	var data := {"obstacles": [
		{"shape": "polyline", "points": [[0, 0], [10, 0], [20, 0]]},
		{"shape": "polyline", "points": [[0, 0], [10, 0]]},
		{"shape": "polygon", "points": [[0, 0], [10, 0], [5, 5]]},
		{"shape": "polygon", "points": [[0, 0], [10, 0], [5, 5], [0, 5]]},
	]}
	check_eq(GizmoGeometry.with_point_removed(data, ["obstacles", 0], 0, 1)["points"], [[0, 0], [20, 0]])
	check_eq(GizmoGeometry.with_point_removed(data, ["obstacles", 1], 0, 0), {}, "polyline keeps 2 points")
	check_eq(GizmoGeometry.with_point_removed(data, ["obstacles", 2], 0, 0), {}, "polygon keeps 3 points")
	check_eq(GizmoGeometry.with_point_removed(data, ["obstacles", 3], 0, 3)["points"], [[0, 0], [10, 0], [5, 5]])
	check_eq(GizmoGeometry.with_point_removed(data, ["obstacles", 3], 0, 9), {}, "index out of range")
	check_eq(data["obstacles"][0]["points"].size(), 3, "data untouched")

func test_insert_remove_in_scatter_clear() -> void:
	var data := _scatter_data()
	var ins := GizmoGeometry.with_point_inserted(data, ["scenery", 0], 1, Vector2(50, 12))
	check_eq(ins["scatter"]["clear"][0]["points"], [[10, 10], [50, 12], [100, 10]])
	check_eq(GizmoGeometry.with_point_inserted(data, ["scenery", 0], 0, Vector2(1, 1)), {}, "the area rect is not a polyline")

# --- snap ---------------------------------------------------------------------------------------------

func test_snap() -> void:
	check_eq(GizmoGeometry.snap(Vector2(13, 27), 10.0), Vector2(10, 30))
	check_eq(GizmoGeometry.snap(Vector2(13.3, 27.7), 0.0), Vector2(13.3, 27.7))
	check_eq(GizmoGeometry.snap(Vector2(13.3, 27.7), -5.0), Vector2(13.3, 27.7))
	check_eq(GizmoGeometry.snap(Vector2(-14, 26), 20.0), Vector2(-20, 20))
