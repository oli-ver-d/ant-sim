extends TestCase
## M17h: carried items are layered by how high they're held (a cut fragment
## over a waste pellet, whatever their ids), and their shadows are drawn in
## their own pass under the ants. Headless: checks the order and the node
## tree, not pixels.

var _config: SimConfig = load("res://sim/default_config.tres")

func _registry() -> Registry:
	var registry := Registry.create_default()
	CoreRenderers.register(registry)
	return registry

func _item(id: int, height: float) -> Item:
	var item := Item.new()
	item.id = id
	item.carry_height = height
	return item

func test_high_items_are_drawn_after_low_ones_whatever_their_ids() -> void:
	var fragment := _item(3, 1.0)
	var pellet := _item(9, 0.5)
	var items: Array[Item] = [fragment, pellet]
	var order := ItemRenderer.carried_order(items)
	check_eq(order[0], pellet, "the low pellet first")
	check_eq(order[1], fragment, "the high fragment last (on top)")

func test_equal_heights_keep_id_order() -> void:
	var items: Array[Item] = [_item(7, 0.5), _item(2, 0.5), _item(4, 0.5)]
	var ids: Array[int] = []
	for item in ItemRenderer.carried_order(items):
		ids.append(item.id)
	check_eq(ids, [2, 4, 7] as Array[int], "by id")

func test_items_are_carried_low_by_default() -> void:
	# (Cut fragments are high: test_leaf.)
	check_eq(Item.new().carry_height, 0.5, "default")

func test_higher_items_cast_their_shadow_further() -> void:
	var low := ItemRenderer.carried_shadow_offset(0.5)
	var high := ItemRenderer.carried_shadow_offset(1.0)
	check(high.length() > low.length(), "higher, further")
	check(low.length() > ItemRenderer.GROUND_SHADOW_OFFSET.length(), "carried above the ground")
	check(high.length() < 2.5, "held high, but not far above the ant's own shadow")

func test_carried_shadows_are_under_the_ants() -> void:
	var data := {"seed": 7, "food": [], "colonies": [{"species": "leafcutter", "nest_type": "basic_nest",
			"nest": [540, 1000], "population": {"media": 4}}]}
	var sim := ScenarioLoader.build(data, _registry(), _config)
	var view := WorldView.new()
	view.setup(sim, sim.registry)
	var shadows := view.carried_shadows.get_index()
	check_eq(view.carried_shadows.pass_kind, ItemRenderer.Pass.CARRIED_SHADOW, "shadow pass")
	check(shadows < view.ant_renderer.get_index(), "shadows under the ants")
	check(view.ant_renderer.get_index() < view.item_renderer.get_index(), "items over the ants")
	check_eq(view.item_renderer.pass_kind, ItemRenderer.Pass.CARRIED, "carried pass")
	check_eq(view.ground_item_renderer.pass_kind, ItemRenderer.Pass.GROUND, "ground pass")
	view.free()
