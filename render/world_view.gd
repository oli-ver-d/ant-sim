class_name WorldView
extends Node2D
## Builds and owns all renderers for one layer of a Simulation.
##
## The surface (layer 0), bottom to top: ground, wet ground (rain),
## obstacles, bridges, nests, pheromone glow, food, ground items (debris),
## ants, carried items, ants riding on carried items, falling rain, debug.
## Food and nest renderers are looked up in the Registry by type id
## ("food:<type>", "nest:<type>"), and must provide bind(sim, target).
##
## An underground layer: soil and dug space (SoilRenderer), the nest's own
## underground renderer ("underground:<nest type>", bind(sim, nest), e.g.
## gardens and brood), portal openings, pheromone glow (hidden by default),
## ground items, ants, carried items, riders, debug. On the surface, nests
## that dig get a spoil heap (SpoilHeapRenderer) under their own renderer.

var sim: Simulation
var registry: Registry
## The layer this view draws.
var layer: int = 0
var pheromone_renderer: PheromoneRenderer
var ant_renderer: AntRenderer
var item_renderer: ItemRenderer
var ground_item_renderer: ItemRenderer
var rider_renderer: AntRenderer
var rain_renderer: RainRenderer
var debug_view: Overlays.DebugView
## Interpolation between the previous and current tick, in [0, 1].
var alpha: float = 1.0:
	set(v):
		alpha = v
		if ant_renderer != null:
			ant_renderer.alpha = v
			item_renderer.alpha = v
			ground_item_renderer.alpha = v
			rider_renderer.alpha = v
			if rain_renderer != null:
				rain_renderer.alpha = v

var _nest_layer: Node2D
var _food_layer: Node2D
var _bound_food: Dictionary[int, bool] = {}
var _bound_colonies: int = 0

## ground_seed varies the soil pattern; debug_readout receives the debug text.
func setup(simulation: Simulation, reg: Registry, ground_seed: float = 0.0, debug_readout: RichTextLabel = null,
		layer_index: int = 0) -> void:
	sim = simulation
	registry = reg
	layer = layer_index
	var surface := layer == 0

	if surface:
		var ground := ColorRect.new()
		ground.size = Vector2(sim.config.world_size)
		ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ground_mat := ShaderMaterial.new()
		ground_mat.shader = preload("res://render/ground.gdshader")
		ground_mat.set_shader_parameter("world_size", Vector2(sim.config.world_size))
		ground_mat.set_shader_parameter("seed", ground_seed)
		ground.material = ground_mat
		add_child(ground)

		# Rain: wet soil goes right on the ground, falling drops on top of everything.
		var wet_layer := Node2D.new()
		add_child(wet_layer)
		rain_renderer = RainRenderer.new()
		rain_renderer.bind(sim, wet_layer)

		var obstacles := ObstacleRenderer.new()
		obstacles.bind(sim)
		add_child(obstacles)

		var bridges := BridgeRenderer.new()
		bridges.bind(sim)
		add_child(bridges)
	else:
		var soil := SoilRenderer.new()
		soil.bind(sim.layers[layer].world, ground_seed)
		add_child(soil)

	# Nests sit on the ground, under the glow of the trails leading into them.
	_nest_layer = Node2D.new()
	add_child(_nest_layer)
	if not surface:
		var portals := PortalRenderer.new()
		portals.bind(sim, layer)
		add_child(portals)

	pheromone_renderer = PheromoneRenderer.new()
	pheromone_renderer.layer = layer
	pheromone_renderer.bind(sim)
	add_child(pheromone_renderer)

	_food_layer = Node2D.new()
	add_child(_food_layer)

	# Items on the ground sit under the ants walking over them.
	ground_item_renderer = ItemRenderer.new()
	ground_item_renderer.ground_layer = true
	ground_item_renderer.layer = layer
	ground_item_renderer.bind(sim)
	add_child(ground_item_renderer)

	ant_renderer = AntRenderer.new()
	ant_renderer.layer = layer
	ant_renderer.bind(sim)
	add_child(ant_renderer)

	item_renderer = ItemRenderer.new()
	item_renderer.layer = layer
	item_renderer.bind(sim)
	add_child(item_renderer)

	# Ants riding on carried items are drawn on top of them.
	rider_renderer = AntRenderer.new()
	rider_renderer.riders_only = true
	rider_renderer.layer = layer
	rider_renderer.bind(sim)
	add_child(rider_renderer)
	if rain_renderer != null:
		add_child(rain_renderer)

	if debug_readout != null:
		debug_view = Overlays.DebugView.new()
		debug_view.layer = layer
		debug_view.bind(sim, debug_readout)
		debug_view.visible = false
		add_child(debug_view)

## Size of the drawn layer in world units.
func world_size() -> Vector2:
	return Vector2(sim.layers[layer].world.size)

func _process(_delta: float) -> void:
	# Pick up colonies and food sources added since the last frame (events, clicks).
	while _bound_colonies < sim.colonies.size():
		var nest := sim.colonies[_bound_colonies].nest
		if layer == 0:
			if nest.underground_layer >= 0:
				var heap := SpoilHeapRenderer.new()
				heap.bind(sim, nest)
				_nest_layer.add_child(heap)
			_attach(_nest_layer, "nest:" + nest.type_id, nest)
		elif nest.underground_layer == layer and registry.renderers.has("underground:" + nest.type_id):
			_attach(_nest_layer, "underground:" + nest.type_id, nest)
		_bound_colonies += 1
	if layer != 0:
		return
	for src in sim.food_sources:
		if not _bound_food.has(src.id):
			_bound_food[src.id] = true
			_attach(_food_layer, "food:" + src.type_id, src)

func _attach(target_layer: Node2D, key: String, target: Object) -> void:
	var script: Script = registry.renderers.get(key)
	if script == null:
		push_warning("No renderer registered for %s" % key)
		return
	var node: Node2D = script.new()
	node.call("bind", sim, target)
	target_layer.add_child(node)
