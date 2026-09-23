extends RefCounted
## Leafcutter ant species module. So far it only uses the core's generic
## behaviours and food pile; its own leaf, behaviours and nest come later.

func register(registry: Registry) -> void:
	registry.register_species("leafcutter", preload("res://species/leafcutter/leafcutter.tres"))
