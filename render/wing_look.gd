class_name WingLook
extends RefCounted
## How an ant's wings are drawn (on a winged ant by WingRenderer, shed ones
## lying on the ground by ItemRenderer): a translucent membrane, broadest
## past the middle, with a darker leading edge, a mid vein and a small
## stigma spot.

## Hind wing length, as a share of the fore wing's.
const HIND := 0.78
## Membrane opacity.
const MEMBRANE := 0.42
const STEPS := 10

## One wing from `base`, pointing along `angle`, `length` long; `side` 1 or
## -1 mirrors it (the leading edge is on the side away from the body's
## back, i.e. toward the head when the wing is folded).
static func draw_wing(ci: CanvasItem, base: Vector2, angle: float, length: float, side: float, tint: Color, alpha: float) -> void:
	if alpha <= 0.002 or length <= 0.0:
		return
	var width := length * 0.3
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var dir := Vector2.from_angle(angle)
	var across := dir.orthogonal() * side
	for k in STEPS + 1:
		var t := float(k) / STEPS
		var along := dir * length * t
		# Leading edge nearly straight, trailing edge full and rounded.
		top.append(base + along - across * width * 0.28 * sin(PI * t))
		bottom.append(base + along + across * width * 0.72 * sin(PI * pow(t, 0.75)))
	var outline := top.duplicate()
	for k in range(bottom.size() - 2, 0, -1):
		outline.append(bottom[k])
	var fill := tint
	fill.a = MEMBRANE * alpha
	ci.draw_colored_polygon(outline, fill)
	var vein := tint.darkened(0.55)
	vein.a = 0.55 * alpha
	ci.draw_polyline(top, vein, maxf(0.15, length * 0.025), true)
	var mid := PackedVector2Array()
	for k in STEPS - 1:
		mid.append(top[k].lerp(bottom[k], 0.4))
	vein.a = 0.3 * alpha
	ci.draw_polyline(mid, vein, maxf(0.1, length * 0.015), true)
	# The stigma: a dark spot on the leading edge.
	var spot := tint.darkened(0.6)
	spot.a = 0.6 * alpha
	ci.draw_circle(top[6].lerp(bottom[6], 0.12), length * 0.035, spot)

## A pair (fore and hind wing) on one side, both from `base`.
static func draw_pair(ci: CanvasItem, base: Vector2, fore_angle: float, hind_angle: float, length: float, side: float, tint: Color, alpha: float) -> void:
	draw_wing(ci, base, hind_angle, length * HIND, side, tint, alpha)
	draw_wing(ci, base, fore_angle, length, side, tint, alpha)
