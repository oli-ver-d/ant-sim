class_name PlantProp
extends PropType
## A plant or grass clump: a stem on the ground (blocking if "stem" > 0) and a
## canopy of blades over the ants, which never blocks.
##   {"type": "plant", "kind": "rosette", "center": [x, y], "radius": 60, "stem": 6,
##    "blades": 8, "rotation": degrees, "scale": 1}
##   {"type": "grass", "center": [x, y], "radius": 40}   (stem 0: canopy only)
## "radius" is the canopy's reach. Kinds:
##   rosette   6-12 long blades flat round a centre (dandelion, plantain)
##   clover    thin stalks, each ending in three heart-shaped lobes
##   fern      arching fronds with paired pinnae along a stalk
##   seedling  two to four small oval blades on a short stem
##   grass     (the "grass" type) a clump of long thin blades, some bent over
## "blades" sets the count (blades, stalks or fronds); random if absent.
##
## The look's geometry goes in prop.detail: "blades", an array of
## {"style", "points" (spine, base to tip), "widths", "heights" (above the
## ground, for the canopy's shadow), "tint", "phase" (sway), "teeth"}, drawn in
## order (lowest first) by CanopyRenderer, and "height" of the stem crown.

## Blade styles, for the canopy shader (CUSTOM1.x).
enum Style { GRASS, BROAD, LOBE, PINNA, STALK }

## Spine points per blade (segments + 1); enough to bend smoothly and sway.
const SEGMENTS := 8

const DEFAULTS := {
	"rosette": {"radius": 60.0, "stem": 6.0, "blades": [6, 12]},
	"clover": {"radius": 45.0, "stem": 4.0, "blades": [3, 8]},
	"fern": {"radius": 80.0, "stem": 6.0, "blades": [3, 6]},
	"seedling": {"radius": 16.0, "stem": 2.0, "blades": [2, 4]},
	"grass": {"radius": 40.0, "stem": 0.0, "blades": [16, 28]},
}

func build(prop: Prop, rng: RandomNumberGenerator) -> void:
	var p := prop.params
	prop.position = params_vec2(p["center"])
	prop.rotation = rotation_of(p, rng)
	prop.scale = float(p.get("scale", 1.0))
	var kind := "grass" if prop.type_id == "grass" else str(p.get("kind", "rosette"))
	if not DEFAULTS.has(kind):
		push_warning("Unknown plant kind '%s', using rosette" % kind)
		kind = "rosette"
	var def: Dictionary = DEFAULTS[kind]
	var reach := float(p.get("radius", def["radius"])) * prop.scale
	var stem := float(p.get("stem", def["stem"])) * prop.scale
	var range_n: Array = def["blades"]
	var count := rng.randi_range(range_n[0], range_n[1])
	if p.has("blades"):
		count = maxi(int(p["blades"]), 1)
	var blades: Array[Dictionary] = []
	match kind:
		"rosette":
			_rosette(blades, prop, reach, count, rng)
		"clover":
			_clover(blades, prop, reach, count, rng)
		"fern":
			_fern(blades, prop, reach, count, rng)
		"seedling":
			_seedling(blades, prop, reach, count, rng)
		_:
			_grass(blades, prop, reach, count, rng)
	prop.detail = {"kind": kind, "blades": blades, "reach": reach, "height": maxf(stem * 1.2, 2.0)}
	prop.canopy = _hull(blades)
	prop.blocks = stem > 0.0 and bool(p.get("blocks", true))
	if stem > 0.0:
		prop.outline = blob(prop.position, stem, stem, 0.0, 0.0, rng, 10)
		prop.footprint = {"shape": "circle", "center": prop.position, "radius": stem}

# --- Kinds --------------------------------------------------------------------------------

