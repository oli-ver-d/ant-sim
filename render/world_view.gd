class_name WorldView
extends Node2D
## Builds and owns all renderers for one Simulation, layered bottom to top:
## ground, obstacles, pheromones, nests, food, ants, carried items.
## Food and nest renderers are looked up in the Registry by type id
## ("food:<type>", "nest:<type>"), and must provide bind(sim, target).

const GROUND_COLOR := Color(0.16, 0.11, 0.07)

var sim: Simulation
var registry: Registry
var pheromone_renderer: PheromoneRenderer
var ant_renderer: AntRenderer
var item_renderer: ItemRenderer
## Interpolation between the previous and current tick, in [0, 1].
var alpha: float = 1.0:
	set(v):
		alpha = v
		if ant_renderer != null:
			ant_renderer.alpha = v
			item_renderer.alpha = v

var _ground: ColorRect
var _nest_layer: Node2D
var _food_layer: Node2D
var _bound_food: Dictionary[int, bool] = {}
var _bound_colonies: int = 0

func setup(simulation: Simulation, reg: Registry) -> void:
	sim = simulation
	registry = reg

	_ground = ColorRect.new()
	_ground.color = GROUND_COLOR
	_ground.size = Vector2(sim.config.world_size)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ground)

	var obstacles := ObstacleRenderer.new()
	obstacles.bind(sim)
	add_child(obstacles)

	pheromone_renderer = PheromoneRenderer.new()
	pheromone_renderer.bind(sim)
	add_child(pheromone_renderer)

	_nest_layer = Node2D.new()
	add_child(_nest_layer)
	_food_layer = Node2D.new()
	add_child(_food_layer)

	ant_renderer = AntRenderer.new()
	ant_renderer.bind(sim)
	add_child(ant_renderer)

	item_renderer = ItemRenderer.new()
	item_renderer.bind(sim)
	add_child(item_renderer)

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
