class_name LogLook
extends RefCounted
## Paints a fallen log or branch (LogProp) for PropBaker: a cylinder lying
## along its axes (main trunk plus side stubs), lit round its curve, with bark
## ridges running along it, knots, patches where the bark has peeled off to
## pale wood, a sawn end showing growth rings and a splintered broken end.
## Registered as the renderer "prop:log".

const BARK_DARK := Color(0.29, 0.21, 0.14)
const BARK_GREY := Color(0.35, 0.3, 0.25)
const WOOD := Color(0.74, 0.62, 0.45)
const HEART := Color(0.6, 0.45, 0.3)

func paint(c: PropBaker.Canvas, prop: Prop, _ground: GroundMap) -> void:
	var d := prop.detail
	var axes: Array = d["axes"]
	var peel := float(d.get("peel", 0.3))
	var bark := BARK_DARK.lerp(BARK_GREY, float(d.get("tint", 0.5)))
	var L := PropBaker.light3()
	var L2 := PropBaker.LIGHT_DIR.normalized()

	# Arc-length offsets of each axis's segments.
	var starts: Array[PackedFloat32Array] = []
	var lengths: PackedFloat32Array = []
	for axis: Dictionary in axes:
		var pts: PackedVector2Array = axis["points"]
		var s := PackedFloat32Array([0.0])
		for k in pts.size() - 1:
			s.append(s[k] + pts[k].distance_to(pts[k + 1]))
		starts.append(s)
		lengths.append(s[s.size() - 1])
	var w0: float = (axes[0]["widths"] as PackedFloat32Array)[0]

	var ridges := PropBaker.noise(prop, 1, 1.0, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var peel_nz := PropBaker.noise(prop, 2, 1.0, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var grain := PropBaker.noise(prop, 3, 1.0)
	var splinter := PropBaker.noise(prop, 4, 1.0 / 1.5)
	var blotch := PropBaker.noise(prop, 5, 1.0 / 12.0, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = prop.prop_seed + 17
	var knots: Array[Vector3] = []   # (along, around, radius)
	for k in rng.randi_range(1, 3):
		knots.append(Vector3(rng.randf_range(0.2, 0.85) * lengths[0], rng.randf_range(-0.6, 0.6) * w0 * 0.5, rng.randf_range(1.5, 3.2)))
	var end_len := w0 * 0.28
	var pith := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))

	var heights := PackedFloat32Array()
	heights.resize(c.width * c.height)
	for y in c.height:
		for x in c.width:
			var i := y * c.width + x
			if c.cover[i] <= 0.0:
				continue
			var p := c.world_at(x, y)
			# Nearest axis: the one we are the smallest fraction of its half-width from.
			var best := INF
			var ax := 0
			var along := 0.0
			var across := 0.0
			var hw := 1.0
			var dir := Vector2.RIGHT
			for a in axes.size():
				var pts: PackedVector2Array = axes[a]["points"]
				var ws: PackedFloat32Array = axes[a]["widths"]
				for k in pts.size() - 1:
					var seg := pts[k + 1] - pts[k]
					var len2 := maxf(seg.length_squared(), 0.0001)
					var t := clampf((p - pts[k]).dot(seg) / len2, 0.0, 1.0)
					var q := pts[k] + seg * t
					var half := lerpf(ws[k], ws[k + 1], t) * 0.5
					var score := p.distance_to(q) / half
					if score < best:
						best = score
						ax = a
						hw = half
						dir = seg.normalized()
						along = starts[a][k] + t * sqrt(len2)
						across = (p - q).dot(dir.orthogonal())
			var v := clampf(across / hw, -1.0, 1.0)
			var up := sqrt(maxf(1.0 - v * v, 0.0))
			heights[i] = hw * (0.6 + up)
			var side := dir.orthogonal()
			var nrm := Vector3(side.x * v, side.y * v, up).normalized()
			# Around the trunk (arc length) and along it, for bark patterns.
			var around := asin(v) * hw
			var col := bark
			var shade := 0.3 + 0.8 * maxf(nrm.dot(L), 0.0)

			# Bark ridges run along the log: noise stretched along the axis.
			var r := ridges.get_noise_2d(along / 9.0, around / 1.3)
			col = col * (0.8 + 0.45 * r) * (1.0 + 0.1 * blotch.get_noise_2d(p.x, p.y))
			if r < -0.2:
				shade *= 0.62
			# Knots on the main trunk: dark rings.
			if ax == 0:
				for kn in knots:
					var kd := Vector2((along - kn.x) * 0.7, around - kn.y).length() / kn.z
					if kd < 1.0:
						col = col.lerp(HEART.darkened(0.4), 0.8 * (1.0 - kd))
						if kd > 0.65:
							shade *= 0.8
			# Peeled bark: pale smooth wood with a dark bark edge round it.
			var pv := peel_nz.get_noise_2d(along / 34.0, around / 9.0)
			var bare := 0.72 - peel * 0.65
			if pv > bare:
				col = WOOD * (0.92 + 0.12 * grain.get_noise_2d(along / 18.0, around / 0.7))
				if pv < bare + 0.04:
					col = bark.darkened(0.35)
			if ax == 0 and along < end_len * 2.0:
				# Sawn end, seen a little from above: an ellipse of end grain.
				var e := Vector2((along - end_len) / end_len, v)
				var er := e.length()
				if er < 1.0:
					var ring_r := (e - pith).length()
					col = WOOD.lerp(HEART, clampf(1.0 - ring_r * 1.4, 0.0, 1.0))
					var rings := fposmod(ring_r * hw * 0.9 + 0.3 * grain.get_noise_2d(p.x * 0.5, p.y * 0.5), 1.0)
					if rings < 0.22:
						col = col.darkened(0.2)
					if er > 0.86:
						col = bark.darkened(0.2)
					# The face is upright, facing back along the log.
					shade = 0.7 + 0.35 * maxf(-dir.dot(L2), 0.0)
					heights[i] = hw * 0.8
				elif along < end_len:
					shade *= 0.55
			elif along > lengths[ax] - 4.0:
				# Broken end: splinters, pale fibres.
				var cut := lengths[ax] - 0.4 - 2.2 * absf(splinter.get_noise_2d(around, 0.0))
				if along > cut:
					c.cover[i] = 0.0
					continue
				if along > cut - (2.0 if ax == 0 else 1.2):
					col = WOOD.lerp(col, 0.35)
			c.set_rgb(i, col * shade)
	c.heights = heights
