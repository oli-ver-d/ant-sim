class_name TestCase
extends RefCounted
## Base class for tests. The runner calls every method whose name starts with
## "test_". GDScript has no exceptions, so checks record failures and continue.

var failures: PackedStringArray = []
## Set by the runner to "<file>::<method>" before each test.
var current_test: String = ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, message])

func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: %s expected <%s> but got <%s>" % [current_test, message, expected, actual])
