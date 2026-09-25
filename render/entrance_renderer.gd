class_name EntranceRenderer
extends Node2D
## Draws every surface entrance of one nest (NestType.entrance_sites(): the
## main one, also while sealed, and each open extra one) with
## entrance.gdshader, in the nest's style (NestType.entrance_style). Each is a
## quad reaching NestType.ENTRANCE_REACH opening radii; an opening widens as
## ants go through it (Portal.uses), so uniforms are only re-set when an
## entrance opens, closes or grows. Crater and mound styles lean toward the
## entrance's spoil heap so heap and rim read as one piece of digging.

const STYLES: Array[String] = ["hole", "crater", "mound", "turret"]
## Radius change (world units) worth a redraw.
const REDRAW_STEP := 0.25

var sim: Simulation
var nest: NestType
var _quads: Array[ColorRect] = []
## What each quad shows: [x, y, radius, open, wear] as last set.
var _shown: Array[PackedFloat32Array] = []

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as NestType

func _process(_delta: float) -> void:
	if nest == null:
		return
	var sites := nest.entrance_sites()
	while _quads.size() < sites.size():
		_quads.append(_make_quad())
		_shown.append(PackedFloat32Array())
	for k in _quads.size():
		_quads[k].visible = k < sites.size()
	for k in sites.size():
		var s := sites[k]
		var wear := snappedf(1.0 - exp(-s.uses / NestType.USES_TO_WIDEN), 0.05)
		var now := PackedFloat32Array([s.position.x, s.position.y, snappedf(s.radius, REDRAW_STEP), 1.0 if s.open else 0.0, wear])
		if now != _shown[k]:
			_shown[k] = now
			_apply(_quads[k], s, wear)

func _make_quad() -> ColorRect:
	var quad := ColorRect.new()
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://render/entrance.gdshader")
	mat.set_shader_parameter("seed", float(nest.colony_id) * 3.7)
	quad.material = mat
	add_child(quad)
	return quad

func _apply(quad: ColorRect, s: NestType.EntranceSite, wear: float) -> void:
	var style := style_of(nest, s)
	var reach := s.reach(style)
	quad.position = s.position - Vector2(reach, reach)
	quad.size = Vector2(reach, reach) * 2.0
	var mat := quad.material as ShaderMaterial
	mat.set_shader_parameter("style", STYLES.find(style))
	mat.set_shader_parameter("center", s.position)
	mat.set_shader_parameter("hole", s.radius)
	mat.set_shader_parameter("reach", reach)
	mat.set_shader_parameter("open", 1.0 if s.open else 0.0)
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("spoil_dir", spoil_direction(nest, s))

## The style an entrance is drawn in: the nest's, but a sealed one is only a
## plug of soil in a plain rim (nothing has been dug out yet).
static func style_of(of_nest: NestType, s: NestType.EntranceSite) -> String:
	return of_nest.entrance_style if s.open else "hole"

## Unit direction from an entrance to its spoil heap (zero for a nest that
## doesn't dig).
static func spoil_direction(of_nest: NestType, s: NestType.EntranceSite) -> Vector2:
	if of_nest.underground_layer < 0:
		return Vector2.ZERO
	return (of_nest.spoil_position_of(s.index) - s.position).normalized()
