class_name PropType
extends RefCounted
## A kind of scenery prop, registered by id (Registry.register_scenery_type).
## Stateless: Scenery makes one instance per type and calls build() for each
## prop with the prop's own seeded RNG (never the Simulation's), so props are
## the same for the same scenario seed and never change the simulation's run.
##
## build() fills the prop's position, rotation, footprint, blocks, outline and
## canopy from prop.params. The default stamp() makes the footprint's cells
## blocking; most types only need build().

func build(_prop: Prop, _rng: RandomNumberGenerator) -> void:
	pass

## Claims the prop's footprint in the world (if it blocks).
func stamp(world: World, prop: Prop) -> void:
	if prop.blocks:
		prop.cells = world.add_prop_cells(footprint_cells(world, prop))

## Cells under prop.footprint.
func footprint_cells(world: World, prop: Prop) -> PackedInt32Array:
	var fp := prop.footprint
	match fp.get("shape", ""):
		"circle":
			return world.cells_in_circle(fp["center"], float(fp["radius"]))
		"polygon":
			return world.cells_in_polygon(fp["points"])
		"polyline":
			return world.cells_in_polyline(fp["points"], float(fp["width"]))
	return PackedInt32Array()

# --- Helpers for build() -----------------------------------------------------------------

## Rotation from params "rotation" (degrees), or a random one.
static func rotation_of(params: Dictionary, rng: RandomNumberGenerator) -> float:
	var random := rng.randf() * TAU  # always drawn, so later draws don't depend on it
	return deg_to_rad(float(params["rotation"])) if params.has("rotation") else random

## Closed outline of an ellipse (radii rx, ry, turned by `angle`) with each
## point's radius varied by up to +-lumpy / 2 (smoothed with its neighbours).
static func blob(center: Vector2, rx: float, ry: float, angle: float, lumpy: float,
		rng: RandomNumberGenerator, points: int = 20) -> PackedVector2Array:
	var bumps: PackedFloat32Array = []
	for i in points:
		bumps.append(rng.randf() - 0.5)
	var out: PackedVector2Array = []
	for i in points:
		var b := (bumps[(i + points - 1) % points] + 2.0 * bumps[i] + bumps[(i + 1) % points]) * 0.25
		var a := TAU * i / points
		var k := 1.0 + lumpy * b * 2.0
		out.append(center + Vector2(cos(a) * rx * k, sin(a) * ry * k).rotated(angle))
	return out

## Closed outline of a thick polyline (per-vertex mitred offsets, flat ends).
static func strip_outline(points: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array:
	var left: PackedVector2Array = []
	var right: PackedVector2Array = []
	var n := points.size()
	for i in n:
		var d_in := (points[i] - points[maxi(i - 1, 0)]).normalized()
		var d_out := (points[mini(i + 1, n - 1)] - points[i]).normalized()
		var d := (d_in + d_out).normalized()
		if d == Vector2.ZERO:
			d = d_out if d_out != Vector2.ZERO else d_in
		var side := d.orthogonal() * widths[i] * 0.5
		left.append(points[i] + side)
		right.append(points[i] - side)
	right.reverse()
	return left + right

static func params_points(v: Variant) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p: Variant in v:
		out.append(params_vec2(p))
	return out

static func params_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	var a: Array = v
	return Vector2(a[0], a[1])
