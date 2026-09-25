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
	registry.register_renderer("prop:plant", PlantLook)
	registry.register_renderer("prop:grass", PlantLook)
	# Refuse on middens (MiddenRenderer).
	registry.register_renderer("refuse:soil_clump", RefuseLooks.SoilClump)
	registry.register_renderer("refuse:husk", RefuseLooks.Husk)
	registry.register_renderer("refuse:corpse", RefuseLooks.DeadAnt)
	registry.register_renderer("refuse:brood_corpse", RefuseLooks.DeadLarva)
	registry.register_renderer("refuse:remnant", RefuseLooks.Remnant)
