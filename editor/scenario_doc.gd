class_name ScenarioDoc
extends RefCounted
## A scenario being edited: the parsed JSON dictionary is the document (the
## editor never edits a running Simulation). Every change is a command
## (set_at, remove_at, insert_at, move_item) recorded with UndoRedo, so the
## inspector, canvas gizmos and tests all edit it the same way.
##
## Paths are arrays of dictionary keys and list indices, e.g.
## ["colonies", 0, "nest_params", "brood", "egg"]. A key the dictionary
## doesn't have yet is added where the schema orders it (after the keys that
## come before it in the schema), or at the end without a schema. Keys the
## schema doesn't know are kept as they are.

signal changed(path: Array)

var data: Dictionary = {}
## The file it was loaded from or last saved to ("" if never saved).
var file_path: String = ""
## Used only to place new keys; may be null.
var schema: ScenarioSchema
var undo_redo := UndoRedo.new()
var _saved_version: int = 0

func _init(initial: Dictionary = {}, scenario_schema: ScenarioSchema = null) -> void:
	data = initial
	schema = scenario_schema
	_saved_version = undo_redo.get_version()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and undo_redo != null:
		undo_redo.free()

static func load_file(path: String, scenario_schema: ScenarioSchema = null) -> ScenarioDoc:
	var doc := ScenarioDoc.new(ScenarioJson.load_file(path), scenario_schema)
	doc.file_path = path
	return doc

## Saves to `path` (default: the file it came from).
func save(path: String = "") -> Error:
	if path == "":
		path = file_path
	var err := ScenarioJson.save_file(path, data)
	if err == OK:
		file_path = path
		_saved_version = undo_redo.get_version()
	return err

func is_dirty() -> bool:
	return undo_redo.get_version() != _saved_version

# --- reading -----------------------------------------------------------------

func has_at(path: Array) -> bool:
	var v: Variant = data
	for key: Variant in path:
		if v is Dictionary and v.has(key):
			v = v[key]
		elif v is Array and key is int and key >= 0 and key < v.size():
			v = v[key]
		else:
			return false
	return true

func get_at(path: Array, default: Variant = null) -> Variant:
	var v: Variant = data
	for key: Variant in path:
		if v is Dictionary and v.has(key):
			v = v[key]
		elif v is Array and key is int and key >= 0 and key < v.size():
			v = v[key]
		else:
			return default
	return v

# --- commands ----------------------------------------------------------------

## Sets the value at `path`: a dictionary key (added if missing, with any
## missing dictionaries on the way) or an existing list item.
func set_at(path: Array, value: Variant, action: String = "") -> void:
	assert(not path.is_empty())
	var parent_path := path.slice(0, -1)
	var key: Variant = path[-1]
	undo_redo.create_action(action if action != "" else "Set " + _label(path))
	# Create missing dictionaries on the way (undone by removing the first one).
	var created := -1
	for i: int in parent_path.size():
		if not has_at(parent_path.slice(0, i + 1)):
			created = i
			break
	if created >= 0:
		var top := parent_path.slice(0, created + 1)
		var nested: Variant = value
		for i: int in range(path.size() - 1, created, -1):
			nested = {path[i]: nested}
		undo_redo.add_do_method(_put.bind(top, nested, -1))
		undo_redo.add_undo_method(_remove.bind(top))
	elif has_at(path):
		undo_redo.add_do_method(_put.bind(path, _copy(value), -1))
		undo_redo.add_undo_method(_put.bind(path, _copy(get_at(path)), -1))
	else:
		undo_redo.add_do_method(_put.bind(path, _copy(value), -1))
		undo_redo.add_undo_method(_remove.bind(path))
	undo_redo.commit_action()

## Removes a dictionary key or a list item.
func remove_at(path: Array, action: String = "") -> void:
	if not has_at(path):
		return
	var parent: Variant = get_at(path.slice(0, -1))
	var index: int = parent.keys().find(path[-1]) if parent is Dictionary else path[-1]
	undo_redo.create_action(action if action != "" else "Remove " + _label(path))
	undo_redo.add_do_method(_remove.bind(path))
	undo_redo.add_undo_method(_put.bind(path, _copy(get_at(path)), index))
	undo_redo.commit_action()

