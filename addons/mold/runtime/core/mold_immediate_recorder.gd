class_name MoldImmediateRecorder
extends RefCounted

## Persistent immediate commands. Keep the recorder, but never reuse a frame token.
## Invalid/expired tokens, stack overflow and underflow return false without mutation.
## Allocate stack capacity at initialization; drawing never grows the stack.
class State:
	var position := Vector3.ZERO
	var rotation := Quaternion.IDENTITY
	var scale := Vector3.ONE
	var style := MoldStyle.new()
	var render_state := MoldRenderState.new()
	var thickness := 0.05
	var dash := MoldDash.new()

	func copy_from(other: State) -> void:
		position = other.position
		rotation = other.rotation
		scale = other.scale
		style.copy_from(other.style)
		render_state.copy_from(other.render_state)
		thickness = other.thickness
		dash.copy_from(other.dash)

	func reset() -> void:
		position = Vector3.ZERO
		rotation = Quaternion.IDENTITY
		scale = Vector3.ONE
		style._init()
		render_state._init()
		thickness = 0.05
		dash.copy_from(null)

var _world
var _token := 0
var _state := State.new()
var _states: Array[State] = []
var _depth := 0
var _scratch := MoldShape.new()

func _init(world, state_capacity: int = 16) -> void:
	_world = world
	_states.resize(maxi(0, state_capacity))
	for index in _states.size(): _states[index] = State.new()


## Starting a new frame invalidates all older frames for the same world.
func begin() -> int:
	if not is_instance_valid(_world) or not _world._is_available(): return 0
	_token = _world._begin_immediate_generation()
	_depth = 0
	_state.reset()
	return _token


func is_active(token: int) -> bool:
	return token > 0 and token == _token and is_instance_valid(_world) \
		and _world._is_available() and token == _world._immediate_generation


func end(token: int) -> bool:
	if not is_active(token): return false
	_token = 0
	_depth = 0
	return true


## Restore defaults and discard open scopes while keeping this frame's commands.
func reset_state(token: int) -> bool:
	if not is_active(token): return false
	_state.reset()
	_depth = 0
	return true


func push_state(token: int) -> bool:
	if not is_active(token) or _depth == _states.size(): return false
	_states[_depth].copy_from(_state)
	_depth += 1
	return true


func pop_state(token: int) -> bool:
	if not is_active(token) or _depth == 0: return false
	_depth -= 1
	_state.copy_from(_states[_depth])
	return true


func shape(token: int, value: MoldShape, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token) or not value: return false
	if _state.dash.is_enabled and value.supports_dashes:
		_scratch.copy_from(value)
		_scratch.dash.copy_from(_state.dash)
		value = _scratch
	_world._record_immediate(token, value, _state.position + _state.rotation * (local_position * _state.scale), _state.rotation * local_rotation, local_scale * _state.scale, _state.style, _state.render_state)
	return true


func polyline(token: int, value: MoldPolyline, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token) or not value: return false
	if _state.dash.is_enabled: value = value.with_dash(_state.dash)
	_world._record_immediate_polyline(token, value, _state.position + _state.rotation * (local_position * _state.scale), _state.rotation * local_rotation, local_scale * _state.scale, _state.style, _state.render_state)
	return true


func line(token: int, start: Vector3, finish: Vector3) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.line_2d(start, finish, maxf(_state.thickness, 0.0001), MoldShape.BillboardMode.DISABLED, 0.0, MoldShape.RectangleRoundnessMode.CORNER_LOCAL, _scratch))


func set_position(token: int, value: Vector3) -> bool:
	if not is_active(token): return false
	_state.position = value
	return true


func set_rotation(token: int, value: Quaternion) -> bool:
	if not is_active(token): return false
	_state.rotation = value
	return true


func set_scale(token: int, value: Vector3) -> bool:
	if not is_active(token): return false
	_state.scale = value
	return true


func set_thickness(token: int, value: float) -> bool:
	if not is_active(token): return false
	_state.thickness = value
	return true


func set_style(token: int, value: MoldStyle) -> bool:
	if not is_active(token): return false
	if value: _state.style.copy_from(value)
	else: _state.style._init()
	return true


func set_render_state(token: int, value: MoldRenderState) -> bool:
	if not is_active(token): return false
	_state.render_state.copy_from(value)
	return true


func set_dash(token: int, value: MoldDash) -> bool:
	if not is_active(token): return false
	_state.dash.copy_from(value)
	return true


