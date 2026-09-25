class_name MoldRuntimeInstance
extends MoldContext

var _disposed := false


func _init(world = null) -> void:
	super(world)


func dispose() -> void:
	if _disposed: return
	_disposed = true
	if is_instance_valid(_world): _world._shutdown()
