@tool
class_name MoldShapeResource
extends Resource

@export var kind: MoldShape.Kind = MoldShape.Kind.CUBOID: set = _set_kind
@export var size_2d := Vector2.ONE: set = _set_size_2d
@export var size_3d := Vector3.ONE: set = _set_size_3d
@export_range(0.0, 10.0, 0.01, "or_greater") var radius := 0.5: set = _set_radius
@export_range(0.0, 10.0, 0.01, "or_greater") var height := 1.0: set = _set_height
@export_range(0.0, 10.0, 0.01, "or_greater") var thickness := 0.1: set = _set_thickness
@export_range(0.0, 1.0, 0.001) var roundness := 0.25: set = _set_roundness
@export var roundness_mode: MoldShape.RectangleRoundnessMode = MoldShape.RectangleRoundnessMode.CORNER_LOCAL: set = _set_roundness_mode
@export_range(-180.0, 180.0, 0.1, "or_less", "or_greater", "degrees") var start_degrees := 0.0: set = _set_start_degrees
@export_range(0.0, 360.0, 0.1, "degrees") var span_degrees := 360.0: set = _set_span_degrees
@export_range(3, 128, 1) var sides := 6: set = _set_sides
@export var detail: MoldShape.Detail = MoldShape.Detail.MEDIUM: set = _set_detail
@export var capped := true: set = _set_capped
@export var billboard_mode: MoldShape.BillboardMode = MoldShape.BillboardMode.DISABLED: set = _set_billboard_mode

@export_group("Line")
@export var line_enabled := false: set = _set_line_enabled
@export var start_position := Vector3(-0.5, 0.0, 0.0): set = _set_start_position
@export var end_position := Vector3(0.5, 0.0, 0.0): set = _set_end_position

@export_group("Dash")
@export var dashed := false: set = _set_dashed
@export var dash_mode: MoldDash.Mode = MoldDash.Mode.FIXED_COUNT: set = _set_dash_mode
@export var dash_snap: MoldDash.Snap = MoldDash.Snap.OFF: set = _set_dash_snap
@export_range(1, 4096, 1) var dash_count := 8: set = _set_dash_count
@export_range(0.0001, 1.0, 0.0001, "or_greater") var dash_length := 0.1: set = _set_dash_length
@export_range(0.0, 1.0, 0.001, "or_greater") var dash_spacing := 0.5: set = _set_dash_spacing
@export_range(-1.0, 1.0, 0.001, "or_less", "or_greater") var dash_offset := 0.0: set = _set_dash_offset
@export var dash_type: MoldDash.Type = MoldDash.Type.NORMAL: set = _set_dash_type
@export_range(-1.0, 1.0, 0.001) var dash_modifier := 0.0: set = _set_dash_modifier


func _changed() -> void: emit_changed()
func _set_kind(value: MoldShape.Kind) -> void:
	if kind == value: return
	if line_enabled and _is_line_capable(value) and not _valid_line_configuration(
		value, start_position, end_position, thickness, billboard_mode): return
	kind = value
	if line_enabled and not _is_line_capable(kind): line_enabled = false
	if kind == MoldShape.Kind.CAPSULE and height > 0.0 and radius > 0.0 \
			and height < radius * 2.0: height = radius * 2.0
	notify_property_list_changed()
	_changed()
func _set_size_2d(value: Vector2) -> void:
	var next := Vector2(_non_negative(value.x), _non_negative(value.y))
	if size_2d == next: return
	size_2d = next
	_changed()
func _set_size_3d(value: Vector3) -> void:
	var next := Vector3(_non_negative(value.x), _non_negative(value.y), _non_negative(value.z))
	if size_3d == next: return
	size_3d = next
	_changed()
func _set_radius(value: float) -> void:
	var next := _non_negative(value)
	var next_height := maxf(height, next * 2.0) if kind == MoldShape.Kind.CAPSULE \
			and height > 0.0 and next > 0.0 else height
	if is_equal_approx(radius, next) and is_equal_approx(height, next_height): return
	radius = next
	height = next_height
	_changed()
func _set_height(value: float) -> void:
	var next := _non_negative(value)
	if kind == MoldShape.Kind.CAPSULE and next > 0.0 and radius > 0.0:
		next = maxf(next, radius * 2.0)
	if is_equal_approx(height, next): return
	height = next
	_changed()
func _set_thickness(value: float) -> void:
	var next := _non_negative(value)
	if is_equal_approx(thickness, next): return
	thickness = next
	_changed()
