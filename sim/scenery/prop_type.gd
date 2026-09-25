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

## Claims the prop's footprint in the world (if it blocks). A prop that dresses
## a scenario wall (params "wall") only marks the wall's cells as its own.
func stamp(world: World, prop: Prop) -> void:
	if prop.params.has("wall"):
		prop.cells = world.mark_prop_cells(footprint_cells(world, prop))
	elif prop.blocks:
		prop.cells = world.add_prop_cells(footprint_cells(world, prop))

## Cells under prop.footprint.
func footprint_cells(world: World, prop: Prop) -> PackedInt32Array:
	return shape_cells(world, prop.footprint)

static func shape_cells(world: World, fp: Dictionary) -> PackedInt32Array:
	match fp.get("shape", ""):
		"circle":
			return world.cells_in_circle(fp["center"], float(fp["radius"]))
		"polygon":
			return world.cells_in_polygon(fp["points"])
		"polyline":
			return world.cells_in_polyline(fp["points"], float(fp["width"]))
		"rect":
			return world.cells_in_rect(fp["rect"])
		"multi":
			var seen: Dictionary[int, bool] = {}
			for part: Dictionary in fp["parts"]:
				for c in shape_cells(world, part):
					seen[c] = true
			var out := PackedInt32Array(seen.keys())
			out.sort()
			return out
	return PackedInt32Array()

## True if `at` is inside a footprint shape, as its cells are chosen (a cell is
## in when its centre is): renderers draw a prop's body over this, so what is
## drawn and what blocks agree to within a cell. `cell` is the World's cell
## size (polylines are stamped a little wider than their width).
static func footprint_contains(fp: Dictionary, at: Vector2, cell: float) -> bool:
	match fp.get("shape", ""):
		"circle":
			return at.distance_squared_to(fp["center"]) <= float(fp["radius"]) ** 2
		"polygon":
			return Geometry2D.is_point_in_polygon(at, fp["points"])
		"polyline":
			var pts: PackedVector2Array = fp["points"]
			var r2 := (float(fp["width"]) * 0.5) ** 2 + cell * cell * 0.25
			if pts.size() == 1:
				return at.distance_squared_to(pts[0]) <= r2
			for i in pts.size() - 1:
				if at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1])) <= r2:
					return true
			return false
		"rect":
			var r: Rect2 = fp["rect"]
			return at.x >= r.position.x and at.y >= r.position.y and at.x < r.end.x and at.y < r.end.y
		"multi":
			for part: Dictionary in fp["parts"]:
				if footprint_contains(part, at, cell):
					return true
	return false

## Bounding box of a footprint shape.
static func footprint_bounds(fp: Dictionary) -> Rect2:
	match fp.get("shape", ""):
		"circle":
			var r := float(fp["radius"])
			return Rect2(fp["center"] - Vector2(r, r), Vector2(r, r) * 2.0)
		"polygon", "polyline":
			var pts: PackedVector2Array = fp["points"]
			var b := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				b = b.expand(p)
			return b.grow(float(fp.get("width", 0.0)) * 0.5 + 2.0)
		"rect":
			return fp["rect"]
		"multi":
			var b := Rect2()
			var first := true
			for part: Dictionary in fp["parts"]:
				var pb := footprint_bounds(part)
				b = pb if first else b.merge(pb)
				first = false
			return b
	return Rect2()

## Footprint of a scenario obstacle shape ({"shape": "polyline" | "polygon" |
## "rect" | "circle", ...}; see ScenarioEvents.add_obstacle): the same cells.
static func obstacle_footprint(ob: Dictionary) -> Dictionary:
	match ob.get("shape", "polyline"):
		"polygon":
			return {"shape": "polygon", "points": params_points(ob["points"])}
		"rect":
			var a: Array = ob["rect"]
			return {"shape": "rect", "rect": Rect2(a[0], a[1], a[2], a[3])}
		"circle":
			return {"shape": "circle", "center": params_vec2(ob["center"]), "radius": float(ob["radius"])}
	return {"shape": "polyline", "points": params_points(ob["points"]), "width": float(ob.get("width", 16.0))}

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
