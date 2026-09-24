class_name FungusUnderground
extends Node2D
## A leafcutter nest's underground, drawn on its layer's WorldView
## ("underground:fungus_nest"): the fungus gardens in the chambers and the
## brood lying in its piles (BroodRenderer). The soil, tunnels and ants are
## drawn by the core.

var sim: Simulation
var nest: FungusNest
var view: WorldView
var _garden: Node2D
var _brood: BroodRenderer
var _drawn_fungus: float = -1.0
var _drawn_chambers: int = -1

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as FungusNest
	_garden = Node2D.new()
	_garden.draw.connect(_draw_garden)
	add_child(_garden)
	_brood = BroodRenderer.new()
	_brood.bind(sim, nest)
	add_child(_brood)

func _process(_delta: float) -> void:
	if nest.chambers_layout == null:
		return
	if absf(nest.fungus - _drawn_fungus) > 1.0 or nest.chambers != _drawn_chambers:
		_drawn_fungus = nest.fungus
		_drawn_chambers = nest.chambers
		_garden.queue_redraw()

## The fungus garden in each dug chamber: soft off-white lumps, more as the
## garden grows (see garden_share()).
func _draw_garden() -> void:
	var layout := nest.chambers_layout
	var rng := RandomNumberGenerator.new()
	for c in layout.list:
		if not c.dug:
			continue
		var share := garden_share(c.index)
		rng.seed = c.index * 7919 + 5
		var centre := c.centre + (Vector2(c.radius * 0.3, -c.radius * 0.3) if c.index == 0 else Vector2.ZERO)
		var reach := c.radius * (0.45 if c.index == 0 else 0.8)
		var lumps := 0 if c.index >= 0 else int(share * 60.0)
		for n in lumps:
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * reach * sqrt(rng.randf())
			var r := rng.randf_range(2.5, 5.0)
			_garden.draw_circle(p + Vector2(0.8, 1.2), r, Color(0, 0, 0, 0.2))
			_garden.draw_circle(p, r, Color(0.9, 0.88, 0.8).darkened(rng.randf() * 0.15))

## Share of chamber k's room the garden fills (0-1).
func garden_share(k: int) -> float:
	var cap := nest.garden_capacity()
	if cap <= 0.0:
		return 0.0
	return clampf(nest.fungus / cap, 0.0, 1.0)
