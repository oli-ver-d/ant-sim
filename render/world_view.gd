class_name WorldView
extends Node2D
## Builds and owns all renderers for one Simulation, layered bottom to top:
## ground, obstacles, nests, pheromone glow, food, ants, carried items, debug.
## Food and nest renderers are looked up in the Registry by type id
## ("food:<type>", "nest:<type>"), and must provide bind(sim, target).

var sim: Simulation
var registry: Registry
var pheromone_renderer: PheromoneRenderer
var ant_renderer: AntRenderer
var item_renderer: ItemRenderer
var debug_view: Overlays.DebugView
## Interpolation between the previous and current tick, in [0, 1].
var alpha: float = 1.0:
	set(v):
		alpha = v
		if ant_renderer != null:
			ant_renderer.alpha = v
			item_renderer.alpha = v

var _nest_layer: Node2D
var _food_layer: Node2D
var _bound_food: Dictionary[int, bool] = {}
var _bound_colonies: int = 0

## ground_seed varies the soil pattern; debug_readout receives the debug text.
func setup(simulation: Simulation, reg: Registry, ground_seed: float = 0.0, debug_readout: RichTextLabel = null) -> void:
	sim = simulation
	registry = reg

	var ground := ColorRect.new()
	ground.size = Vector2(sim.config.world_size)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = preload("res://render/ground.gdshader")
	ground_mat.set_shader_parameter("world_size", Vector2(sim.config.world_size))
	ground_mat.set_shader_parameter("seed", ground_seed)
	ground.material = ground_mat
	add_child(ground)

	var obstacles := ObstacleRenderer.new()
	obstacles.bind(sim)
	add_child(obstacles)

	# Nests sit on the ground, under the glow of the trails leading into them.
	_nest_layer = Node2D.new()
	add_child(_nest_layer)

	pheromone_renderer = PheromoneRenderer.new()
	pheromone_renderer.bind(sim)
	add_child(pheromone_renderer)

	_food_layer = Node2D.new()
	add_child(_food_layer)

	ant_renderer = AntRenderer.new()
	ant_renderer.bind(sim)
	add_child(ant_renderer)

	item_renderer = ItemRenderer.new()
	item_renderer.bind(sim)
	add_child(item_renderer)

	if debug_readout != null:
		debug_view = Overlays.DebugView.new()
		debug_view.bind(sim, debug_readout)
		debug_view.visible = false
		add_child(debug_view)

func _process(_delta: float) -> void:
	# Pick up colonies and food sources added since the last frame (events, clicks).
	while _bound_colonies < sim.colonies.size():
		var nest := sim.colonies[_bound_colonies].nest
		_attach(_nest_layer, "nest:" + nest.type_id, nest)
		_bound_colonies += 1
	for src in sim.food_sources:
		if not _bound_food.has(src.id):
			_bound_food[src.id] = true
			_attach(_food_layer, "food:" + src.type_id, src)

func _attach(layer: Node2D, key: String, target: Object) -> void:
	var script: Script = registry.renderers.get(key)
	if script == null:
		push_warning("No renderer registered for %s" % key)
		return
	var node: Node2D = script.new()
	node.call("bind", sim, target)
	layer.add_child(node)
