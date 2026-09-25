@tool
extends EditorProperty

var selector := OptionButton.new()
var _commit: Callable

func _init(labels: Array, commit: Callable, ids: Array = []):
	_commit = commit
	for i in labels.size(): selector.add_item(labels[i],ids[i] if not ids.is_empty() else i)
	add_child(selector)
	add_focusable(selector)
	selector.item_selected.connect(_selected)

func _selected(index: int) -> void:
	_commit.call(get_edited_object(), selector.get_item_id(index))

func _update_property() -> void:
	selector.select(selector.get_item_index(int(get_edited_object().get(get_edited_property()))))

func _set_read_only(value: bool) -> void:
	selector.disabled = value
