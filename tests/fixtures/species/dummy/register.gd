extends RefCounted
## Minimal species module used by test_registry to exercise discovery.

func register(registry: Registry) -> void:
	registry.register_behaviour("dummy_idle", Behaviour.new())
