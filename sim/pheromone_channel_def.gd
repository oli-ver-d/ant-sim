class_name PheromoneChannelDef
extends Resource
## One pheromone channel a species uses (e.g. "home", "food"). Each colony
## registers its own copy in the PheromoneField, namespaced by colony id.

## Local channel name, referenced by behaviour state params (e.g. "follow_channel").
@export var name: StringName = &""
## Seconds for a deposited value to evaporate to half strength.
@export var half_life: float = 30.0
## Fraction per second blended toward the 3x3 neighbourhood mean (0 = none).
@export_range(0.0, 1.0) var diffusion: float = 0.2
## Maximum value a cell can hold.
@export var cap: float = 10.0
## Deposits combine as: cell = max(cell, deposit) + reinforce * deposit.
## The max makes a cell hold "how fresh is the freshest ant from the source",
## a clean gradient however many ants pass; reinforce adds a little on top so
## busy trails still grow stronger than quiet ones (0 = pure max).
@export var reinforce: float = 0.1
## Colour used by the pheromone overlay.
@export var color: Color = Color.WHITE