func _rosette(out: Array[Dictionary], prop: Prop, reach: float, count: int, rng: RandomNumberGenerator) -> void:
	var green := Color(0.26, 0.45, 0.15).lerp(Color(0.34, 0.5, 0.18), rng.randf())
	# Dandelion-like (narrower, deeply lobed) or plantain-like (broad, smooth).
	var lobed := rng.randf() < 0.55
	var teeth := rng.randf_range(0.35, 0.55) if lobed else 0.0
	var broad := rng.randf_range(0.22, 0.28) if lobed else rng.randf_range(0.28, 0.38)
	# Two whorls: the outer, older blades first (under), the inner ones on top.
	for i in count:
		var inner := i >= count / 2
		var a := prop.rotation + TAU * (i + rng.randf_range(-0.35, 0.35)) / count + (PI / count if inner else 0.0)
		var length := reach * rng.randf_range(0.55, 1.0) * (0.75 if inner else 1.0)
		var width := length * broad * rng.randf_range(0.8, 1.2)
		var spine := _arc(prop.position, a, length, rng.randf_range(-0.35, 0.35))
		var widths: PackedFloat32Array = []
		var heights: PackedFloat32Array = []
		for k in spine.size():
			var t := float(k) / SEGMENTS
			# Narrow stalk at the base, widest two thirds out, rounded tip.
			var s := pow(t, 1.7)
			widths.append(width * pow(sin(PI * s), 0.6) * (0.3 + 0.7 * smoothstep(0.0, 0.35, t)))
			heights.append(1.5 + 4.0 * sin(PI * minf(t * 1.2, 1.0)) * (1.0 if inner else 0.6))
		var tint := green.darkened(0.0 if inner else 0.15).lerp(Color(0.5, 0.48, 0.2), 0.15 * rng.randf())
		out.append(_blade(Style.BROAD, spine, widths, heights, tint, rng, teeth))

func _clover(out: Array[Dictionary], prop: Prop, reach: float, count: int, rng: RandomNumberGenerator) -> void:
	var green := Color(0.18, 0.38, 0.16).lerp(Color(0.24, 0.44, 0.2), rng.randf())
	var stalks: Array[Dictionary] = []
	var lobes: Array[Dictionary] = []
	for i in count:
		var a := prop.rotation + TAU * (i + rng.randf_range(-0.35, 0.35)) / count
		var length := reach * rng.randf_range(0.5, 0.78)
		var spine := _arc(prop.position, a, length, rng.randf_range(-0.6, 0.6))
		var widths: PackedFloat32Array = []
		var heights: PackedFloat32Array = []
		var top := rng.randf_range(5.0, 9.0)
		for k in spine.size():
			var t := float(k) / SEGMENTS
			widths.append(lerpf(1.6, 1.1, t))
			heights.append(top * sqrt(t))
		var phase := rng.randf() * TAU
		var stalk := _blade(Style.STALK, spine, widths, heights, green.darkened(0.1).lerp(Color(0.45, 0.4, 0.25), 0.3), rng)
		stalk["phase"] = phase
		stalks.append(stalk)
		# Three heart-shaped lobes round the stalk's tip.
		var tip := spine[SEGMENTS]
		var dir := (spine[SEGMENTS] - spine[SEGMENTS - 1]).angle()
		var size := reach * rng.randf_range(0.2, 0.27)
		var mark := rng.randf() < 0.7
		for j in 3:
			var la := dir + TAU * j / 3.0 + rng.randf_range(-0.2, 0.2)
			var lspine := _arc(tip, la, size, rng.randf_range(-0.15, 0.15))
			var lw: PackedFloat32Array = []
			var lh: PackedFloat32Array = []
			for k in lspine.size():
				var t := float(k) / SEGMENTS
				lw.append(size * 0.95 * pow(sin(PI * clampf(t, 0.0, 1.0)), 0.55))
				lh.append(top + 0.5)
			var lobe := _blade(Style.LOBE, lspine, lw, lh, green.lightened(0.05 * j), rng, 1.0 if mark else 0.0)
			lobe["phase"] = phase
			lobes.append(lobe)
	out.append_array(stalks)
	out.append_array(lobes)

