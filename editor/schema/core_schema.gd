class_name CoreSchema
extends RefCounted
## The top level of the scenario format: metadata, colonies, food, events,
## agent caps, playback (duration, warmup, speed schedule, camera), render and
## presentation settings and the output frame. Ground, scenery, obstacles and
## debris are in ScenerySchema, nest params in NestSchema, state params and
## channels in BehaviourSchema. See ScenarioSchema.

const F = preload("res://editor/schema/field_spec.gd")

## Core registered schemas: "food:food_pile".
static func register(schema: ScenarioSchema) -> void:
	schema.add("food:food_pile", food_pile())

static func root(schema: ScenarioSchema) -> FieldSpec:
	return F.dict({
		"name": F.text("", "Scenario name (usually the file name)"),
		"description": F.text("", "What the scenario shows"),
		"seed": F.integer(1, "Random seed of the run (--seed= overrides it)").limits(0),
		"duration": F.number(null, "Video length in seconds"),
		"warmup": F.number(0.0, "Simulated seconds run before the first frame").limits(0),
		"ticks_per_frame": ticks_per_frame(),
		"camera": camera(),
		"render": render(),
		"output": output(),
		"colonies": F.list(colony(schema), "Colonies placed at load time"),
		"food": F.list(food(), "Food sources placed at load time"),
		"obstacles": F.list(ScenerySchema.obstacle(), "Walls, water, bridges"),
		"ground": ScenerySchema.ground(),
		"scenery": F.list(ScenerySchema.scenery_item(), "Surface props and scatters"),
		"debris": F.list(ScenerySchema.debris(), "Loose twigs and pebbles"),
		"events": F.list(event(schema), "Timed events (t in simulated seconds)"),
		"max_agents": F.dict({
			"surface": F.integer(null, "Agents on the surface beyond which colonies grow abstractly").limits(0),
			"nest": F.integer(null, "Agents in each nest's underground").limits(0),
		}, "Agents per layer (Simulation.balance_pools)"),
	})

static func colony(schema: ScenarioSchema) -> FieldSpec:
	return F.dict({
		"species": F.choice([], null, "Species id").from_registry("species").req(),
		"nest": F.vec2(null, "Nest position (world units)").req(),
		"nest_type": F.choice([], "", "Nest type instead of the species' own").from_registry("nest_types"),
		"population": F.map(F.integer(0).limits(0), "castes", "Starting ants per caste"),
		"release_per_second": F.number(0.0, "Ants start inside and emerge at this rate (0 = all at once)").limits(0),
		"params": F.resolved(schema.params_spec, F.map(F.raw(), "params", "SimConfig values and species tunables")),
		"state_params": BehaviourSchema.state_params(),
		"channels": BehaviourSchema.channels(),
		"nest_params": F.resolved(schema.nest_params_spec, F.map(F.raw(), "", "Nest parameters (per nest type)")),
	}, "A colony")

## A food entry: "type" picks the food source type, whose own keys come from
## its schema ("food:<type>").
static func food() -> FieldSpec:
	var s := F.variant("type", {}, "A food source").with_registry_variants("food")
	return s

## Keys every food source takes (FoodSource / Simulation.add_food_source);
## merged into each food type's schema by food_type().
static func food_common() -> Dictionary:
	return {
		"pos": F.vec2([0, 0], "Position (world units)").req(),
		"rotation": F.number(0.0, "Rotation in degrees"),
		"sense_radius": F.number(60.0, "How far beyond its edge an ant can sense the source").limits(0),
	}

## A food type's schema: the common keys plus `own`.
static func food_type(own: Dictionary, help_text: String = "") -> FieldSpec:
	var fields := food_common()
	fields.merge(own)
	return F.dict(fields, help_text)

static func food_pile() -> FieldSpec:
	return food_type({
		"radius": F.number(24.0, "Pile radius (world units)").limits(1),
		"amount": F.integer(200, "Number of crumbs").limits(0),
		"crumb_mass": F.number(1.0, "Mass of each crumb").limits(0),
		"color": F.color(null, "Crumb colour"),
	}, "Circular pile of identical crumbs")

## Playback speed: one number, or points ramped linearly between (ScenarioPlayer).
static func ticks_per_frame() -> FieldSpec:
	return F.any_of([
		F.number(0.5, "Simulation ticks per 60 fps video frame (0.5 = real time at 30 ticks/s)").limits(0),
		F.list(F.dict({
			"t": F.number(0.0, "Video time in seconds").req().limits(0),
			"tpf": F.number(null, "Ticks per frame from this time (ramped linearly between points)").limits(0),
			"jump": F.number(0.0, "Simulated seconds run at once in the first frame at or after t (a time skip to hide under a fade; the cameras snap to their targets)").limits(0),
		}), "Speed schedule"),
	], "Simulation ticks per video frame: a number or a schedule of points")

