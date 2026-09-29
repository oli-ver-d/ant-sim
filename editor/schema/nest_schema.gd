class_name NestSchema
extends RefCounted
## Core nest params ("nest_params" of a colony) per nest type: registered as
## "nest:<nest type>". Species nests register their own schema (usually
## extending colony_nest() with extend()) in their register.gd. See
## ScenarioSchema.
##
## Sources: sim/nests/nest_type.gd (entrance, midden, dump, underground),
## colony_nest.gd (economy, roles, entrances, nurseries), brood.gd,
## nest_chambers.gd, highways.gd, founding.gd, alates.gd.

const F = preload("res://editor/schema/field_spec.gd")

static func register(schema: ScenarioSchema) -> void:
	schema.add("nest:basic_nest", basic_nest())

## A new dict spec: `base`'s fields, then `extra`'s (which win on a clash).
static func extend(base: FieldSpec, extra: Dictionary) -> FieldSpec:
	var fields := base.fields.duplicate()
	fields.merge(extra, true)
	return F.dict(fields, base.help)

## BasicNest: a hole that turns delivered food mass into ants.
static func basic_nest() -> FieldSpec:
	var fields := nest_type_fields()
	fields.merge({
		"ant_cost": F.number(5.0, "Food mass per new ant").limits(0),
		"max_population": F.integer(1000, "No new ants above this population").limits(0),
	})
	return F.dict(fields, "A hole in the ground that turns delivered food into new ants")

## Keys every nest type reads (NestType.setup).
static func nest_type_fields() -> Dictionary:
	return {
		"radius": F.number(12.0, "Distance from the entrance at which an ant counts as at the nest").limits(1),
		"sense_radius": F.number(60.0, "Distance from which returning ants see the entrance and head for it").limits(1),
		"entrance": entrance(),
		"midden": midden(),
		"dump": F.vec2([120, 40], "One fixed refuse site, relative to the nest (default: a midden is sited as needed)"),
		"underground": underground_base(),
	}

## How the entrances look (render only), and the disc kept clear round them.
static func entrance() -> FieldSpec:
	return F.dict({
		"style": F.choice(["hole", "crater", "mound", "turret"], "hole", "Entrance look: plain hole, ring of grit, low cone of soil, or raised collar"),
		"clear_radius": F.number(0.0, "Radius of the disc kept clear round the entrance at full size (0 = none)").limits(0),
		"clears_plants": F.boolean(false, "Plants and litter are cleared from that disc"),
	}, "Entrance look and cleared disc")

## Where refuse goes (NestType refuse, Midden).
static func midden() -> FieldSpec:
	return F.dict({
		"style": F.choice(["pile", "ring", "scatter"], "pile", "Where loads land: a spreading heap, an arc of a band round the nest, or loose deposits"),
		"distance": F.vec2([100, 200], "Nearest and furthest distance of a midden from the entrance"),
		"sites": F.integer(2, "Middens sited round the nest").limits(1),
		"capacity": F.number(30.0, "Refuse mass a midden takes before the next one is sited").limits(0),
		"avoid_trails": F.boolean(true, "Site middens away from foraging trails"),
	}, "Refuse dumps")

# --- Underground -------------------------------------------------------------

## Soil texture of the nest layer (World.add_soil_texture).
static func texture() -> FieldSpec:
	return F.dict({
		"clay": F.number(0.16, "Share of cells in clay patches").limits(0, 1),
		"clay_hardness": F.number(2.2, "Digging work multiplier of clay").limits(1),
		"roots": F.number(0.05, "Share of cells with roots").limits(0, 1),
		"root_hardness": F.number(3.0, "Digging work multiplier of roots").limits(1),
		"stones": F.number(5.0, "Stones per 10,000 cells").limits(0),
		"rocks": F.number(4.0, "Big rocks per 100,000 cells").limits(0),
		"pebbles": F.number(0.002, "Share of cells holding a pebble").limits(0, 1),
	}, "Clay, roots and stones in the soil")

