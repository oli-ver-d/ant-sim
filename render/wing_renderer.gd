class_name WingRenderer
extends Node2D
## Draws winged ants' wings (NestType.winged_ants(): a landing queen, later
## alates) on one layer, and their shadows on the ground. Two passes: SHADOW
## (under the ants) draws the ground shadow of an ant in the air, offset
## along the light by its altitude and fainter the higher it is; WINGS (over
## the ants) draws the wings, beating in a blur while the ant flies, held
## out while it glides and folded back over the abdomen on the ground. The
## body is drawn larger with altitude by AntRenderer (LIFT_SCALE), so the
## wings scale with it.

enum Pass { SHADOW, WINGS }

## Ground shadow offset per unit of altitude (the light of ant.gdshader's
## drop shadow: down and to the right).
const LIGHT := Vector2(0.54, 0.84) * 0.6
const SHADOW := Color(0, 0, 0, 0.5)

var sim: Simulation
var layer: int = 0
var pass_kind: int = Pass.WINGS
## Fraction of the way from the previous tick to the current one (set by WorldView).
var alpha: float = 1.0

func bind(simulation: Simulation) -> void:
	sim = simulation

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	for colony in sim.colonies:
		var winged := colony.nest.winged_ants(sim)
		for i: int in winged:
			if sim.alive[i] == 0 or sim.layer[i] != layer:
				continue
			var w: Vector3 = winged[i]
			if pass_kind == Pass.SHADOW:
				_draw_shadow(i, w)
			else:
				_draw_wings(i, w)

func _at(i: int) -> Vector2:
	return sim.prev_pos[i].lerp(sim.shown_pos[i], alpha)

func _heading(i: int) -> float:
	return lerp_angle(sim.prev_heading[i], sim.shown_heading[i], alpha)

func _draw_shadow(i: int, w: Vector3) -> void:
	var alt := w.y
	if alt <= 0.5:
		return
	var size := sim.caste_of(i).size
	var h := _heading(i)
	var at := _at(i) + LIGHT * alt
	var fade := clampf(1.0 - alt / 500.0, 0.3, 1.0)
	# Soft: a few nested ellipses, the outer ones fainter (a higher ant's
	# shadow is blurrier).
	var blur := 1.0 + alt / 150.0
	for k in 3:
		var grow := 1.0 + k * 0.3 * blur
		var c := SHADOW
		c.a *= fade * (0.9 if k == 0 else 0.45)
		draw_set_transform(at, h, Vector2(size * 0.45 * grow, size * 0.17 * grow))
		draw_circle(Vector2.ZERO, 1.0, c)
		# The wings' shadow, fainter.
		if w.x > 0 and w.z > 0.0:
			c.a *= 0.5
			draw_set_transform(at, h, Vector2(size * 0.22 * grow, size * 0.75 * grow))
			draw_circle(Vector2.ZERO, 1.0, c)
	draw_set_transform(Vector2.ZERO)

func _draw_wings(i: int, w: Vector3) -> void:
	var def := sim.caste_of(i)
	var scale := 1.0 + w.y * AntRenderer.LIFT_SCALE
	var size := def.size * scale
	var h := _heading(i)
	var at := _at(i)
	var fwd := Vector2.from_angle(h)
	var tint := def.wing_color()
	var length := size * def.wing_length
	var pairs := int(w.x)
	# Right side (1) first shed, so a queen with one pair left has the left.
	for s: float in [-1.0, 1.0]:
		if s > 0.0 and pairs < 2:
			continue
		if pairs < 1:
			continue
		var base := at + fwd * size * 0.06 + fwd.orthogonal() * -s * size * 0.07
		if w.z <= 0.0:
			# Folded back over the abdomen, fore wing over hind wing.
			WingLook.draw_pair(self, base, h + PI - s * 0.12, h + PI - s * 0.2, length, -s, tint, 1.0)
			continue
		# Spread; beating: a faint fan over the stroke, the wing at a point in it.
		var out := h + s * PI * 0.5
		var beat := w.z
		if beat > 0.1:
			var t := sim.time() * 23.0 + i
			for k in 5:
				var a := out + s * lerpf(-0.5, 0.5, k / 4.0) * beat
				WingLook.draw_pair(self, base, a - s * 0.1, a + s * 0.15, length, -s, tint, 0.18)
			var now := out + s * sin(t) * 0.5 * beat
			WingLook.draw_pair(self, base, now - s * 0.1, now + s * 0.15, length, -s, tint, 0.5)
		else:
			WingLook.draw_pair(self, base, out - s * 0.25, out + s * 0.1, length, -s, tint, 0.9)
