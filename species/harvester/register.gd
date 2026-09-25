extends RefCounted
## Harvester ant species module: collects seeds from seed piles with the core's
## generic behaviours, and stores them in a seed nest (a hole in the ground),
## or in a nest that digs its own granaries (granary_nest: a queen, brood,
## seeds carried down and stored, chaff carried out to the midden).

func register(registry: Registry) -> void:
	registry.register_species("harvester", preload("res://species/harvester/harvester.tres"))
	registry.register_behaviour("store_seed", StoreSeedBehaviour.new())
	registry.register_behaviour("tend_granary", TendGranaryBehaviour.new())
	registry.register_food_source_type("seed_pile", SeedPile)
	registry.register_item_type("seed", Item)
	registry.register_item_type("seed_meal", Item)
	registry.register_item_type("chaff", Item)
	registry.register_nest_type("seed_nest", SeedNest)
	registry.register_nest_type("granary_nest", GranaryNest)
	registry.register_renderer("food:seed_pile", SeedPileRenderer)
	registry.register_renderer("nest:seed_nest", SeedNestRenderer)
	registry.register_renderer("nest:granary_nest", GranaryNestRenderer)
	registry.register_renderer("underground:granary_nest", GranaryUnderground)
	registry.register_renderer("underground_top:granary_nest", CarriedBroodRenderer)
