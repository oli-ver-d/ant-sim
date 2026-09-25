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
	registry.register_behaviour("carry_waste", CarryWasteBehaviour.new())
	registry.register_behaviour("dig", DigBehaviour.new())
	registry.register_behaviour("carry_spoil", CarrySpoilBehaviour.new())
	registry.register_behaviour("go_up", GoUpBehaviour.new())
	# Nests with a queen that dig their own underground (ColonyNest).
	registry.register_behaviour("queen", QueenBehaviour.new())
	registry.register_behaviour("nest_role", NestRoleBehaviour.new())
	registry.register_behaviour("nurse", NurseBehaviour.new())
	registry.register_behaviour("tend_queen", TendQueenBehaviour.new())
	registry.register_behaviour("carry_spent", CarrySpentBehaviour.new())

	registry.register_food_source_type("food_pile", FoodPile)
	registry.register_item_type("crumb", Item)
	registry.register_item_type("twig", Item)
	registry.register_item_type("pebble", Item)
	registry.register_item_type("waste", Item)
	registry.register_item_type("spoil", Item)
	registry.register_nest_type("basic_nest", BasicNest)
	registry.register_scenery_type("rock", RockProp)
	registry.register_scenery_type("log", LogProp)
	registry.register_scenery_type("plant", PlantProp)
	registry.register_scenery_type("grass", PlantProp)
