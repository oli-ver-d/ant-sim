class_name RefuseLooks
extends RefCounted
## The core's refuse looks (RefuseLook), registered by CoreRenderers as
## "refuse:<kind>": soil clumps, split seed husks, curled dead workers (in
## greys, tinted by caste), dead larvae and crumbs of leftover food.

## Clods of subsoil: a few lumps pressed together, gritty.
class SoilClump extends RefuseLook:
	func paint(img: Image, at: Vector2i, _v: int, rng: RandomNumberGenerator) -> void:
		var r := body()
		for k in rng.randi_range(2, 4):
			var off := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.45)
			var col: Color = SpoilHeapRenderer.COLORS[rng.randi() % SpoilHeapRenderer.COLORS.size()]
			blob(img, at, mid() + off, Vector2(r, r) * rng.randf_range(0.45, 0.65), rng.randf() * TAU,
					col.lightened(rng.randf() * 0.1), 0.7)
		for k in 14:
			speck(img, at, mid() + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()), 0.8,
					rng.randf_range(-0.3, 0.25))

## A seed coat split open: two pale, cupped halves lying in a loose V, or one
## half on its own; straw coloured, darker along the rims.
class Husk extends RefuseLook:
	const STRAW := Color(0.78, 0.69, 0.5)

	func paint(img: Image, at: Vector2i, v: int, rng: RandomNumberGenerator) -> void:
		var r := body()
		var halves := 1 if v % 3 == 2 else 2
		var base := rng.randf() * TAU
		for h in halves:
			var a := base + (h - 0.5) * rng.randf_range(0.5, 1.1)
			var dir := Vector2.from_angle(a)
			var c := mid() + dir * r * 0.25 * (h * 2 - 1) * (1.0 if halves == 2 else 0.0)
			var col := STRAW.darkened(rng.randf() * 0.18).lerp(Color(0.62, 0.5, 0.32), rng.randf() * 0.35)
			var radii := Vector2(r * 0.75, r * 0.36)
			blob(img, at, c, radii, a, col.darkened(0.25), 0.5)
			# The hollow inside, shaded like a cup (a flatter, darker core).
			blob(img, at, c + dir.orthogonal() * radii.y * 0.25, radii * Vector2(0.78, 0.55), a,
					col.darkened(0.08), -0.4)

## A dead worker curled on its side: abdomen and head drawn in toward the
## thorax, legs folded under. Painted in greys; the renderer tints it with
## the caste's colour.
class DeadAnt extends RefuseLook:
	func _init() -> void:
		tinted = true

	func paint(img: Image, at: Vector2i, _v: int, rng: RandomNumberGenerator) -> void:
		var r := body()
		var a := rng.randf() * TAU
		var dir := Vector2.from_angle(a)
		var across := dir.orthogonal()
		var side := across * (1.0 if rng.randf() < 0.5 else -1.0)
		var curl := rng.randf_range(0.2, 0.6)
		# Body along `dir`, abdomen and head bent toward `side`.
		var thorax := mid() - side * r * 0.1
		var abdomen := thorax - dir * r * 0.5 + side * r * 0.22 * curl
		var head := thorax + dir * r * 0.46 + side * r * 0.25 * curl
		var leg := Color(0.32, 0.32, 0.32)
		# Legs drawn in: out from the thorax to a knee, then folded back under.
		for k in 6:
			var s := -1.0 if k % 2 == 0 else 1.0
			var along := floorf(k / 2.0) - 1.0
			var root := thorax + dir * r * along * 0.12
			var knee := root + across * s * r * rng.randf_range(0.4, 0.55) + dir * r * along * rng.randf_range(0.15, 0.35)
			var foot := knee.lerp(root, rng.randf_range(0.3, 0.7)) + dir * r * rng.randf_range(-0.25, 0.1)
			stroke(img, at, root, knee, 1.3, leg)
			stroke(img, at, knee, foot, 1.1, leg)
		blob(img, at, abdomen, Vector2(r * 0.4, r * 0.3), (thorax - abdomen).angle(), Color(0.92, 0.92, 0.92))
		blob(img, at, thorax, Vector2(r * 0.3, r * 0.14), a, Color(0.85, 0.85, 0.85))
		blob(img, at, head, Vector2(r * 0.22, r * 0.2), (head - thorax).angle(), Color(0.9, 0.9, 0.9))
		# Antennae bent back along the head.
		for s: float in [-1.0, 1.0]:
			var elbow := head + (dir + across * s * 0.8).normalized() * r * 0.32
			stroke(img, at, head + dir * r * 0.1, elbow, 0.9, leg)
			stroke(img, at, elbow, elbow - dir * r * 0.2 + across * s * r * 0.1, 0.8, leg)

## A dead larva: a pale, segmented grub bent into a C.
class DeadLarva extends RefuseLook:
	const CREAM := Color(0.86, 0.82, 0.68)

	func paint(img: Image, at: Vector2i, _v: int, rng: RandomNumberGenerator) -> void:
		var r := body()
		var a0 := rng.randf() * TAU
		var bend := rng.randf_range(1.8, 2.8)
		var segs := 7
		for k in segs:
			var t := float(k) / (segs - 1)
			var p := mid() + Vector2.from_angle(a0 + (t - 0.5) * bend) * r * 0.55
			var w := r * (0.3 + 0.18 * sin(t * PI))
			blob(img, at, p, Vector2(w, w * 0.9), a0 + (t - 0.5) * bend, CREAM.darkened(0.06 * (k % 2) + rng.randf() * 0.05), 0.8)

## Crumbs of food nobody wanted: a few irregular brown-ochre fragments.
class Remnant extends RefuseLook:
	func paint(img: Image, at: Vector2i, _v: int, rng: RandomNumberGenerator) -> void:
		var r := body()
		for k in rng.randi_range(3, 5):
			var off := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.1, 0.6)
			var col := Color(0.55, 0.42, 0.25).lerp(Color(0.4, 0.3, 0.2), rng.randf())
			blob(img, at, mid() + off, Vector2(rng.randf_range(0.25, 0.45), rng.randf_range(0.18, 0.3)) * r,
					rng.randf() * TAU, col, 0.6)