## Camera keyframes: a list, or {"surface": [...], "nest": [...]} to give the
## nest view (split layout) its own track.
static func camera() -> FieldSpec:
	var frames := F.list(camera_keyframe(), "Camera keyframes (video seconds)")
	return F.any_of([
		frames,
		F.dict({
			"surface": F.list(camera_keyframe(), "Keyframes of the surface camera"),
			"nest": F.list(camera_keyframe(), "Keyframes of the nest (underground) camera; default: fit the excavation"),
		}, "Separate surface and nest camera tracks"),
	], "Camera keyframes")

static func camera_keyframe() -> FieldSpec:
	return F.dict({
		"t": F.number(0.0, "Video time in seconds").req().limits(0),
		"pos": F.vec2(null, "Camera centre (default: the middle of the world)"),
		"zoom": F.number(1.0, "Zoom factor (interpolated in log space)").limits(0.01),
		"ease": F.choice(["linear", "in", "out", "in_out"], "in_out", "Easing towards this keyframe from the previous one"),
		"follow": camera_follow(),
		"smoothing": F.number(0.35, "Follow smoothing: seconds to cover ~63% of the distance (0 locks on)").limits(0),
		"fit": F.choice(["excavation"], null, "Frame everything dug so far on the camera's layer"),
		"margin": F.number(60.0, "Fit: world units added around the dug area").limits(0),
		"min_zoom": F.number(0.3, "Fit: smallest zoom").limits(0.01),
		"max_zoom": F.number(4.0, "Fit: largest zoom").limits(0.01),
	}, "A camera keyframe: pos, follow or fit, with a zoom")

static func camera_follow() -> FieldSpec:
	return F.dict({
		"near": F.vec2([0, 0], "Choose the ant (or brood item) nearest this point"),
		"state": F.choice([], "", "Only ants in this behaviour state").from_registry("states"),
		"colony": F.integer(null, "Only this colony (index)").limits(0),
		"ant": F.any_of([
			F.integer(null, "Ant slot").limits(0),
			F.choice(["same"], "same", "Whatever the story follows now"),
		], "An ant slot, or \"same\" for the story's current target"),
		"brood": F.any_of([
			F.integer(null, "Brood record id").limits(0),
			F.choice(["first", "last", "near"], "first", "The oldest, the newest or the one nearest \"near\""),
		], "Follow a brood item of the colony's nest instead of an ant"),
		"stage": F.choice(["egg", "larva", "pupa"], null, "Brood: only this stage"),
		"across": F.boolean(false, "Keep the ant through portals (the camera showing its layer takes over)"),
		"switch_mode": F.boolean(false, "With across: change the layout mode so the ant's layer is shown"),
	}, "What the camera tracks")

## Everything under "render": presentation (captions, fades, grade), layout,
## story marker and the pheromone overlay.
static func render() -> FieldSpec:
	return F.dict({
		"pheromones": F.boolean(true, "Draw the pheromone overlay"),
		"pheromone_opacity": F.number(0.55, "Opacity of the pheromone overlay").limits(0, 1),
		"captions": F.list(F.dict({
			"t": F.number(0.0, "Video time it starts, seconds").req().limits(0),
			"until": F.number(null, "Video time it ends (default t + 4)").limits(0),
			"text": F.text("", "Caption text (\\n breaks lines, long lines wrap)"),
			"style": F.choice(["title", "chapter", "caption"], "caption", "title (large), chapter (medium) or caption"),
			"pos": F.choice(["top", "middle", "bottom"], "bottom", "Vertical position inside the safe area"),
			"fade": F.number(0.8, "Seconds to fade in after t and out before until").limits(0),
		}), "Text over the frame"),
		"fades": F.list(F.dict({
			"t": F.number(0.0, "Video time in seconds").req().limits(0),
			"to": F.number(0.0, "Opacity of the fade colour from this point (1 = the frame is that colour)").limits(0, 1),
			"color": F.color([0, 0, 0], "Fade colour [r, g, b], 0-1"),
			"ease": F.choice(["linear", "in", "out", "in_out"], "in_out", "Easing towards this point"),
		}), "Full-frame fade points; a missing key keeps the previous point's value"),
		"grade": F.list(F.dict({
			"t": F.number(0.0, "Video time in seconds").req().limits(0),
			"tint": F.color([1.0, 1.0, 1.0], "Tint [r, g, b]"),
			"brightness": F.number(1.0, "Brightness multiplier").limits(0),
			"contrast": F.number(1.0, "Contrast multiplier").limits(0),
			"saturation": F.number(1.0, "Saturation multiplier").limits(0),
			"vignette": F.number(0.0, "Vignette strength").limits(0),
			"ease": F.choice(["linear", "in", "out", "in_out"], "in_out", "Easing towards this point"),
		}), "Colour grade points (dawn, noon, dusk, night); a missing key keeps the previous point's value"),
		"story_marker": F.list(F.dict({
			"t": F.number(0.0, "Video time it appears").req().limits(0),
			"until": F.number(null, "Video time it disappears (default: never)").limits(0),
			"fade": F.number(0.5, "Seconds to fade in and out").limits(0),
		}), "Windows in which a ring marks the ant or brood item the camera story follows"),
		"layout": F.dict({
			"mode": F.choice(["split", "nest", "surface", "normal"], "split", "split (surface and nest), nest (nest full screen) or surface/normal (world full screen)"),
			"colony": F.integer(0, "Colony whose nest is shown").limits(0),
			"surface": F.choice(["top", "bottom"], "top", "Where the surface part sits"),
			"ratio": F.number(0.5, "The surface's share of the frame height").limits(0.2, 0.8),
			"stats": F.boolean(true, "Show the nest's readout"),
			"highlight": F.boolean(true, "Ring new workers emerging on the surface"),
			"modes": F.list(F.dict({
				"t": F.number(0.0, "Video time in seconds").req().limits(0),
				"mode": F.choice(["split", "nest", "surface", "normal"], null, "Layout mode from this time").req(),
			}), "Timed layout changes (the mode stays until the next point)"),
		}, "Split surface/underground layout"),
	}, "Render and presentation settings")

