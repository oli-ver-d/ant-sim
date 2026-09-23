extends RefCounted
## Leafcutter ant species module: the species definition, procedurally
## generated leaves, and the cut_leaf behaviour.

func register(registry: Registry) -> void:
	registry.register_species("leafcutter", preload("res://species/leafcutter/leafcutter.tres"))
	registry.register_behaviour("cut_leaf", CutLeafBehaviour.new())
	registry.register_food_source_type("leaf", LeafSource)
	registry.register_item_type("leaf_fragment", Item)
	registry.register_renderer("food:leaf", LeafRenderer)
