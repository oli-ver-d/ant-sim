class_name FoodPile
extends FoodSource
## Generic circular pile of identical crumbs. Mostly for testing the core.
##
## params: radius (world units), amount (number of crumbs), crumb_mass, color

var radius: float = 24.0
var amount: int = 200
var initial_amount: int = 200
var crumb_mass: float = 1.0
var color: Color = Color(0.85, 0.75, 0.45)

func setup(sim: Simulation, params: Dictionary) -> void:
	super.setup(sim, params)
	radius = params.get("radius", radius)
	amount = int(params.get("amount", amount))
	initial_amount = amount
	crumb_mass = params.get("crumb_mass", crumb_mass)
	if params.has("color"):
		color = Color(params["color"])

## Current visual radius: shrinks with sqrt(remaining) like a flattening pile.
func current_radius() -> float:
	if initial_amount <= 0:
		return 0.0
	return radius * sqrt(float(amount) / initial_amount)

func nearest_access_point(pos: Vector2) -> Vector2:
	var offset := pos - position
	if offset.length_squared() < 0.0001:
		return position
	return position + offset.normalized() * current_radius()

func take(sim: Simulation, _ant: int) -> Item:
	if amount <= 0:
		return null
	amount -= 1
	taken_mass += crumb_mass
	version += 1
	var item := sim.create_item("crumb", crumb_mass)
	item.source_id = id
	item.color = color
	item.radius = 2.0
	return item

func is_depleted() -> bool:
	return amount <= 0

func remaining_mass() -> float:
	return amount * crumb_mass