func _set_roundness(value: float) -> void:
	var next := clampf(_finite(value), 0.0, 1.0)
	if is_equal_approx(roundness, next): return
	roundness = next
	_changed()
func _set_roundness_mode(value: MoldShape.RectangleRoundnessMode) -> void:
	var next := value if value >= MoldShape.RectangleRoundnessMode.CORNER_LOCAL \
		and value <= MoldShape.RectangleRoundnessMode.SHAPE_RELATIVE \
		else MoldShape.RectangleRoundnessMode.CORNER_LOCAL
	if roundness_mode == next: return
	roundness_mode = next
	_changed()
func _set_start_degrees(value: float) -> void:
	var next := _finite(value)
	if is_equal_approx(start_degrees, next): return
	start_degrees = next
	_changed()
func _set_span_degrees(value: float) -> void:
	var next := clampf(_finite(value), 0.0, 360.0)
	if is_equal_approx(span_degrees, next): return
	span_degrees = next
	_changed()
func _set_sides(value: int) -> void:
	var next := clampi(value, 3, 128)
	if sides == next: return
	sides = next
	_changed()
func _set_detail(value: MoldShape.Detail) -> void:
	if detail == value: return
	detail = value
	_changed()
func _set_capped(value: bool) -> void:
	if capped == value: return
	capped = value
	_changed()
func _set_billboard_mode(value: MoldShape.BillboardMode) -> void:
	if line_enabled and kind == MoldShape.Kind.RECTANGLE and not _valid_line_configuration(
		kind, start_position, end_position, thickness, value): return
	if billboard_mode == value: return
	billboard_mode = value
	_changed()
func _set_line_enabled(value: bool) -> void:
	var next := value and _is_line_capable(kind)
	if line_enabled == next: return
	if next and not _valid_line_configuration(
		kind, start_position, end_position, thickness, billboard_mode): return
	line_enabled = next
	notify_property_list_changed()
	_changed()
func _set_start_position(value: Vector3) -> void:
	var next := value if value.is_finite() else Vector3(-0.5, 0.0, 0.0)
	if line_enabled and not _valid_line_configuration(
		kind, next, end_position, thickness, billboard_mode): return
	if start_position == next: return
	start_position = next
	_changed()
func _set_end_position(value: Vector3) -> void:
	var next := value if value.is_finite() else Vector3(0.5, 0.0, 0.0)
	if line_enabled and not _valid_line_configuration(
		kind, start_position, next, thickness, billboard_mode): return
	if end_position == next: return
	end_position = next
	_changed()
func _set_dashed(value: bool) -> void:
	if dashed == value: return
	dashed = value
	notify_property_list_changed()
	_changed()
func _set_dash_mode(value: MoldDash.Mode) -> void:
	var next := value if value >= MoldDash.Mode.FIXED_COUNT and value <= MoldDash.Mode.LENGTH else MoldDash.Mode.FIXED_COUNT
	if dash_mode == next: return
	dash_mode = next
	notify_property_list_changed()
	_changed()
func _set_dash_snap(value: MoldDash.Snap) -> void:
	var next := value if value >= MoldDash.Snap.OFF and value <= MoldDash.Snap.END_TO_END else MoldDash.Snap.OFF
	if dash_snap == next: return
	dash_snap = next
	_changed()
func _set_dash_count(value: int) -> void:
	var next := clampi(value, 1, 4096)
	if dash_count == next: return
	dash_count = next
	_changed()
func _set_dash_length(value: float) -> void:
	var next := maxf(_finite(value, 0.1), 0.0001)
	if is_equal_approx(dash_length, next): return
	dash_length = next
	_changed()
func _set_dash_spacing(value: float) -> void:
	var next := maxf(_finite(value), 0.0)
	if is_equal_approx(dash_spacing, next): return
	dash_spacing = next
	_changed()
func _set_dash_offset(value: float) -> void:
	var next := _finite(value)
	if is_equal_approx(dash_offset, next): return
	dash_offset = next
	_changed()
func _set_dash_type(value: MoldDash.Type) -> void:
	if dash_type == value: return
	dash_type = value
	_changed()
func _set_dash_modifier(value: float) -> void:
	var next := clampf(_finite(value), -1.0, 1.0)
	if is_equal_approx(dash_modifier, next): return
	dash_modifier = next
	_changed()


static func _finite(value: float, fallback := 0.0) -> float:
	return value if is_finite(value) else fallback


static func _non_negative(value: float) -> float:
	return maxf(_finite(value), 0.0)


