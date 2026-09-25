class_name MoldCurveStream
extends RefCounted
## World-owned GPU curve stream backed by a reusable sampler.
enum DistanceMode { CURRENT_LENGTHS, REST_LENGTHS }
var distance_mode := DistanceMode.CURRENT_LENGTHS
var _renderer: MoldGpuPolylineRenderer
var _sampler := MoldCurveSampler.new()
var is_valid: bool:
	get: return _renderer != null and _renderer.is_valid
var sample_count: int:
	get: return _sampler.sample_count
func _init(renderer: MoldGpuPolylineRenderer) -> void:
	_renderer=renderer
func set_curve(curve: MoldCurve,stroke: MoldStroke = null,sampling: MoldCurveSampling = null) -> bool:
	if not is_valid: return false
	if not stroke: stroke=MoldStroke.new()
	if not _sampler.set_curve(curve,stroke,sampling): return false
	_renderer.geometry=stroke.geometry
	_renderer.join=stroke.join; _renderer.cap=stroke.cap; _renderer.miter_limit=stroke.miter_limit
	_renderer.set_data(_sampler._points,[MoldGpuPolylineRange.new(0,sample_count,curve.closed)])
	return true
func update_curve(curve: MoldCurve,recalculate_bounds := true) -> bool:
	if not is_valid or not _sampler.update_curve(curve): return false
	_upload(recalculate_bounds); return true
func update_bezier_knots(knots: PackedFloat32Array,recalculate_bounds := true) -> bool:
	if not is_valid or not _sampler.update_bezier_knots(knots): return false
	_upload(recalculate_bounds); return true
func update_catmull_rom_points(points: PackedVector3Array,recalculate_bounds := true) -> bool:
	if not is_valid or not _sampler.update_catmull_rom_points(points): return false
	_upload(recalculate_bounds); return true
func _upload(bounds: bool) -> void:
	_renderer.update_points(_sampler._points,bounds)
	if distance_mode==DistanceMode.CURRENT_LENGTHS: _renderer.recalculate_distances()
func configure(style: MoldStyle,state: MoldRenderState = null) -> void: _renderer.configure(style,state)
func set_transform(value: Transform3D) -> void: _renderer.set_transform(value)
func set_visible(value: bool) -> void: _renderer.set_visible(value)
func set_dash(value: MoldDash) -> void: _renderer.set_dash(value)
func set_reveal(value: float) -> void: _renderer.set_reveal(value)
func set_local_bounds(value: AABB) -> void: _renderer.set_local_bounds(value)
func dispose() -> void: _renderer.dispose()