func _fern(out: Array[Dictionary], prop: Prop, reach: float, count: int, rng: RandomNumberGenerator) -> void:
	var green := Color(0.22, 0.44, 0.14).lerp(Color(0.3, 0.5, 0.18), rng.randf())
	for i in count:
		var a := prop.rotation + TAU * (i + rng.randf_range(-0.3, 0.3)) / count
		var length := reach * rng.randf_range(0.75, 1.0)
		var bend := rng.randf_range(-0.5, 0.5)
		var spine := _arc(prop.position, a, length, bend)
		var rise := length * rng.randf_range(0.25, 0.35)
		var widths: PackedFloat32Array = []
		var heights: PackedFloat32Array = []
		for k in spine.size():
			var t := float(k) / SEGMENTS
			widths.append(lerpf(2.4, 0.8, t))
			heights.append(rise * sin(PI * lerpf(0.15, 0.85, t)))
		var phase := rng.randf() * TAU
		var tint := green.darkened(rng.randf_range(0.0, 0.15))
		var rachis := _blade(Style.STALK, spine, widths, heights, tint.darkened(0.2), rng)
		rachis["phase"] = phase
		out.append(rachis)
		# Pinnae in pairs from 15% of the way out, longest a third of the way.
		var pairs := int(clampf(length / 7.0, 5.0, 16.0))
		for k in pairs:
			var f := lerpf(0.15, 0.97, float(k) / (pairs - 1))
			var at := _along(spine, f)
			var here: Vector2 = at["point"]
			var d: float = at["angle"]
			var plen := length * 0.34 * sin(PI * lerpf(0.12, 1.0, f)) * rng.randf_range(0.9, 1.1)
			plen = maxf(plen, 2.5)
			var h: float = rise * sin(PI * lerpf(0.15, 0.85, f))
			for side: float in [-1.0, 1.0]:
				var pa := d + side * deg_to_rad(rng.randf_range(55.0, 70.0))
				var pspine := _arc(here, pa, plen, side * 0.25)
				var pw: PackedFloat32Array = []
				var ph: PackedFloat32Array = []
				for m in pspine.size():
					var t := float(m) / SEGMENTS
					pw.append(plen * 0.36 * pow(sin(PI * lerpf(0.08, 1.0, t)), 0.7))
					ph.append(h)
				var pinna := _blade(Style.PINNA, pspine, pw, ph, tint.lightened(0.08 * f), rng, 0.5)
				pinna["phase"] = phase
				out.append(pinna)

func _seedling(out: Array[Dictionary], prop: Prop, reach: float, count: int, rng: RandomNumberGenerator) -> void:
	var green := Color(0.36, 0.56, 0.18).lerp(Color(0.44, 0.62, 0.22), rng.randf())
	for i in count:
		var a := prop.rotation + TAU * (i + rng.randf_range(-0.15, 0.15)) / count
		var length := reach * rng.randf_range(0.75, 1.0)
		var spine := _arc(prop.position, a, length, rng.randf_range(-0.3, 0.3))
		var widths: PackedFloat32Array = []
		var heights: PackedFloat32Array = []
		for k in spine.size():
			var t := float(k) / SEGMENTS
			widths.append(length * 0.55 * pow(sin(PI * lerpf(0.05, 1.0, t)), 0.8) * smoothstep(0.0, 0.3, t) + 0.8)
			heights.append(2.0 + 2.0 * t)
		out.append(_blade(Style.BROAD, spine, widths, heights, green.lightened(0.05 * i), rng))

