class_name OutlineDrag
extends RefCounted
## Drag-to-reorder for the editor's outline tree: rows that are items of a
## list can be dragged before/after other items of the same list.

var _editor: ScenarioEditor

func _init(editor: ScenarioEditor) -> void:
	_editor = editor
	var tree := editor.outline
	tree.set_drag_forwarding(_get_drag, _can_drop, _drop)

## The path of the outline row under a Tree-local position, or null.
func _path_at(at: Vector2) -> Variant:
	var item := _editor.outline.get_item_at_position(at)
	if item == null:
		return null
	return _editor.rows[int(item.get_metadata(0))]["path"]

func _get_drag(at: Vector2) -> Variant:
	var item := _editor.outline.get_item_at_position(at)
	if item == null:
		return null
	var path: Array = _editor.rows[int(item.get_metadata(0))]["path"]
	if path.is_empty() or not path[-1] is int:
		return null
	var label := Label.new()
	label.text = item.get_text(0)
	_editor.outline.set_drag_preview(label)
	_editor.outline.drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	return {"outline_path": path}

func _plan(at: Vector2, data: Variant) -> Dictionary:
	if not (data is Dictionary and data.has("outline_path")):
		return {}
	var onto: Variant = _path_at(at)
	if onto == null:
		return {}
	return EditorOutline.drop_move(data["outline_path"], onto, _editor.outline.get_drop_section_at_position(at))

func _can_drop(at: Vector2, data: Variant) -> bool:
	return not _plan(at, data).is_empty()

func _drop(at: Vector2, data: Variant) -> void:
	var move := _plan(at, data)
	if not move.is_empty():
		apply(move)

## Performs a move from EditorOutline.drop_move and selects the moved item.
func apply(move: Dictionary) -> void:
	var path: Array = move["path"]
	_editor.doc.move_item(path, move["to"], "Reorder")
	_editor._select_path(path.slice(0, -1) + [move["to"]])
