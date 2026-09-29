class_name ScenerySchema
extends RefCounted
## Surface content of the scenario format: obstacles, ground materials and
## regions, scenery props and scatters, debris. See ScenarioSchema.

const F = preload("res://editor/schema/field_spec.gd")

## Core registered schemas: "scenery:<prop type>".
static func register(schema: ScenarioSchema) -> void:
	schema.add("scenery:rock", rock())
	schema.add("scenery:log", log_prop())
	schema.add("scenery:plant", plant("plant"))
	schema.add("scenery:grass", plant("grass"))

# --- Shapes -----------------------------------------------------------------

static func _points(help_text: String = "Polyline points [[x, y], ...]") -> FieldSpec:
	return F.points(help_text)

## An obstacle-style shape (also the scatter's "clear" zones): "polyline" (a
## strip of `width`), "polygon", "rect" or "circle".
static func shape_variant(extra: Dictionary, help_text: String) -> FieldSpec:
	var poly := {
		"points": _points().req(),
		"width": F.number(16.0, "Strip width (world units)").limits(1),
	}
	poly.merge(extra)
	var polygon := {"points": _points("Polygon corners [[x, y], ...]").req()}
	polygon.merge(extra)
	var rect := {"rect": F.rect(null, "Rectangle [x, y, w, h]").req()}
	rect.merge(extra)
	var circle := {
		"center": F.vec2(null, "Centre [x, y]").req(),
		"radius": F.number(null, "Radius (world units)").req().limits(1),
	}
	circle.merge(extra)
	return F.variant("shape", {
		"polyline": F.dict(poly), "polygon": F.dict(polygon),
		"rect": F.dict(rect), "circle": F.dict(circle),
	}, help_text)

# --- Obstacles --------------------------------------------------------------

## An obstacle (the "obstacles" list, and add/remove_obstacle events).
static func obstacle() -> FieldSpec:
	var extra := {
		"kind": F.choice(["wall", "water", "bridge"], "wall",
				"wall blocks ants, water blocks them too but is drawn as water, bridge is a walkable twig strip over either (polyline only)"),
		"look": F.choice(["rock"], null, "Draw a wall as a rock prop over exactly its cells"),
		"name": F.text("", "Name of the rock prop (for remove_scenery)"),
	}
	extra.merge(rock_look())
	return shape_variant(extra, "Walls, water or a bridge")

## The rock look keys shared by rock props and rock-look walls.
static func rock_look() -> Dictionary:
	return {
		"stone": F.choice(["granite", "sandstone", "basalt"], null, "Kind of stone (random if absent)"),
		"lichen": F.number(null, "Lichen cover 0..1 (random if absent)").limits(0, 1),
		"moss": F.number(null, "Moss cover 0..1 (from the ground if absent)").limits(0, 1),
		"height": F.number(1.0, "How tall it stands, scales its shadow").limits(0),
	}

# --- Ground -----------------------------------------------------------------

## GroundMap.MATERIALS; the first is what is left over.
const MATERIALS: Array[String] = ["soil", "sand", "gravel", "moss", "litter", "dry"]

## "ground": a material name (short for {"base": material}) or a dict.
static func ground() -> FieldSpec:
	var material := F.choice(MATERIALS, "soil", "Ground material")
	return F.any_of([
		material,
		F.dict({
			"base": F.choice(MATERIALS, "soil", "Material everywhere to start with"),
			"regions": F.list(ground_region(), "Regions painted in order, later over earlier"),
		}, "Ground materials"),
	], "Ground materials (render only): a material name or a base plus regions")

static func ground_region() -> FieldSpec:
	return F.dict({
		"material": F.choice(MATERIALS, null, "Material painted").req(),
		"shape": F.choice(["circle", "rect", "polygon"], null, "Shape covered (absent: the whole world)"),
		"center": F.vec2([0, 0], "Circle centre [x, y]"),
		"radius": F.number(0.0, "Circle radius (world units)").limits(0),
		"rect": F.rect(null, "Rectangle [x, y, w, h]"),
		"points": F.points("Polygon corners [[x, y], ...]"),
		"soft": F.number(40.0, "Edge width (world units)").limits(1),
		"ragged": F.number(null, "How far noise pushes the edge in and out (default soft * 0.8)").limits(0),
		"strength": F.number(1.0, "How much it covers what was there, 0..1").limits(0, 1),
		"noise": F.dict({
			"scale": F.number(300.0, "Patch size (world units)").limits(20, 2000),
			"cover": F.number(0.5, "Fraction of the region covered by patches").limits(0, 1),
			"soft": F.number(0.15, "Patch edge width in noise terms").limits(0, 1),
		}, "Paint only noisy patches of the region"),
	}, "A ground region")

# --- Scenery ----------------------------------------------------------------

## A "scenery" entry: a scatter, or a prop whose "type" picks its keys
## ("scenery:<type>").
static func scenery_item() -> FieldSpec:
	return F.any_of([
		F.dict({"scatter": scatter().req()}, "Scatter props over an area from a preset"),
		F.variant("type", {}, "A scenery prop").with_registry_variants("scenery"),
	], "A scenery prop or scatter")

