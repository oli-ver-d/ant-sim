class_name CoreRenderers
extends RefCounted
## Registers renderers for the core's generic food and nest types.
## Species modules register renderers for their own types in register.gd.

static func register(registry: Registry) -> void:
	registry.register_renderer("food:food_pile", FoodPileRenderer)
	registry.register_renderer("nest:basic_nest", BasicNestRenderer)
