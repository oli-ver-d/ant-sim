class_name FungusUnderground
extends Node2D
## A leafcutter nest's underground, drawn on its layer's WorldView
## ("underground:fungus_nest"): the fungus gardens in the chambers
## (GardenRenderer) and the brood lying in its piles on and beside them
## (BroodRenderer). The soil, tunnels, ants and items are drawn by the core.

var sim: Simulation
var nest: FungusNest
var view: WorldView
var _garden: GardenRenderer
var _brood: BroodRenderer

func bind(simulation: Simulation, target: Object) -> void:
	sim = simulation
	nest = target as FungusNest
	if nest.garden != null:
		_garden = GardenRenderer.new()
		_garden.bind(nest)
		add_child(_garden)
	_brood = BroodRenderer.new()
	_brood.bind(sim, nest)
	add_child(_brood)