## A shape dug out at the start: a capsule (from/to/radius), a disc (center/radius)
## or ellipses (lobes).
static func carve_shape() -> FieldSpec:
	return F.dict({
		"from": F.vec2(null, "Start of a capsule"),
		"to": F.vec2(null, "End of a capsule (default: the start)"),
		"center": F.vec2(null, "Centre of a disc (same as from)"),
		"radius": F.number(10.0, "Radius of the capsule or disc").limits(1),
		"lobes": F.list(F.number(), "Flat list of ellipses: x, y, rx, ry, angle for each"),
		"rough": F.number(0.0, "Outline roughness of the ellipses (world units)").limits(0),
		"seed": F.integer(0, "Roughness seed of the ellipses"),
	}, "A cavity carved out at the start")

## A digging job the colony works on (ExcavationPlan, DigShape).
static func plan_job() -> FieldSpec:
	return F.dict({
		"name": F.text("", "Job name (a job called \"entrance\" opens the sealed entrance when done)"),
		"priority": F.number(0.0, "Higher priority jobs are dug first"),
		"diggers": F.integer(4, "Workers digging it at once").limits(1),
		"from": F.vec2(null, "Start of a capsule job"),
		"to": F.vec2(null, "End of a capsule job (default: the start)"),
		"radius": F.number(7.0, "Radius of a capsule, or of path points without radii").limits(1),
		"path": F.points("A tunnel dug along these points"),
		"radii": F.list(F.number(), "Radius at each path point"),
		"lobes": F.list(F.number(), "A chamber of ellipses: x, y, rx, ry, angle for each"),
		"origin": F.vec2(null, "Where diggers start (default: the shape's start)"),
		"face": F.vec2(null, "Where a blob job is first dug from (default: the origin)"),
	}, "A shape the colony digs")

## Highways: busy tunnels widen (Highways).
static func highways() -> FieldSpec:
	return F.dict({
		"check_every": F.number(20.0, "Seconds between traffic checks").limits(1),
		"threshold": F.number(45.0, "Traffic per unit length above which a section is busy").limits(0),
		"sustain": F.integer(3, "Checks in a row above the threshold before widening").limits(1),
		"grow": F.number(1.35, "Radius multiplier of a widening").limits(1),
		"max_radius": F.number(14.0, "Widest a tunnel gets (world units)").limits(1),
		"section": F.number(50.0, "Length of a watched section (world units)").limits(5),
		"bypass": F.number(1.8, "A full-width section this many times over the threshold gets a bypass").limits(1),
		"max_bypasses": F.integer(6, "Bypasses dug at most").limits(0),
		"priority": F.number(35.0, "Plan priority of the widening jobs (after chambers)"),
		"half_life": F.number(60.0, "Half-life of the traffic map (s)").limits(1),
		"lanes": F.number(0.8, "Lane strength of the layer (SimLayer.lanes)").limits(0),
	}, "Busy tunnels widen and get bypasses")

## The nest layer, as NestType builds it (any nest type).
static func underground_base() -> FieldSpec:
	return F.dict(underground_base_fields(), "The nest's own underground layer")

static func underground_base_fields() -> Dictionary:
	return {
		"size": F.size([1280, 1280], "Layer size in world units"),
		"cell_size": F.integer(4, "World units per soil cell").limits(1),
		"hardness": F.number(1.0, "Digging work of plain soil").limits(0),
		"shaft": F.vec2(null, "Where the entrance shaft comes down (default: the layer's centre)"),
		"shaft_radius": F.number(10.0, "Radius of the shaft").limits(1),
		"open": F.boolean(true, "False: sealed, no entrance until dug open (a founding nest)"),
		"spoil": F.vec2([-70, 40], "Where spoil is dropped on the surface, relative to the entrance"),
		"texture": texture(),
		"carve": F.list(carve_shape(), "Cavities dug out from the start"),
		"keep_clear": F.list(F.raw("[x, y, radius]"), "Circles [x, y, radius] kept free of stones and roots"),
		"plan": F.list(plan_job(), "Jobs the colony digs"),
		"bite": F.number(1.2, "Work removed from a soil cell per bite").limits(0),
		"overdig": F.number(0.0, "Roughness of dug outlines (world units; colony nests default to 4.5)").limits(0),
		"ragged": F.number(6.0, "How uneven the digging face is (0 = always the best ranked cell)").limits(0),
		"highways": F.any_of([highways(), F.boolean(false)], "Widen busy tunnels (a dict of settings; false = off)"),
	}