## Inserts `value` into the list at `path` minus its last element, at that
## index (the list's size appends). Creates the list if missing.
func insert_at(path: Array, value: Variant, action: String = "") -> void:
	var list_path := path.slice(0, -1)
	if not has_at(list_path):
		set_at(list_path, [value], action if action != "" else "Add " + _label(path))
		return
	var list: Array = get_at(list_path)
	var index: int = clampi(path[-1], 0, list.size())
	var at := list_path + [index]
	undo_redo.create_action(action if action != "" else "Add " + _label(path))
	undo_redo.add_do_method(_insert.bind(at, _copy(value)))
	undo_redo.add_undo_method(_remove.bind(at))
	undo_redo.commit_action()

## Moves the list item at `path` to index `to` in the same list.
func move_item(path: Array, to: int, action: String = "") -> void:
	var list: Array = get_at(path.slice(0, -1), [])
	var from: int = path[-1]
	to = clampi(to, 0, list.size() - 1)
	if from == to or from < 0 or from >= list.size():
		return
	var list_path := path.slice(0, -1)
	undo_redo.create_action(action if action != "" else "Move " + _label(path))
	undo_redo.add_do_method(_move.bind(list_path, from, to))
	undo_redo.add_undo_method(_move.bind(list_path, to, from))
	undo_redo.commit_action()

func undo() -> bool:
	return undo_redo.undo()

func redo() -> bool:
	return undo_redo.redo()

# --- primitive edits (run by UndoRedo) -----------------------------------------

## Sets `path` to `value`. A new dictionary key goes at `index` if >= 0,
## else where the schema orders it.
func _put(path: Array, value: Variant, index: int) -> void:
	var parent: Variant = get_at(path.slice(0, -1))
	var key: Variant = path[-1]
	value = _copy(value)
	if parent is Array:
		if index >= 0:
			parent.insert(index, value)
		else:
			parent[key] = value
	elif parent.has(key):
		parent[key] = value
	else:
		_insert_key(parent, key, value, index if index >= 0 else _schema_position(path.slice(0, -1), parent, key))
	changed.emit(path)

func _remove(path: Array) -> void:
	var parent: Variant = get_at(path.slice(0, -1))
	if parent is Array:
		parent.remove_at(path[-1])
	else:
		parent.erase(path[-1])
	changed.emit(path)

func _insert(path: Array, value: Variant) -> void:
	var list: Array = get_at(path.slice(0, -1))
	list.insert(path[-1], _copy(value))
	changed.emit(path)

func _move(list_path: Array, from: int, to: int) -> void:
	var list: Array = get_at(list_path)
	var item: Variant = list[from]
	list.remove_at(from)
	list.insert(to, item)
	changed.emit(list_path)

## Adds `key` at position `index` of `dict`, keeping the dictionary object
## (its parent holds a reference to it).
static func _insert_key(dict: Dictionary, key: Variant, value: Variant, index: int) -> void:
	var keys := dict.keys()
	if index < 0 or index >= keys.size():
		dict[key] = value
		return
	var old := dict.duplicate()
	dict.clear()
	for i: int in keys.size():
		if i == index:
			dict[key] = value
		dict[keys[i]] = old[keys[i]]

## Where a new `key` goes in `dict` (at `dict_path`): after the last existing
## key that the schema lists before it. -1 = at the end.
func _schema_position(dict_path: Array, dict: Dictionary, key: Variant) -> int:
	if schema == null:
		return -1
	var spec := schema.spec_at(data, dict_path)
	if spec == null or spec.type != "dict" or not spec.fields.has(key):
		return -1
	var order: Array = spec.fields.keys()
	var rank := order.find(key)
	var keys := dict.keys()
	var pos := 0
	for i: int in keys.size():
		var r := order.find(keys[i])
		if r >= 0 and r < rank:
			pos = i + 1
	return pos if pos < keys.size() else -1

static func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

static func _label(path: Array) -> String:
	return "/".join(path.map(func(k: Variant) -> String: return str(k)))