func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	if property_name == "dash_spacing":
		property.hint_string = "0,1,0.001" if dash_mode == MoldDash.Mode.FIXED_COUNT else "0,1,0.001,or_greater"
	var line_capable := _is_line_capable(kind)
	var line := line_capable and line_enabled
	var visible := true
	if property_name == "size_2d": visible = not line and kind in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.ELLIPSE, MoldShape.Kind.ELLIPSE_RIM]
	elif property_name == "size_3d": visible = not line and kind in [MoldShape.Kind.CUBOID, MoldShape.Kind.ELLIPSOID]
	elif property_name == "radius": visible = not line and kind not in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.CUBOID, MoldShape.Kind.ELLIPSOID, MoldShape.Kind.ELLIPSE, MoldShape.Kind.ELLIPSE_RIM]
	elif property_name == "height": visible = not line and kind in [MoldShape.Kind.CYLINDER, MoldShape.Kind.REGULAR_PRISM, MoldShape.Kind.CONE, MoldShape.Kind.CAPSULE, MoldShape.Kind.PYRAMID]
	elif property_name == "thickness": visible = line or kind in [MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.DISC_RIM, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.TORUS, MoldShape.Kind.ELLIPSE_RIM]
	elif property_name == "roundness": visible = (line and kind in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.CYLINDER]) or (not line and kind in [
		MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.REGULAR_POLYGON,
		MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.CUBOID, MoldShape.Kind.CYLINDER,
		MoldShape.Kind.REGULAR_PRISM, MoldShape.Kind.PYRAMID])
	elif property_name == "roundness_mode": visible = (line and kind == MoldShape.Kind.RECTANGLE) or (not line and kind in [
		MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM])
	elif property_name in ["start_degrees", "span_degrees"]: visible = kind in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.DISC, MoldShape.Kind.DISC_RIM, MoldShape.Kind.REGULAR_POLYGON, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.TORUS, MoldShape.Kind.ELLIPSE, MoldShape.Kind.ELLIPSE_RIM]
	elif property_name == "sides": visible = kind in [MoldShape.Kind.REGULAR_POLYGON, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.REGULAR_PRISM, MoldShape.Kind.PYRAMID]
	elif property_name == "detail": visible = kind == MoldShape.Kind.CYLINDER if line else not _is_2d_kind(kind)
	elif property_name == "capped": visible = kind == MoldShape.Kind.HEMISPHERE
	elif property_name == "billboard_mode": visible = (not line and _is_2d_kind(kind)) or (line and kind == MoldShape.Kind.RECTANGLE)
	elif property_name == "Line": visible = line_capable
	elif property_name == "line_enabled": visible = line_capable
	elif property_name in ["start_position", "end_position"]: visible = line
	elif property_name == "Dash": visible = _is_rim(kind) or line
	elif property_name == "dashed": visible = _is_rim(kind) or line
	elif property_name in ["dash_mode", "dash_spacing", "dash_offset"]: visible = (_is_rim(kind) or line) and dashed
	elif property_name == "dash_snap": visible = (_is_rim(kind) or line) and dashed and dash_mode == MoldDash.Mode.LENGTH
	elif property_name == "dash_count": visible = (_is_rim(kind) or line) and dashed and dash_mode == MoldDash.Mode.FIXED_COUNT
	elif property_name == "dash_length": visible = (_is_rim(kind) or line) and dashed and dash_mode != MoldDash.Mode.FIXED_COUNT
	elif property_name in ["dash_type", "dash_modifier"]: visible = (_is_rim(kind) or (line and kind == MoldShape.Kind.RECTANGLE)) and dashed
	if not visible: property.usage &= ~PROPERTY_USAGE_EDITOR


static func _is_2d_kind(value: MoldShape.Kind) -> bool:
	return value in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.DISC, MoldShape.Kind.DISC_RIM, MoldShape.Kind.REGULAR_POLYGON, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.ELLIPSE, MoldShape.Kind.ELLIPSE_RIM]


static func _is_rim(value: MoldShape.Kind) -> bool:
	return value in [MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.DISC_RIM, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.ELLIPSE_RIM]


static func _is_line_capable(value: MoldShape.Kind) -> bool:
	return value in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.CYLINDER]


static func _valid_line_configuration(value_kind: MoldShape.Kind, start: Vector3,
		end: Vector3, value_thickness: float,
		billboard: MoldShape.BillboardMode) -> bool:
	if not start.is_finite() or not end.is_finite(): return false
	if value_kind == MoldShape.Kind.RECTANGLE and billboard == MoldShape.BillboardMode.FACE_CAMERA_Y:
		return false
	return true


