class_name BroodRenderer
extends MultiMeshInstance2D
## Draws the brood of a FungusNest with care on (LeafcutterBrood), one
## MultiMesh instance each, with brood.gdshader: eggs, larvae that grow,
## pupae that darken as they mature, callows in their split casings. Dirty
## brood looks fuzzy, hungry larvae dull.
##
## Brood lying in the nest is drawn under the ants; with `carried_only` the
## renderer draws just the brood being carried, in its carrier's jaws, over
## the ants (CarriedBroodRenderer, registered as "underground_top:fungus_nest").

const STRIDE := 16
const EGG_SIZE := 2.8
const Stage := LeafcutterBrood.Stage

var sim: Simulation
var nest: FungusNest
var carried_only: bool = false
## The WorldView drawing this (set when attached; gives the tick interpolation).
var view: WorldView
var _buffer: PackedFloat32Array = []
var _caste_size: PackedFloat32Array = []
var _caste_color: PackedColorArray = []

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as FungusNest
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = AntRenderer._unit_quad()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://species/leafcutter/brood.gdshader")
	material = mat
	for c in sim.colonies[nest.colony_id].species.castes:
		_caste_size.append(c.size)
		_caste_color.append(c.color)

func _process(_delta: float) -> void:
	var brood := nest.brood if nest != null else null
	if brood == null or not brood.care:
		return
	var n := brood.count()
	if n > multimesh.instance_count:
		multimesh.instance_count = maxi(n * 2, 64)
		_buffer.resize(multimesh.instance_count * STRIDE)
	var o := 0
	var shown := 0
	for k in n:
		var carried := brood.carrier[k] >= 0
		if carried != carried_only:
			continue
		var s := brood.stage[k]
		var at := brood.pos[k]
		if carried:
			var c := brood.carrier[k]
			var h := sim.shown_heading[c]
			var alpha := view.alpha if view != null else 1.0
			h = lerp_angle(sim.prev_heading[c], h, alpha)
			at = sim.prev_pos[c].lerp(sim.shown_pos[c], alpha) + Vector2.from_angle(h) * sim.caste_of(c).size * 0.55
		var size := EGG_SIZE
		var t := clampf(brood.age[k] / brood.stage_time[s], 0.0, 1.0)
		var cs := _caste_size[brood.caste[k]]
		if s == Stage.LARVA:
			size = lerpf(3.0, maxf(5.5, cs * 0.9), brood.growth[k])
			t = brood.growth[k]
		elif s >= Stage.PUPA:
			size = cs * 1.35
		var col := _caste_color[brood.caste[k]]
		_buffer[o] = size
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = at.x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = size
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = at.y
		_buffer[o + 8] = col.r
		_buffer[o + 9] = col.g
		_buffer[o + 10] = col.b
		_buffer[o + 11] = 1.0
		_buffer[o + 12] = float(s)
		_buffer[o + 13] = t
		_buffer[o + 14] = brood.dirt[k] * 0.999 + 2.0 * floorf(brood.hunger[k] * 100.0)
		# A fixed look per brood item, and a heading: eggs and larvae lie any
		# way, pupae along their pile's spiral.
		var id := brood.id[k]
		var heading := wrapf(id * 2.39996, -PI, PI)
		_buffer[o + 15] = heading + 100.0 * float(id % 97)
		o += STRIDE
		shown += 1
	# The canvas item only picks up a resized MultiMesh when redrawn.
	if shown != multimesh.visible_instance_count:
		queue_redraw()
	multimesh.visible_instance_count = shown
	if shown > 0:
		multimesh.buffer = _buffer