## Keys every prop takes (Prop, PropType).
static func prop_common() -> Dictionary:
	return {
		"name": F.text("", "Name, for remove_scenery events"),
		"rotation": F.number(null, "Rotation in degrees (random if absent)"),
		"scale": F.number(1.0, "Size factor").limits(0.05),
		"blocks": F.boolean(true, "Whether the footprint blocks ants"),
	}

static func rock() -> FieldSpec:
	var fields := {"center": F.vec2(null, "Centre [x, y]").req(),
		"radius": F.number(40.0, "Long radius (world units)").limits(1),
		"flat": F.number(0.8, "Short radius over the long one").limits(0.2, 1),
		"lumpy": F.number(0.25, "How lumpy the outline is").limits(0, 1),
	}
	fields.merge(rock_look())
	fields.merge(prop_common())
	return F.dict(fields, "A boulder that blocks ants")

static func log_prop() -> FieldSpec:
	var fields := {"points": _points("Axis points [[x, y], ...], sawn end first").req(),
		"width": F.number(30.0, "Width at the first point").limits(1),
		"taper": F.number(0.6, "Width at the last point over the first").limits(0.1, 2),
		"stubs": F.integer(null, "Side branch stubs (random 0-2 if absent)").limits(0),
		"peel": F.number(null, "Bare patches 0..1 (random if absent)").limits(0, 1),
	}
	fields.merge(prop_common())
	return F.dict(fields, "A fallen log or branch that blocks ants")

## A plant, or the grass type (stem 0 by default: canopy only).
static func plant(type_id: String) -> FieldSpec:
	var fields := {"center": F.vec2(null, "Centre [x, y]").req(),
		"radius": F.number(null, "Canopy reach (world units; kind's default if absent)").limits(1),
		"stem": F.number(null, "Stem radius, blocks ants if above 0 (kind's default if absent)").limits(0),
		"blades": F.integer(null, "Number of blades, stalks or fronds (random if absent)").limits(1),
	}
	if type_id == "plant":
		fields["kind"] = F.choice(["rosette", "clover", "fern", "seedling", "grass"], "rosette", "Kind of plant")
	fields.merge(prop_common())
	return F.dict(fields, "A plant" if type_id == "plant" else "A grass clump")

static func scatter() -> FieldSpec:
	return F.dict({
		"preset": F.choice(["meadow", "forest_floor", "rocky", "sandy"], "meadow", "What to scatter"),
		"density": F.number(1.0, "Darts thrown relative to the preset").limits(0),
		"blocking": F.boolean(true, "false keeps only plants and grass, cut to their canopy, so the run is unchanged"),
		"rect": F.rect(null, "Area [x, y, w, h] (default: the whole world)"),
		"keep_clear": F.number(30.0, "Margin kept round nests and food").limits(0),
		"avoid": F.list(F.choice(["nests", "food", "portals"]), "What to keep clear (default: all three)"),
		"clear": F.list(shape_variant({
			"reserve": F.boolean(false, "Only keep blocking props out (a plant keeps its canopy)"),
		}, "Shape to keep clear"), "Extra shapes to keep clear (polylines are paths, width 40 by default)"),
		"reserve": F.number(1.0, "Scale of the room kept round nests for middens and later entrances").limits(0),
		"seed": F.integer(null, "Seed of this scatter (default: from the scenario seed)"),
		"per_mu": F.number(null, "Darts per million square units at density 1 (replaces the preset's)").limits(0),
		"entries": F.list(scatter_entry(), "Prop entries (replace the preset's)"),
	}, "Scatter props over an area from a preset")

static func scatter_entry() -> FieldSpec:
	return F.dict({
		"type": F.choice([], null, "Scenery type").from_registry("scenery_types").req(),
		"kind": F.choice(["rosette", "clover", "fern", "seedling", "grass"], null, "Plant kind"),
		"w": F.number(null, "Weight among the entries").req().limits(0),
		"size": F.raw("[min, max] radius (a log's length)").req(),
		"spacing": F.number(1.0, "How close its reach may come to others' (1 = not overlapping)").limits(0),
		"prefer": F.map(F.number(1.0).limits(0), "", "Weight factor per ground material (1 if absent)"),
		"params": F.map(F.raw(), "", "Extra prop params; [a, b] picks a random value in that range"),
	}, "A prop entry of a scatter")

# --- Debris -----------------------------------------------------------------

## A debris piece (Debris.create); omitted values are random.
static func debris() -> FieldSpec:
	return F.dict({
		"type": F.choice(["twig", "pebble"], "twig", "Kind of debris"),
		"pos": F.vec2(null, "Position [x, y]").req(),
		"rotation": F.number(null, "Rotation in degrees (random if absent)"),
		"length": F.number(null, "Twig length, world units (random 24-44)").limits(1),
		"radius": F.number(null, "Pebble radius, world units (random 3.5-6.5)").limits(1),
		"mass": F.number(null, "Item mass (default from the size)").limits(0),
	}, "A twig or pebble ants can carry and that slows them")
