@tool
class_name MoldImmediateDrawer3D
extends Node3D

const DRIVER_SCRIPT = preload("res://addons/mold/runtime/components/mold_immediate_drawer_driver.gd")
const DRIVER_MARKER := &"_mold_immediate_drawer_driver"
static var _drivers: Dictionary = {}

@export var use_culling_mask := true:
	set(value):
		if use_culling_mask == value: return
		use_culling_mask = value
		request_redraw()
@export_flags_3d_render var render_layer_mask := 1:
	set(value):
		var next := value if value != 0 else 1
		if render_layer_mask == next: return
		render_layer_mask = next
		request_redraw()
@export var continuously_redraw := false:
	set(value):
		if continuously_redraw == value: return
		continuously_redraw = value
		request_redraw()

var _mold_drawer_driver: Node


func _enter_tree() -> void:
	set_notify_transform(true)
	set_process(true)
	_register_drawer.call_deferred()


func _exit_tree() -> void:
	_unregister_drawer()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		request_redraw()
	elif what == NOTIFICATION_PARENTED and is_inside_tree():
		_reregister_drawer.call_deferred()
	elif what == NOTIFICATION_PROCESS and is_inside_tree() and not is_instance_valid(_mold_drawer_driver):
		_register_drawer.call_deferred()


func draw_molds(_draw: MoldImmediateRecorder, _token: int, _camera: Camera3D) -> void:
	pass


func is_drawer_enabled() -> bool:
	return true


func request_redraw() -> void:
	if is_instance_valid(_mold_drawer_driver):
		_mold_drawer_driver.request_redraw()
	elif is_inside_tree():
		_register_drawer.call_deferred()


func _mold_should_draw(camera: Camera3D) -> bool:
	if not is_inside_tree() or not is_visible_in_tree() or not is_drawer_enabled(): return false
	if Engine.is_editor_hint():
		var editor_interface := Engine.get_singleton("EditorInterface")
		var edited_root: Node = editor_interface.get_edited_scene_root() if editor_interface else null
		if not edited_root or (self != edited_root and not edited_root.is_ancestor_of(self)):
			return false
	return not use_culling_mask or not camera or (camera.cull_mask & render_layer_mask) != 0


func _register_drawer() -> void:
	if not is_inside_tree(): return
	var viewport := get_viewport()
	# Godot hosts the driver on the viewport so inactive editor tabs can be
	# cleared when the active tab changes.
	var host := viewport
	var key := viewport.get_instance_id()
	var driver: Node = _drivers.get(key)
	if not is_instance_valid(driver) or driver.get_parent() != host:
		_drivers.erase(key)
		_remove_orphaned_drivers(viewport)
		driver = DRIVER_SCRIPT.new()
		driver.name = "__Mold Immediate Drawer Driver"
		driver.set_meta(DRIVER_MARKER, true)
		host.add_child(driver, false, Node.INTERNAL_MODE_BACK)
		_drivers[key] = driver
	_mold_drawer_driver = driver
	driver.register(self)


# Godot can retain native tool nodes after script static state is reloaded.
# Reclaim marked drivers before replacing their viewport registration.
func _remove_orphaned_drivers(viewport: Viewport) -> void:
	var pending: Array[Node] = [viewport]
	var orphans: Array[Node] = []
	while not pending.is_empty():
		var parent := pending.pop_back()
		for child in parent.get_children(true):
			if child.has_meta(DRIVER_MARKER): orphans.append(child)
			else:
				pending.append(child)
	for child in orphans:
		if child is Node3D: child.visible = false
		if child.has_method("shutdown"): child.shutdown()
		else: child.queue_free()


func _reregister_drawer() -> void:
	_unregister_drawer()
	_register_drawer()


func _unregister_drawer() -> void:
	var driver := _mold_drawer_driver
	_mold_drawer_driver = null
	if not is_instance_valid(driver): return
	driver.unregister(self)
	if driver.drawer_count() != 0: return
	if is_instance_valid(driver.get_viewport()):
		_drivers.erase(driver.get_viewport().get_instance_id())
	driver.shutdown()
