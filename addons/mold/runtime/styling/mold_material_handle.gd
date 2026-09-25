class_name MoldMaterialHandle
extends RefCounted

var _world
var _id := 0

var is_valid: bool:
	get:
		return is_instance_valid(_world) and _world._is_material_handle_valid(self)


func _init(world = null, id := 0) -> void:
	_world = world
	_id = id


func equals(other: MoldMaterialHandle) -> bool:
	return other != null and _world == other._world and _id == other._id