# --- Colony nests ------------------------------------------------------------

## Brood model (Brood) with care (ColonyNest always turns care on underground).
static func brood() -> FieldSpec:
	return F.dict({
		"lay_interval": F.number(4.0, "Seconds between eggs at most").limits(0.05),
		"egg": F.number(40.0, "Seconds as an egg").limits(0),
		"larva": F.number(90.0, "Seconds as a larva (only while fed)").limits(0),
		"pupa": F.number(60.0, "Seconds as a pupa").limits(0),
		"callow": F.number(8.0, "Seconds as a callow before emerging").limits(0),
		"max_brood": F.integer(80, "Brood items at most").limits(0),
		"initial": F.dict({
			"egg": F.integer(0, "Eggs at the start").limits(0),
			"larva": F.integer(0, "Larvae at the start").limits(0),
			"pupa": F.integer(0, "Pupae at the start").limits(0),
		}, "Brood the nest starts with, spread through each stage"),
		"dirt_rate": F.number(1.0 / 90.0, "How fast brood gets dirty (per second)").limits(0),
		"hunger_rate": F.number(1.0 / 40.0, "How fast larvae get hungry (per second)").limits(0),
		"starve_time": F.number(120.0, "Seconds a larva can be fully hungry before it dies").limits(0),
		"brood_per_worker": F.number(2.5, "Brood each worker can look after before care falls short").limits(0),
		"first_caste": F.integer(-1, "Caste index of the first workers (default: the nest's founding caste)"),
		"first_workers": F.integer(12, "Workers raised in the first caste before the others").limits(0),
	}, "Egg-to-worker brood model")

## A founding queen who lands first (Founding).
static func landing() -> FieldSpec:
	return F.dict({
		"from": F.vec2(null, "Surface point under her at the start (default: up and left of the landing)"),
		"land": F.vec2(null, "Where she lands (default: 30 units from the entrance toward from)"),
		"altitude": F.number(220.0, "Height she starts at").limits(0),
		"flight": F.number(9.0, "Seconds of flight").limits(0.1),
		"shed": F.number(6.0, "Seconds shedding her wings").limits(0),
		"loop_radius": F.number(14.0, "Radius of her walk round the nest site").limits(0),
		"dig": F.number(20.0, "Seconds digging the entrance").limits(0),
		"spoil_pellets": F.integer(6, "Spoil pellets put on the heap while digging").limits(0),
		"wing_life": F.number(900.0, "Seconds the shed wings lie there").limits(0),
	}, "The queen's landing and first digging")

## Winged reproductives and their nuptial flight (Alates).
static func alates() -> FieldSpec:
	return F.dict({
		"from_population": F.integer(400, "Colony size at which the queen starts laying alates").limits(0),
		"count": F.integer(12, "Alates raised").limits(0),
		"castes": F.map(F.number(1.0).limits(0), "castes", "Weight of each alate caste (default: every alate caste, 1)"),
		"stagger": F.number(0.8, "Seconds between alates setting off up").limits(0),
		"gather": F.number(12.0, "Seconds after the flight is called before take-off starts").limits(0),
		"every": F.number(1.2, "Seconds between take-offs").limits(0.05),
		"settle": F.number(3.0, "Seconds on the mound before taking off").limits(0),
		"warm_up": F.number(0.8, "Seconds beating wings on the ground").limits(0),
		"climb": F.number(7.0, "Seconds climbing to full altitude").limits(0.1),
		"altitude": F.number(420.0, "Height reached").limits(0),
		"distance": F.number(260.0, "Distance drifted off while climbing").limits(0),
		"drift": F.vec2([0.5, -1.0], "Direction of the drift (normalised)"),
		"spread": F.number(0.9, "Radians the directions fan over").limits(0),
		"gather_radius": F.number(45.0, "Radius of the mound they gather on (they keep off its inner fifth)").limits(1),
		"escort": F.integer(10, "Surface workers milling round the alates").limits(0),
		"escort_reach": F.number(160.0, "How far an escort looks for the flight").limits(0),
	}, "Alates and the nuptial flight (needs an underground)")