func _grass(out: Array[Dictionary], prop: Prop, reach: float, count: int, rng: RandomNumberGenerator) -> void:
	var green := Color(0.32, 0.5, 0.16).lerp(Color(0.42, 0.56, 0.2), rng.randf())
	var straw := Color(0.64, 0.58, 0.34)
	var tuft := reach * 0.08
	for i in count:
		var a := rng.randf() * TAU
		var base := prop.position + Vector2.from_angle(rng.randf() * TAU) * tuft * sqrt(rng.randf())
		var length := reach * rng.randf_range(0.55, 1.0)
		var width := clampf(reach * rng.randf_range(0.045, 0.07), 1.5, 4.0)
		var bent := rng.randf() < 0.3
		var kink := rng.randf_range(0.4, 0.7)
		var turn := deg_to_rad(rng.randf_range(35.0, 80.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var curve := rng.randf_range(-0.4, 0.4)
		var spine: PackedVector2Array = [base]
		var widths: PackedFloat32Array = []
		var heights: PackedFloat32Array = []
		var step := length / SEGMENTS
		var dir := a
		for k in SEGMENTS + 1:
			var t := float(k) / SEGMENTS
			if k > 0:
				dir += curve / SEGMENTS
				if bent and t > kink and float(k - 1) / SEGMENTS <= kink:
					dir += turn
				spine.append(spine[k - 1] + Vector2.from_angle(dir) * step)
			widths.append(width * (1.0 - pow(t, 2.2)) * (0.8 + 0.2 * smoothstep(0.0, 0.2, t)))
			# Upright blades rise and arch over; a bent one falls from its kink.
			var h := length * 0.45 * sin(PI * 0.5 * minf(t / 0.6, 1.0)) * (1.0 - 0.4 * maxf(t - 0.6, 0.0))
			if bent and t > kink:
				h = lerpf(length * 0.45 * sin(PI * 0.5 * minf(kink / 0.6, 1.0)), 1.5, (t - kink) / (1.0 - kink))
			heights.append(h)
		var dry := rng.randf()
		var tint := green.darkened(rng.randf_range(0.0, 0.2))
		if dry < 0.15:
			tint = straw.darkened(rng.randf_range(0.0, 0.15))
		elif bent:
			tint = tint.lerp(straw, 0.35)
		out.append(_blade(Style.GRASS, spine, widths, heights, tint, rng))

# --- Helpers ------------------------------------------------------------------------------

## A blade record; its sway phase is random unless the caller shares one.
static func _blade(style: Style, spine: PackedVector2Array, widths: PackedFloat32Array,
		heights: PackedFloat32Array, tint: Color, rng: RandomNumberGenerator, teeth: float = 0.0) -> Dictionary:
	return {"style": style, "points": spine, "widths": widths, "heights": heights,
			"tint": tint, "phase": rng.randf() * TAU, "teeth": teeth}

## SEGMENTS + 1 points along an arc from `start` at angle `a`, turning by
## `bend` radians over its `length`.
static func _arc(start: Vector2, a: float, length: float, bend: float) -> PackedVector2Array:
	var out: PackedVector2Array = [start]
	var step := length / SEGMENTS
	var dir := a - bend * 0.5 / SEGMENTS
	for k in SEGMENTS:
		dir += bend / SEGMENTS
		out.append(out[k] + Vector2.from_angle(dir) * step)
	return out

## Point and direction a fraction `f` of the way along a spine of equal steps.
static func _along(spine: PackedVector2Array, f: float) -> Dictionary:
	var x := clampf(f, 0.0, 1.0) * (spine.size() - 1)
	var k := mini(int(x), spine.size() - 2)
	var t := x - k
	return {"point": spine[k].lerp(spine[k + 1], t), "angle": (spine[k + 1] - spine[k]).angle()}

## Convex hull of every blade's edges: the canopy outline.
static func _hull(blades: Array[Dictionary]) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for b in blades:
		var spine: PackedVector2Array = b["points"]
		var widths: PackedFloat32Array = b["widths"]
		for k in spine.size():
			var d := (spine[mini(k + 1, spine.size() - 1)] - spine[maxi(k - 1, 0)]).normalized().orthogonal()
			pts.append(spine[k] + d * widths[k] * 0.5)
			pts.append(spine[k] - d * widths[k] * 0.5)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull
