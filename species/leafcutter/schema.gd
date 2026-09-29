extends RefCounted
## Editor metadata for the leafcutter's scenario options: the fungus nest's
## nest_params and the leaf food source. Registered in register.gd.

const F = preload("res://editor/schema/field_spec.gd")

static func register(registry: Registry) -> void:
	registry.register_schema("nest:fungus_nest", fungus_nest())
	registry.register_schema("food:leaf", leaf())

static func phorids() -> FieldSpec:
	return F.dict({
		"count": F.integer(5, "Flies about").limits(0),
		"reach": F.number(170.0, "How far a fly looks for a carrier").limits(0),
		"dives": F.integer(3, "Dives at one carrier").limits(1),
		"speed": F.number(70.0, "Fly speed in world units per second (dives are 3x)").limits(0),
		"altitude": F.number(9.0, "Height the flies hover at").limits(0),
		"arrive": F.number(2.0, "Seconds between flies turning up").limits(0),
		"clear": F.number(90.0, "Carriers this near the nest entrance are left alone").limits(0),
		"item": F.text("leaf_fragment", "Item type of the carried pieces the flies go for"),
		"seed": F.integer(0, "Random seed of the flies (drawn only, never affects the simulation)"),
	}, "Phorid flies over the leaf line (drawn only)")

static func fungus_nest() -> FieldSpec:
	var under := NestSchema.extend(NestSchema.colony_underground(), {
		"garden_life": F.number(900.0, "Seconds a garden cell lives").limits(0),
		"mould_rate": F.number(0.0000005, "Chance per second a garden cell falls sick").limits(0),
	})
	return NestSchema.extend(NestSchema.colony_nest(), {
		"underground": under,
		"initial_fungus": F.number(60.0, "Fungus mass at the start").limits(0),
		"digest_rate": F.number(0.02, "Substrate the garden digests per second per unit of fungus").limits(0),
		"fungus_yield": F.number(0.6, "Share of digested substrate that becomes fungus (the rest is waste)").limits(0, 1),
		"upkeep_per_ant": F.number(0.0002, "Fungus the colony eats per ant per second").limits(0),
		"chamber_capacity": F.number(150.0, "Fungus one garden chamber holds").limits(1),
		"waste_load": F.number(0.25, "Waste mass a worker carries out at once").limits(0.01),
		"phorids": phorids(),
		"queen_reserve": F.number(30.0, "Body reserves a founding queen feeds her garden with (a sealed nest: 30, else 0)").limits(0),
		"queen_feed_rate": F.number(0.15, "Substrate the queen feeds the garden per second until the first leaf comes in").limits(0),
		"garden_reserve": F.number(0.3, "Share of the gardens' capacity kept back from brood").limits(0, 1),
	})

static func leaf() -> FieldSpec:
	return CoreSchema.food_type({
		"length": F.number(360.0, "Leaf length along the midrib (world units)").limits(10),
		"width": F.number(160.0, "Leaf width (world units)").limits(10),
		"shape": F.choice(["elliptic", "lanceolate"], "elliptic", "Outline profile"),
		"teeth": F.integer(26, "Number of serrations along the edge").limits(0),
		"seed": F.integer(null, "Seed of the outline and veins (default: from the run's random stream)"),
		"mass_per_cell": F.number(0.15, "Food mass of one 3x3 cell of tissue").limits(0),
	}, "A procedurally generated leaf lying on the ground")