func set_style_values(token: int, value_mode: MoldStyle.BlendMode = MoldStyle.BlendMode.OPAQUE, value_color: Color = Color.WHITE, secondary: Color = Color.TRANSPARENT, emission: float = 0.0, value_color_mode: MoldStyle.ColorMode = MoldStyle.ColorMode.SINGLE, interpolation: MoldStyle.ColorInterpolation = MoldStyle.ColorInterpolation.LINEAR_RGB, space: MoldStyle.GradientSpace = MoldStyle.GradientSpace.WORLD, direction: Vector3 = Vector3.UP, material: MoldMaterialHandle = null) -> bool:
	if not is_active(token): return false
	_state.style._init(value_mode, value_color, secondary, emission, value_color_mode, interpolation, space, direction, material)
	return true


func set_render_state_values(token: int, layer_mask: int = 1,
	order: int = 0,
	value_depth_test: MoldRenderState.DepthTest = MoldRenderState.DepthTest.LESS_EQUAL,
	value_depth_write: MoldRenderState.DepthWrite = MoldRenderState.DepthWrite.AUTO,
	value_stencil_flags: int = MoldRenderState.StencilFlags.DISABLED,
	value_stencil_compare: MoldRenderState.StencilCompare = MoldRenderState.StencilCompare.ALWAYS,
	value_stencil_reference: int = 0,
	value_face_cull: MoldRenderState.FaceCull = MoldRenderState.FaceCull.DISABLED) -> bool:
	if not is_active(token): return false
	_state.render_state._init(layer_mask, order, value_depth_test, value_depth_write, value_stencil_flags, value_stencil_compare, value_stencil_reference, value_face_cull)
	return true


func set_dash_fixed_count(token: int, count: int,
	dash_spacing: float = 0.1,
	dash_offset: float = 0.0,
	dash_type: MoldDash.Type = MoldDash.Type.NORMAL,
	dash_modifier: float = 0.0) -> bool:
	if not is_active(token) or count < 1 or count > 4096 or dash_spacing < 0.0 or dash_spacing > 1.0: return false
	_state.dash.copy_from(MoldDash.fixed_count(count, dash_spacing, dash_offset, dash_type, dash_modifier))
	return true


func set_dash_length(token: int, dash_length: float, gap: float,
		dash_snap: MoldDash.Snap = MoldDash.Snap.OFF, offset: float = 0.0,
		dash_type: MoldDash.Type = MoldDash.Type.NORMAL, dash_modifier: float = 0.0) -> bool:
	if not is_active(token): return false
	if not is_finite(dash_length) or dash_length <= 0.0 or not is_finite(gap) or gap < 0.0 or not is_finite(offset): return false
	if dash_snap < MoldDash.Snap.OFF or dash_snap > MoldDash.Snap.END_TO_END: return false
	_state.dash.copy_from(MoldDash.length(dash_length, gap, dash_snap, offset, dash_type, dash_modifier))
	return true


