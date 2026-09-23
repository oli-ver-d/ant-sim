class_name CoreModule
extends RefCounted
## Registers the generic, species-independent pieces of the engine.

static func register(registry: Registry) -> void:
	registry.register_behaviour("explore", ExploreBehaviour.new())
	registry.register_behaviour("follow_trail", FollowTrailBehaviour.new())
	registry.register_behaviour("go_to_food", GoToFoodBehaviour.new())
	registry.register_behaviour("carry_home", CarryHomeBehaviour.new())
	registry.register_behaviour("deliver", DeliverBehaviour.new())
	registry.register_behaviour("linger", LingerBehaviour.new())

	registry.register_food_source_type("food_pile", FoodPile)
	registry.register_item_type("crumb", Item)
	registry.register_item_type("twig", Item)
	registry.register_item_type("pebble", Item)
	registry.register_nest_type("basic_nest", BasicNest)