## The output frame (M16b): size and safe-zone preset. Absent = 1080x1920, tiktok.
static func output() -> FieldSpec:
	return F.dict({
		"size": F.size([1080, 1920], "Output frame size in pixels (even width and height)"),
		"safe_zones": F.choice(["tiktok", "youtube_shorts", "none"], "tiktok", "Safe-zone guides drawn over the frame"),
	}, "Output frame")

static func event(schema: ScenarioSchema) -> FieldSpec:
	var t := func() -> FieldSpec: return F.number(0.0, "Simulated seconds when it happens").req().limits(0)
	return F.variant("type", {
		"spawn_food": F.dict({"t": t.call(), "food": food().req()}, "Places a food source"),
		"add_obstacle": F.dict({"t": t.call(), "obstacle": ScenerySchema.obstacle().req()}, "Adds a wall, water or bridge"),
		"remove_obstacle": F.dict({"t": t.call(), "obstacle": ScenerySchema.obstacle().req()}, "Clears the cells of the shape"),
		"add_scenery": F.dict({"t": t.call(), "scenery": F.any_of([ScenerySchema.scenery_item(),
				F.list(ScenerySchema.scenery_item())]).req()}, "Adds scenery props"),
		"remove_scenery": F.dict({
			"t": t.call(),
			"name": F.text(null, "Remove the props with this name"),
			"at": F.vec2(null, "Or the props covering this point"),
		}, "Removes scenery props"),
		"add_colony": F.dict({"t": t.call(), "colony": colony(schema).req()}, "Founds a colony"),
		"rain": F.dict({
			"t": t.call(),
			"duration": F.number(5.0, "Seconds it rains").limits(0),
			"area": F.any_of([
				F.dict({"center": F.vec2(null, "Centre").req(), "radius": F.number(null, "Radius").req().limits(0)}, "A circle"),
				F.dict({"rect": F.rect(null, "[x, y, w, h]").req()}, "A rectangle"),
			], "Where it rains (default: the whole world)"),
			"wash_half_life": F.number(0.0, "Seconds for the pheromone under the rain to halve (0 = wiped at once)").limits(0),
		}, "A shower that washes pheromones away"),
		"drop_debris": F.dict({
			"t": t.call(),
			"debris": F.list(ScenerySchema.debris(), "Pieces to drop"),
			"scatter": F.dict({
				"count": F.integer(5, "Pieces to drop").limits(0),
				"near": F.vec2(null, "Centre of the area").req(),
				"radius": F.number(150.0, "Radius of the area").limits(0),
				"on_channel": F.text("", "Pheromone channel (e.g. c0.food): land on its strongest spots"),
				"min_spacing": F.number(25.0, "Least distance between pieces").limits(0),
				"types": F.list(F.text(), "Debris types to pick from (default twig, pebble)"),
			}, "Drop random pieces near a point"),
		}, "Drops debris"),
		"nuptial_flight": F.dict({
			"t": t.call(),
			"colony": F.integer(null, "Colony index (default: every colony)").limits(0),
		}, "Nests raising alates send them up to fly"),
	}, "A timed event")
