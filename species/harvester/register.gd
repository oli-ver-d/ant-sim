extends RefCounted
## Harvester ant species module: collects seeds from seed piles with the core's
## generic behaviours, and stores them in a seed nest.

func register(registry: Registry) -> void:
	registry.register_species("harvester", preload("res://species/harvester/harvester.tres"))
	registry.register_food_source_type("seed_pile", SeedPile)
	registry.register_item_type("seed", Item)
	registry.register_nest_type("seed_nest", SeedNest)
	registry.register_renderer("food:seed_pile", SeedPileRenderer)
	registry.register_renderer("nest:seed_nest", SeedNestRenderer)