func rectangle(token: int, value: Vector2, value_roundness: float = 0.0, value_roundness_mode: MoldShape.RectangleRoundnessMode = MoldShape.RectangleRoundnessMode.CORNER_LOCAL, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.rectangle(value, value_roundness, value_roundness_mode, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func rectangle_rim(token: int, value: Vector2, value_thickness: float, value_roundness: float = 0.0, value_dash: MoldDash = null, value_roundness_mode: MoldShape.RectangleRoundnessMode = MoldShape.RectangleRoundnessMode.CORNER_LOCAL, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.rectangle_rim(value, value_thickness, value_roundness, value_dash, value_roundness_mode, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func disc(token: int, value_radius: float, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.disc(value_radius, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func disc_rim(token: int, value_radius: float, value_thickness: float, start: float = 0.0, span: float = TAU, value_dash: MoldDash = null, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.disc_rim(value_radius, value_thickness, start, span, value_dash, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func regular_polygon(token: int, value_sides: int, value_radius: float, value_roundness: float = 0.0, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.regular_polygon(value_sides, value_radius, value_roundness, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func regular_polygon_rim(token: int, value_sides: int, value_radius: float, value_thickness: float, value_roundness: float = 0.0, value_dash: MoldDash = null, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.regular_polygon_rim(value_sides, value_radius, value_thickness, value_roundness, value_dash, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func cuboid(token: int, value: Vector3, value_roundness: float = 0.0, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.cuboid(value, value_roundness, value_detail, _scratch), local_position, local_rotation, local_scale)


func line_2d(token: int, start: Vector3, end: Vector3, value_thickness: float, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, value_roundness: float = 0.0, value_roundness_mode: MoldShape.RectangleRoundnessMode = MoldShape.RectangleRoundnessMode.CORNER_LOCAL, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.line_2d(start, end, value_thickness, billboard, value_roundness, value_roundness_mode, _scratch), local_position, local_rotation, local_scale)


func line_3d(token: int, start: Vector3, end: Vector3, value_thickness: float, value_roundness: float = 0.0, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.line_3d(start, end, value_thickness, value_roundness, value_detail, _scratch), local_position, local_rotation, local_scale)


func cylinder(token: int, value_radius: float, value_height: float, value_roundness: float = 0.0, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.cylinder(value_radius, value_height, value_roundness, value_detail, _scratch), local_position, local_rotation, local_scale)


func regular_prism(token: int, value_sides: int, value_radius: float, value_height: float, value_roundness: float = 0.0, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.regular_prism(value_sides, value_radius, value_height, value_roundness, value_detail, _scratch), local_position, local_rotation, local_scale)


func cone(token: int, value_radius: float, value_height: float, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.cone(value_radius, value_height, value_detail, _scratch), local_position, local_rotation, local_scale)


func pyramid(token: int, value_sides: int, value_radius: float, value_height: float, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE, value_roundness: float = 0.0, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.pyramid(value_sides, value_radius, value_height, value_roundness, value_detail, _scratch), local_position, local_rotation, local_scale)


func sphere(token: int, value_radius: float, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.sphere(value_radius, value_detail, _scratch), local_position, local_rotation, local_scale)


func hemisphere(token: int, value_radius: float, value_capped: bool = true, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.hemisphere(value_radius, value_capped, value_detail, _scratch), local_position, local_rotation, local_scale)


func capsule(token: int, value_radius: float, total_height: float, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.capsule(value_radius, total_height, value_detail, _scratch), local_position, local_rotation, local_scale)


func torus(token: int, value_radius: float, value_thickness: float, start: float = 0.0, span: float = TAU, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.torus(value_radius, value_thickness, start, span, value_detail, _scratch), local_position, local_rotation, local_scale)


func set_opaque(token: int, value: Color) -> bool:
	if not is_active(token): return false
	_state.style._init(MoldStyle.BlendMode.OPAQUE, value)
	return true


func set_transparent(token: int, value: Color) -> bool:
	if not is_active(token): return false
	_state.style._init(MoldStyle.BlendMode.TRANSPARENT, value)
	return true


func set_additive(token: int, value: Color) -> bool:
	if not is_active(token): return false
	_state.style._init(MoldStyle.BlendMode.ADDITIVE, value)
	return true


func set_dual_radial(token: int, inner: Color, outer: Color, blend_mode: MoldStyle.BlendMode = MoldStyle.BlendMode.OPAQUE, interpolation: MoldStyle.ColorInterpolation = MoldStyle.ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> bool:
	if not is_active(token): return false
	_state.style._init(blend_mode, inner, outer, emission, MoldStyle.ColorMode.DUAL_RADIAL, interpolation)
	return true


func set_dual_directional(token: int, negative: Color, positive: Color, direction_or_emission: Variant = Vector3.UP, space: MoldStyle.GradientSpace = MoldStyle.GradientSpace.WORLD, blend_mode: MoldStyle.BlendMode = MoldStyle.BlendMode.OPAQUE, interpolation: MoldStyle.ColorInterpolation = MoldStyle.ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> bool:
	if not is_active(token): return false
	var direction := Vector3.UP
	if direction_or_emission is Vector3: direction = direction_or_emission
	elif direction_or_emission is float or direction_or_emission is int: emission = float(direction_or_emission)
	else: push_error("MoldStyle.dual_directional direction must be a Vector3.")
	_state.style._init(blend_mode, negative, positive, emission, MoldStyle.ColorMode.DUAL_DIRECTIONAL, interpolation, space, direction)
	return true

func curve(token: int,value: MoldCurve,stroke: MoldStroke = null,sampling: MoldCurveSampling = null) -> void:
	var path := value.to_polyline(stroke,sampling)
	if path: polyline(token,path)


func ellipse(token: int, value: Vector2, start: float = 0.0, span: float = TAU, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.ellipse(value, start, span, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func ellipse_rim(token: int, value: Vector2, value_thickness: float, start: float = 0.0, span: float = TAU, value_dash: MoldDash = null, billboard: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	if billboard < MoldShape.BillboardMode.DISABLED or billboard > MoldShape.BillboardMode.FACE_CAMERA_Y: return false
	var prepared := MoldShape.ellipse_rim(value, value_thickness, start, span, value_dash, _scratch)
	if not prepared: return false
	prepared.billboard_mode = billboard
	return shape(token, prepared, local_position, local_rotation, local_scale)


func ellipsoid(token: int, value: Vector3, value_detail: MoldShape.Detail = MoldShape.Detail.MEDIUM, local_position: Vector3 = Vector3.ZERO, local_rotation: Quaternion = Quaternion.IDENTITY, local_scale: Vector3 = Vector3.ONE) -> bool:
	if not is_active(token): return false
	return shape(token, MoldShape.ellipsoid(value, value_detail, _scratch), local_position, local_rotation, local_scale)
