@tool
extends Node3D

var _drawers: Array = []
var _world: MoldRuntimeInstance
var _recorder: MoldImmediateRecorder
var _dirty := true
var _had_active_drawer := false
var _had_camera := false
var _camera_transform := Transform3D.IDENTITY
var _camera_projection := 0
var _camera_fov := 0.0
var _camera_size := 0.0
var _camera_mask := 0
var _viewport_size := Vector2.ZERO


func _ready() -> void:
	process_priority = 900
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Scene-view previews use the detail requested by each immediate command.
	# Runtime drawers retain Mold's screen-space continuous LOD.
	var settings: MoldWorldSettings
	if Engine.is_editor_hint():
		settings = MoldWorldSettings.new()
		settings.lod_mode = MoldWorldSettings.LodMode.MANUAL
	_world = MoldRuntime.create_attached_instance(self, settings)
	_recorder = _world.create_immediate_recorder()


func _process(_delta: float) -> void:
	_remove_invalid_drawers()
	if _drawers.is_empty() or not _world: return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	var has_camera := camera != null
	var camera_changed := has_camera != _had_camera
	_had_camera = has_camera
	if camera:
		var transform := camera.global_transform
		var size := viewport.get_visible_rect().size
		camera_changed = camera_changed or transform != _camera_transform or camera.projection != _camera_projection or camera.fov != _camera_fov or camera.size != _camera_size or camera.cull_mask != _camera_mask or size != _viewport_size
		_camera_transform = transform; _camera_projection = camera.projection
		_camera_fov = camera.fov; _camera_size = camera.size
		_camera_mask = camera.cull_mask; _viewport_size = size
	var has_active_drawer := false
	var continuous := false
	for drawer in _drawers:
		if not drawer._mold_should_draw(camera): continue
		has_active_drawer = true
		continuous = continuous or drawer.continuously_redraw
	var activity_changed := has_active_drawer != _had_active_drawer
	_had_active_drawer = has_active_drawer
	if Engine.is_editor_hint() and not _dirty and not camera_changed and not continuous and not activity_changed: return
	if not Engine.is_editor_hint() and not has_active_drawer and not _dirty: return
	_dirty = false
	var token := _recorder.begin()
	for drawer in _drawers:
		if not _recorder.is_active(token): break
		if not drawer._mold_should_draw(camera): continue
		# Callbacks share commands but always begin with independent default state.
		_recorder.reset_state(token)
		drawer.draw_molds(_recorder, token, camera)
	_recorder.end(token)



func register(drawer: Node) -> void:
	if drawer not in _drawers: _drawers.append(drawer)
	_dirty = true


func unregister(drawer: Node) -> void:
	_drawers.erase(drawer)
	_dirty = true


func request_redraw() -> void:
	_dirty = true


func drawer_count() -> int:
	return _drawers.size()


func shutdown() -> void:
	set_process(false)
	_drawers.clear()
	if _world: _world.dispose()
	_world = null
	_recorder = null
	if is_inside_tree(): queue_free.call_deferred()


func _remove_invalid_drawers() -> void:
	for index in range(_drawers.size() - 1, -1, -1):
		if not is_instance_valid(_drawers[index]) or not _drawers[index].is_inside_tree():
			_drawers.remove_at(index)
