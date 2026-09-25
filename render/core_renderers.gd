class_name CoreRenderers
extends RefCounted
## Registers renderers for the core's generic food and nest types and scenery props.
## Species modules register renderers for their own types in register.gd.

static func register(registry: Registry) -> void:
	registry.register_renderer("food:food_pile", FoodPileRenderer)
	registry.register_renderer("nest:basic_nest", BasicNestRenderer)
	# Scenery prop looks, baked by PropBaker.
	registry.register_renderer("prop:rock", RockLook)
	registry.register_renderer("prop:log", LogLook)
