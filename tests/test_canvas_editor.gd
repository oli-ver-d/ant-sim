extends TestCase
## M16e: canvas editing (CanvasEditor) driven with world positions, headless:
## place tools, selecting, moving, handle drags, snap, point insert/delete,
## delete and duplicate, all as doc commands.

const TOL := 8.0

var _schema: ScenarioSchema

func _canvas(data: Dictionary) -> CanvasEditor:
	if _schema == null:
		var registry := Registry.create_default()
		_schema = ScenarioSchema.new(registry)
	return CanvasEditor.new(ScenarioDoc.new(data, _schema), _schema)

func _data() -> Dictionary:
	return {"name": "t", "seed": 1, "colonies": [{"species": "leafcutter", "nest": [540.0, 1500.0]}],
			"food": [{"type": "food_pile", "pos": [300.0, 500.0], "radius": 30.0, "amount": 200.0}],
			"obstacles": [{"shape": "polyline", "points": [[100.0, 900.0], [400.0, 900.0]], "width": 16.0}]}

func _click(c: CanvasEditor, at: Vector2, alt: bool = false) -> void:
	c.press(at, TOL, alt)
	c.release(at, TOL)

func _drag(c: CanvasEditor, from: Vector2, to: Vector2) -> void:
	c.press(from, TOL)
	c.motion(from.lerp(to, 0.5), TOL)
	c.motion(to, TOL)
	c.release(to, TOL)

func test_every_tool_places_an_item_that_builds() -> void:
	var registry := Registry.create_default()
	for t: Array in CanvasEditor.TOOLS:
		if t[0] == "select":
			continue
		var c := _canvas(_data())
		var picked: Array = []
		c.select_requested.connect(func(p: Variant) -> void: picked.append(p))
		c.set_tool(t[0])
		var how: String = t[3]
		if how == "polyline" or how == "polygon":
			for p: Vector2 in [Vector2(600, 600), Vector2(700, 620), Vector2(650, 720)]:
				_click(c, p)
			check(c.finish_poly(), "%s finishes" % t[0])
		else:
			_click(c, Vector2(700, 700))
		var list: Array = t[2]
		var items: Variant = c.doc.get_at(list)
		if list == ["camera"]:
			check(items is Array and items.size() == 1, "camera key added")
		check(items is Array and not items.is_empty(), "%s adds to %s" % [t[0], list])
		check_eq(picked, [list + [(items as Array).size() - 1]], "%s selects the new item" % t[0])
		check_eq(c.tool, "select", "%s: back to the select tool" % t[0])
		check_eq(c.item, list + [(items as Array).size() - 1], "%s: canvas selection" % t[0])
		check(not GizmoGeometry.shapes(c.doc.data, c.item).is_empty(), "%s has gizmo shapes" % t[0])
		var sim := ScenarioLoader.build(c.doc.data, registry, preload("res://sim/default_config.tres"))
		check(sim != null, "%s: the document still builds" % t[0])

func test_circle_and_rect_tools_span_a_drag() -> void:
	var c := _canvas(_data())
	c.set_tool("food")
	_drag(c, Vector2(500, 500), Vector2(560, 580))
	var food: Dictionary = c.doc.get_at(["food", 1])
	check_eq(food["pos"], [500, 500], "centre at the press")
	check_eq(food["radius"], 100, "radius to the release")
	c.set_tool("scatter")
	_drag(c, Vector2(300, 400), Vector2(100, 250))
	check_eq(c.doc.get_at(["scenery", 0, "scatter", "rect"]), [100, 250, 200, 150], "rect spanned either way")

func test_polygon_needs_three_points_and_double_click_finishes() -> void:
	var c := _canvas(_data())
	c.set_tool("water")
	_click(c, Vector2(0, 0))
	_click(c, Vector2(100, 0))
	check(not c.finish_poly(), "two points are not a polygon")
	c.press(Vector2(50, 80), TOL)
	c.release(Vector2(50, 80), TOL)
	c.press(Vector2(50, 80), TOL, false, true)
	c.release(Vector2(50, 80), TOL)
	check_eq(c.doc.get_at(["obstacles", 1, "points"]), [[0, 0], [100, 0], [50, 80]], "double click finishes")
	check_eq(c.doc.get_at(["obstacles", 1, "kind"]), "water")

func test_region_tool_turns_a_ground_material_into_regions() -> void:
	var data := _data()
	data["ground"] = "sand"
	var c := _canvas(data)
	c.set_tool("region_circle")
	_click(c, Vector2(400, 400))
	check_eq(c.doc.get_at(["ground", "base"]), "sand", "base kept")
	check_eq(c.doc.get_at(["ground", "regions", 0, "center"]), [400, 400], "region added")
	check(c.doc.undo() and c.doc.get_at(["ground"]) == "sand", "one undo step")

func test_click_selects_and_empty_click_deselects() -> void:
	var c := _canvas(_data())
	var picked: Array = []
	c.select_requested.connect(func(p: Variant) -> void: picked.append(p))
	_click(c, Vector2(305, 505))
	check_eq(c.item, ["food", 0], "click on food")
	_click(c, Vector2(250, 903))
	check_eq(c.item, ["obstacles", 0], "click near a polyline")
	_click(c, Vector2(900, 100))
	check_eq(picked, [["food", 0], ["obstacles", 0], null], "empty click deselects")
	check(not c.doc.is_dirty(), "clicks change nothing")

