class_name MoldContext
extends RefCounted

var _world
var transparent_ordering_mode: MoldWorldSettings.TransparentOrderingMode:
	get: return _required_world().transparent_ordering_mode
	set(value): _required_world().transparent_ordering_mode = value

var is_valid: bool:
	get: return is_instance_valid(_world) and _world._is_available()

var performance_metrics: MoldPerformanceMetrics:
	get: return _required_world().performance_metrics

var statistics: MoldStatistics:
	get:
		var target = _required_world()
		return target.statistics if target else MoldStatistics.new()


func statistics_into(result: MoldStatistics) -> void:
	_required_world().statistics_into(result)

func _init(world = null) -> void:
	_world = world


func create(shape: MoldShape, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _required_world().create(shape, style, render_state)


func create_transformed(shape: MoldShape, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _required_world().create_transformed(shape, position, rotation, scale, style, render_state)


func create_polyline(polyline: MoldPolyline, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO) -> MoldHandle:
	return _required_world().create_polyline(polyline, style, render_state, backend)


func create_polyline_transformed(polyline: MoldPolyline, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO) -> MoldHandle:
	return _required_world().create_polyline_transformed(polyline, position, rotation, scale, style, render_state, backend)


## Create once and retain. Commands use scalar frame tokens for stale-frame protection.
func create_immediate_recorder(state_capacity: int = 16) -> MoldImmediateRecorder:
	return MoldImmediateRecorder.new(_required_world(), state_capacity)


func prewarm(shapes: Array) -> void:
	_required_world().prewarm(shapes)


func clear_unused_meshes() -> void:
	_required_world().clear_unused_meshes()


func register_material(material: ShaderMaterial) -> MoldMaterialHandle:
	return _required_world().register_material(material)


func update_line_positions_bulk(handles: Array[MoldHandle], starts: PackedVector3Array, ends: PackedVector3Array) -> int:
	return _required_world().update_line_positions_bulk(handles, starts, ends)


func update_positions_bulk(handles: Array[MoldHandle], positions: PackedVector3Array) -> int:
	return _required_world().update_positions_bulk(handles, positions)


func update_transforms_bulk(handles: Array[MoldHandle], positions: PackedVector3Array, rotations: Array[Quaternion], scales: PackedVector3Array) -> int:
	return _required_world().update_transforms_bulk(handles, positions, rotations, scales)


func update_colors_bulk(handles: Array[MoldHandle], colors: PackedColorArray) -> int:
	return _required_world().update_colors_bulk(handles, colors)


func update_shader_data(handle: MoldHandle, value: Vector4) -> void:
	_required_world().update_shader_data(handle, value)

func update_shader_data_2(handle: MoldHandle, value: Vector4) -> void:
	_required_world().update_shader_data_2(handle, value)


func update_shader_data_bulk(handles: Array[MoldHandle], values: Array[Vector4]) -> int:
	return _required_world().update_shader_data_bulk(handles, values)

func update_shader_data_2_bulk(handles: Array[MoldHandle], values: Array[Vector4]) -> int:
	return _required_world().update_shader_data_2_bulk(handles, values)


func _required_world():
	if not is_instance_valid(_world) or not _world._is_available():
		push_error("The runtime that owned this Mold context is no longer active.")
		return null
	return _world


func create_gpu_polyline_renderer() -> MoldGpuPolylineRenderer:
	return _required_world().create_gpu_polyline_renderer()


func create_polygon(polygon: MoldPolygon, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolygonBackend.Mode = MoldPolygonBackend.Mode.AUTO) -> MoldPolygonRenderer:
	return _required_world().create_polygon(polygon, style, render_state, backend)

func create_curve(curve: MoldCurve,stroke: MoldStroke = null,style: MoldStyle = null,render_state: MoldRenderState = null,backend := MoldPolylineBackend.Mode.AUTO,sampling: MoldCurveSampling = null) -> MoldHandle:
	if not curve: push_error("A curve is required."); return null
	var path := curve.to_polyline(stroke,sampling)
	return create_polyline(path,style,render_state,backend) if path else null

func create_curve_stream(curve: MoldCurve,stroke: MoldStroke = null,sampling: MoldCurveSampling = null) -> MoldCurveStream:
	var stream := MoldCurveStream.new(create_gpu_polyline_renderer())
	if not stream.set_curve(curve,stroke,sampling): stream.dispose(); return null
	return stream
