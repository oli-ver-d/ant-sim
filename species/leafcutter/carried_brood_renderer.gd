class_name CarriedBroodRenderer
extends BroodRenderer
## Brood being carried by nurses, drawn in their jaws above the ants
## (registered as "underground_top:fungus_nest"). See BroodRenderer.

func _init() -> void:
	carried_only = true
