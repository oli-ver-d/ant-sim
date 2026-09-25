class_name SpentSubstrateLook
extends RefuseLook
## Spent garden substrate on a leafcutter midden ("refuse:spent_substrate"):
## spongy grey-brown clumps with a faint grey-green cast and tufts of white
## mould on them. Ageing (refuse.gdshader) greys and darkens them further.

const SPONGE := Color(0.54, 0.48, 0.38)
const GREEN := Color(0.5, 0.51, 0.41)
const MOULD := Color(0.93, 0.93, 0.88)

func paint(img: Image, at: Vector2i, _v: int, rng: RandomNumberGenerator) -> void:
	var r := body()
	var lumps: Array[Vector2] = []
	for k in rng.randi_range(3, 5):
		var off := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.5)
		lumps.append(mid() + off)
		var col := SPONGE.lerp(GREEN, rng.randf() * 0.6).darkened(rng.randf() * 0.2)
		blob(img, at, mid() + off, Vector2(r, r) * rng.randf_range(0.35, 0.55), rng.randf() * TAU, col, 0.6)
	# Pores.
	for k in 18:
		speck(img, at, mid() + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.9, 0.7, -0.3)
	# Mould: on some, a fuzzy white tuft of short hairs on the lumps.
	for k in rng.randi_range(-1, 1):
		var c: Vector2 = lumps[rng.randi() % lumps.size()] + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		blob(img, at, c, Vector2.ONE * r * 0.18, 0.0, Color(MOULD, 0.8), 0.3)
		for h in 7:
			var dir := Vector2.from_angle(rng.randf() * TAU)
			stroke(img, at, c, c + dir * r * rng.randf_range(0.18, 0.32), 0.6, Color(MOULD, 0.55))
