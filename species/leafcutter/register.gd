extends RefCounted
## Leafcutter ant species module: the species definition, procedurally
## generated leaves, and the leafcutter-specific behaviours: cutting leaves,
## minims hitchhiking on fragments, and majors clearing debris off the trail.

func register(registry: Registry) -> void:
	registry.register_species("leafcutter", preload("res://species/leafcutter/leafcutter.tres"))
	registry.register_behaviour("cut_leaf", CutLeafBehaviour.new())
	registry.register_behaviour("assign_role", AssignRoleBehaviour.new())
	registry.register_behaviour("seek_ride", SeekRideBehaviour.new())
	registry.register_behaviour("hitchhike", HitchhikeBehaviour.new())
	registry.register_behaviour("patrol_trail", PatrolTrailBehaviour.new())
	registry.register_behaviour("clear_debris", ClearDebrisBehaviour.new())
	registry.register_food_source_type("leaf", LeafSource)
	registry.register_item_type("leaf_fragment", Item)
	registry.register_renderer("food:leaf", LeafRenderer)