func is_valid_for_authoring() -> bool:
	return not line_enabled or not _is_line_capable(kind) or _valid_line_configuration(
		kind, start_position, end_position, thickness, billboard_mode)


func to_shape() -> MoldShape:
	var safe_radius := maxf(radius, 0.0)
	var safe_height := maxf(height, 0.0)
	var safe_thickness := maxf(thickness, 0.0)
	var safe_size_2d := Vector2(maxf(size_2d.x, 0.0), maxf(size_2d.y, 0.0))
	var safe_size_3d := Vector3(maxf(size_3d.x, 0.0), maxf(size_3d.y, 0.0), maxf(size_3d.z, 0.0))
	var safe_roundness := clampf(roundness, 0.0, 1.0)
	var dash := MoldDash.new()
	if dashed:
		dash = MoldDash.length(dash_length, dash_spacing, dash_snap, dash_offset, dash_type, dash_modifier) \
			if dash_mode == MoldDash.Mode.LENGTH else \
			MoldDash.fixed_count(dash_count, clampf(dash_spacing, 0.0, 1.0), dash_offset, dash_type, dash_modifier)
	if line_enabled and _is_line_capable(kind):
		var line_shape: MoldShape
		match kind:
			MoldShape.Kind.RECTANGLE: line_shape = MoldShape.line_2d(
				start_position, end_position, safe_thickness, billboard_mode,
				safe_roundness, roundness_mode)
			MoldShape.Kind.CYLINDER: line_shape = MoldShape.line_3d(start_position, end_position, safe_thickness, safe_roundness, detail)
		return line_shape.with_dash(dash) if dashed else line_shape
	var shape: MoldShape
	match kind:
		MoldShape.Kind.RECTANGLE: shape = MoldShape.rectangle(safe_size_2d, safe_roundness,
			roundness_mode, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.RECTANGLE_RIM: shape = MoldShape.rectangle_rim(
			safe_size_2d, safe_thickness, safe_roundness, dash, roundness_mode,
			deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.ELLIPSOID: shape = MoldShape.ellipsoid(safe_size_3d, detail)
		MoldShape.Kind.ELLIPSE: shape = MoldShape.ellipse(safe_size_2d, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.ELLIPSE_RIM: shape = MoldShape.ellipse_rim(safe_size_2d, safe_thickness, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)), dash)
		MoldShape.Kind.DISC: shape = MoldShape.disc(safe_radius, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.DISC_RIM: shape = MoldShape.disc_rim(safe_radius, safe_thickness, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)), dash)
		MoldShape.Kind.REGULAR_POLYGON: shape = MoldShape.regular_polygon(sides, safe_radius,
			safe_roundness, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.REGULAR_POLYGON_RIM: shape = MoldShape.regular_polygon_rim(sides,
			safe_radius, safe_thickness, safe_roundness, dash,
			deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)))
		MoldShape.Kind.CUBOID: shape = MoldShape.cuboid(safe_size_3d, safe_roundness, detail)
		MoldShape.Kind.CYLINDER: shape = MoldShape.cylinder(safe_radius, safe_height, safe_roundness, detail)
		MoldShape.Kind.REGULAR_PRISM: shape = MoldShape.regular_prism(sides, safe_radius, safe_height, safe_roundness, detail)
		MoldShape.Kind.CONE: shape = MoldShape.cone(safe_radius, safe_height, detail)
		MoldShape.Kind.PYRAMID: shape = MoldShape.pyramid(sides, safe_radius, safe_height, roundness, detail)
		MoldShape.Kind.SPHERE: shape = MoldShape.sphere(safe_radius, detail)
		MoldShape.Kind.HEMISPHERE: shape = MoldShape.hemisphere(safe_radius, capped, detail)
		MoldShape.Kind.CAPSULE: shape = MoldShape.capsule(safe_radius,
			maxf(safe_height, safe_radius * 2.0) if safe_height > 0.0 and safe_radius > 0.0 else safe_height, detail)
		MoldShape.Kind.TORUS: shape = MoldShape.torus(safe_radius, safe_thickness, deg_to_rad(start_degrees), deg_to_rad(clampf(span_degrees, 0.0, 360.0)), detail)
	if not shape: shape = MoldShape.cuboid(Vector3.ONE)
	if shape.is_2d and billboard_mode != MoldShape.BillboardMode.DISABLED:
		shape = shape.with_billboard(billboard_mode)
	return shape