func test_drag_moves_an_item_in_one_command() -> void:
	var c := _canvas(_data())
	c.press(Vector2(300, 500), TOL)
	c.motion(Vector2(350, 520), TOL)
	check(c.dragging(), "dragging")
	check_eq(c.doc.get_at(["food", 0, "pos"]), [300.0, 500.0], "the doc waits for the release")
	check_eq(c.drag_item["pos"], [350, 520], "drag item moved")
	c.release(Vector2(350, 520), TOL)
	check(not c.dragging(), "drag over")
	check_eq(c.doc.get_at(["food", 0, "pos"]), [350, 520], "moved")
	check_eq(c.doc.get_at(["food", 0, "amount"]), 200.0, "other keys kept")
	c.doc.undo()
	check_eq(c.doc.get_at(["food", 0, "pos"]), [300.0, 500.0], "one undo restores")
	check(not c.doc.is_dirty(), "clean after the undo")

func test_small_press_movement_is_a_click() -> void:
	var c := _canvas(_data())
	c.press(Vector2(300, 500), TOL)
	c.motion(Vector2(302, 500), TOL)
	c.release(Vector2(302, 500), TOL)
	check(not c.doc.is_dirty(), "no move under the drag threshold")

func test_handle_drags_radius_and_points() -> void:
	var c := _canvas(_data())
	_click(c, Vector2(300, 500))
	_drag(c, Vector2(330, 500), Vector2(345, 500))
	check_eq(c.doc.get_at(["food", 0, "radius"]), 45, "radius handle")
	check_eq(c.doc.get_at(["food", 0, "pos"]), [300.0, 500.0], "centre stays")
	_click(c, Vector2(250, 900))
	_drag(c, Vector2(400, 900), Vector2(420, 960))
	check_eq(c.doc.get_at(["obstacles", 0, "points"]), [[100, 900], [420, 960]], "point handle")

func test_snap() -> void:
	var c := _canvas(_data())
	c.snap = true
	c.press(Vector2(300, 500), TOL)
	c.motion(Vector2(333, 517), TOL)
	c.release(Vector2(333, 517), TOL)
	check_eq(c.doc.get_at(["food", 0, "pos"]), [330, 520], "moved to the grid")
	c.set_tool("rock")
	_click(c, Vector2(104, 96))
	check_eq(c.doc.get_at(["scenery", 0, "center"]), [100, 100], "placed on the grid")

func test_alt_click_inserts_and_delete_removes_a_point() -> void:
	var c := _canvas(_data())
	_click(c, Vector2(250, 900))
	_click(c, Vector2(250, 902), true)
	check_eq(c.doc.get_at(["obstacles", 0, "points"]), [[100, 900], [250, 902], [400, 900]], "inserted")
	_click(c, Vector2(250, 902))
	check_eq(c.active_handle.get("role"), "point", "point handle active")
	check(c.delete_selected(), "deleted")
	check_eq(c.doc.get_at(["obstacles", 0, "points"]), [[100, 900], [400, 900]], "point removed")
	# Two points left: Delete on a point removes the whole item.
	_click(c, Vector2(100, 900))
	check(c.delete_selected(), "deleted again")
	check_eq((c.doc.get_at(["obstacles"]) as Array).size(), 0, "polyline removed")
	check(c.item == null, "nothing selected")

func test_duplicate_and_delete_items() -> void:
	var c := _canvas(_data())
	check(not c.duplicate_selected(), "nothing to duplicate")
	_click(c, Vector2(300, 500))
	check(c.duplicate_selected(), "duplicated")
	check_eq(c.item, ["food", 1], "copy selected")
	check_eq(c.doc.get_at(["food", 1, "pos"]), [320, 520], "copy offset")
	check(c.delete_selected(), "deleted")
	check_eq((c.doc.get_at(["food"]) as Array).size(), 1, "copy removed")
	c.doc.undo()
	c.doc.undo()
	check_eq((c.doc.get_at(["food"]) as Array).size(), 1, "undo delete then duplicate")
	check(not c.doc.is_dirty(), "back to clean")

func test_cancel_drops_a_drag_and_placing() -> void:
	var c := _canvas(_data())
	c.press(Vector2(300, 500), TOL)
	c.motion(Vector2(400, 500), TOL)
	c.cancel()
	c.release(Vector2(400, 500), TOL)
	check(not c.doc.is_dirty(), "cancelled drag writes nothing")
	c.set_tool("wall_line")
	_click(c, Vector2(0, 0))
	c.cancel()
	check(c.poly_points.is_empty(), "points dropped")
	check_eq(c.tool, "wall_line", "tool kept")

func test_item_of() -> void:
	var data := _data()
	check_eq(CanvasEditor.item_of(data, ["food", 0, "amount"]), ["food", 0])
	check_eq(CanvasEditor.item_of(data, ["food"]), null)
	check_eq(CanvasEditor.item_of(data, null), null)
	check_eq(CanvasEditor.item_of(data, []), null)