## The nest layer of a ColonyNest: NestType's keys plus the chambers' (NestChambers).
static func colony_underground() -> FieldSpec:
	var fields := underground_base_fields()
	fields.merge({
		"royal": F.vec2(null, "Centre of the royal chamber (default: the layer's centre)"),
		"royal_radius": F.number(36.0, "Radius of the royal chamber").limits(5),
		"shaft_distance": F.number(46.0, "Distance of the shaft from the royal chamber's edge").limits(0),
		"shaft_hardness": F.number(3.0, "Digging work multiplier of a sealed shaft").limits(1),
		"chamber_min_radius": F.number(38.0, "Smallest new chamber radius").limits(5),
		"chamber_max_radius": F.number(62.0, "Largest new chamber radius").limits(5),
		"tunnel_radius": F.number(7.0, "Radius of secondary tunnels (mains are 1.35 times, capillaries 0.72)").limits(1),
		"overdig": F.number(4.5, "Roughness of dug outlines (world units)").limits(0),
	}, true)
	return F.dict(fields, "The nest's own underground layer (chambers, shaft, soil)")

## Everything ColonyNest and its helpers read from nest_params.
static func colony_nest() -> FieldSpec:
	var fields := nest_type_fields()
	fields.merge({
		"ant_cost": F.number(1.5, "Food mass per new ant (a larva eats this over its stage)").limits(0),
		"brood_reserve": F.number(30.0, "Food stock below which the queen stops laying").limits(0),
		"brood_rate": F.number(0.004, "New ants per second per unit of food stock").limits(0),
		"max_population": F.integer(3000, "No new ants above this population").limits(0),
		"max_chambers": F.integer(5, "Chambers dug at most").limits(1),
		"underground": colony_underground(),
		"brood": brood(),
		"open_entrance_at": F.integer(4, "Workers needed before a sealed nest digs its entrance open").limits(1),
		"brood_per_nurse": F.number(2.5, "Larvae a nurse can feed (eggs and pupae: four times as many)").limits(0.1),
		"retinue_max": F.integer(5, "Workers tending the queen at most").limits(1),
		"dig_fraction": F.number(0.3, "Share of the colony that digs when there is work").limits(0, 1),
		"inside_share": F.number(0.6, "Share of a caste that works inside when no role is short").limits(0, 1),
		"queen_groom_time": F.number(60.0, "Seconds a grooming keeps the queen laying at full pace").limits(0),
		"initial_chambers": F.integer(0, "Chambers already dug at the start (an established nest)").limits(0),
		"nurseries": F.dict({
			"population": F.integer(80, "Colony size at which eggs, larvae and pupae each get a chamber").limits(0),
			"chambers": F.integer(3, "Chambers dug (royal included) before the nurseries are planned").limits(1),
			"carve": F.boolean(false, "Carve the nurseries at the start"),
		}, "Separate chambers for each brood stage"),
		"entrances": F.dict({
			"at": F.list(F.integer().limits(0), "Colony sizes at which another entrance is dug"),
			"spacing": F.number(150.0, "How far apart entrances are (world units)").limits(0),
		}, "More entrances as the colony grows"),
		"founding": F.dict({
			"landing": landing(),
		}, "A founding queen who arrives first"),
		"alates": alates(),
	}, true)
	return F.dict(fields, "A nest with a queen, brood and (optionally) an underground it digs itself")
