class_name CarriedBroodRenderer
extends BroodRenderer
## Brood being carried by nurses, drawn in their jaws above the ants
## (species register it as "underground_top:<nest type>"). See BroodRenderer.

func _init() -> void:
	carried_only = true
