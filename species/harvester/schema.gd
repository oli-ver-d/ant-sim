extends RefCounted
## Editor metadata for the harvester's scenario options: the seed and granary
## nests' nest_params and the seed pile food source. Registered in register.gd.

const F = preload("res://editor/schema/field_spec.gd")

static func register(registry: Registry) -> void:
	registry.register_schema("nest:seed_nest", seed_nest())
	registry.register_schema("nest:granary_nest", granary_nest())
	registry.register_schema("food:seed_pile", seed_pile())

static func seed_nest() -> FieldSpec:
	return NestSchema.extend(NestSchema.basic_nest(), {
		"disc_radius": F.number(70.0, "Radius of the disc cleared of plants round the entrance").limits(0),
	})

static func granary_nest() -> FieldSpec:
	return NestSchema.extend(NestSchema.colony_nest(), {
		"upkeep_per_ant": F.number(0.0002, "Stored seed the colony eats per ant per second").limits(0),
		"granary_capacity": F.number(60.0, "Seed mass a granary chamber of radius 40 holds (by area; the royal chamber a third)").limits(1),
		"initial_seeds": F.integer(0, "Seeds in the founding queen's cache in the royal chamber").limits(0),
		"seed_mass": F.number(0.4, "Mass of each cached seed").limits(0),
		"ants_per_chamber": F.number(120.0, "Colony size each dug chamber serves before another is planned").limits(1),
		"husk": F.number(0.3, "Share of an eaten seed's mass left as chaff").limits(0, 1),
		"chaff_load": F.number(0.3, "Chaff mass a worker carries out at once").limits(0.01),
		"disc_radius": F.number(70.0, "Radius of the disc cleared of plants round the entrance").limits(0),
	})

static func seed_pile() -> FieldSpec:
	return CoreSchema.food_type({
		"radius": F.number(30.0, "Radius the seeds are scattered over (denser in the middle)").limits(1),
		"count": F.integer(150, "Number of seeds").limits(0),
		"seed_size": F.number(2.4, "Half-length of a seed (world units)").limits(0.1),
		"seed_mass": F.number(0.4, "Mass of each seed").limits(0),
		"seed": F.integer(null, "Seed of the scatter (default: from the run's random stream)"),
	}, "A scattered cluster of individual seeds")
