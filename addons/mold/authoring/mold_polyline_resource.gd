@tool
class_name MoldPolylineResource
extends Resource

@export var points: Array[MoldPolylinePointResource] = [
	_point(Vector3(-0.5, 0.0, 0.0)),
	_point(Vector3(0.0, 0.5, 0.0)),
	_point(Vector3(0.5, 0.0, 0.0)),
]:
	set(value):
		_disconnect_points()
		points = value if value else []
		_connect_points()
		emit_changed()

## Blends point colors before multiplying them by the style color.
@export var point_color_interpolation: MoldStyle.ColorInterpolation = MoldStyle.ColorInterpolation.LINEAR_RGB:
	set(value): point_color_interpolation = value; emit_changed()

@export var closed := false:
	set(value): closed = value; notify_property_list_changed(); emit_changed()

@export_range(0.0, 10.0, 0.01, "or_greater") var thickness := 0.05:
	set(value): thickness = maxf(value, 0.001) if is_finite(value) else 0.05; emit_changed()


@export var join: MoldPolyline.Join = MoldPolyline.Join.MITER:
	set(value): join = value; emit_changed()

@export_range(1.0, 10.0, 0.1, "or_greater") var miter_limit := 4.0:
	set(value): miter_limit = maxf(value, 1.0) if is_finite(value) else 4.0; emit_changed()


@export var cap: MoldPolyline.Cap = MoldPolyline.Cap.BUTT:
	set(value): cap = value; emit_changed()

@export var geometry: MoldPolyline.Geometry = MoldPolyline.Geometry.FLAT_2D:
	set(value):
		geometry = value
		if value == MoldPolyline.Geometry.FLAT_2D:
			_disconnect_points()
			for point in points:
				if point:
					var flat_position := point.position
					flat_position.z = 0.0
					point.position = flat_position
			_connect_points()
		notify_property_list_changed()
		emit_changed()

# Only layout changes should notify the property list; rebuilding it interrupts numeric drags.
@export_group("Dashes")
@export var dash_enabled := false:
	set(value): dash_enabled = value; notify_property_list_changed(); emit_changed()
@export var dash_mode: MoldDash.Mode = MoldDash.Mode.FIXED_COUNT:
	set(value):
		if dash_mode == value: return
		dash_mode = value; notify_property_list_changed(); emit_changed()
@export_range(1, 4096, 1) var dash_count := 8:
	set(value): dash_count = clampi(value, 1, 4096); emit_changed()
@export_range(0.0001, 1.0, 0.0001, "or_greater") var dash_length := 0.1:
	set(value): dash_length = maxf(value, 0.0001) if is_finite(value) else 0.1; emit_changed()
@export_range(0.0, 1.0, 0.001, "or_greater") var dash_spacing := 0.5:
	set(value): dash_spacing = maxf(value, 0.0) if is_finite(value) else 0.5; emit_changed()
@export var dash_snap: MoldDash.Snap = MoldDash.Snap.OFF:
	set(value): dash_snap = value; emit_changed()
@export_range(-1.0, 1.0, 0.001, "or_less", "or_greater") var dash_offset := 0.0:
	set(value): dash_offset = value if is_finite(value) else 0.0; emit_changed()
@export var dash_rounded := false:
	set(value): dash_rounded = value; emit_changed()

func to_dash() -> MoldDash:
	if not dash_enabled: return MoldDash.new()
	var type := MoldDash.Type.ROUNDED if dash_rounded else MoldDash.Type.NORMAL
	return MoldDash.length(dash_length, dash_spacing, dash_snap, dash_offset, type) if dash_mode == MoldDash.Mode.LENGTH else MoldDash.fixed_count(dash_count, clampf(dash_spacing,0,1), dash_offset, type)

func _init() -> void:
	_connect_points()


func to_polyline() -> MoldPolyline:
	var runtime_points: Array[MoldPolylinePoint] = []
	var count := points.size()
	runtime_points.resize(count)
	for index in count:
		assert(points[index] != null, "Polyline point %d is missing." % index)
		runtime_points[index] = points[index].to_point()
	return MoldPolyline.new(runtime_points, thickness, closed, join, cap,
		miter_limit, geometry, false, point_color_interpolation).with_dash(to_dash())


func _connect_points() -> void:
	var count := points.size()
	for index in count:
		var point := points[index]
		if point and not point.changed.is_connected(_on_point_changed):
			point.changed.connect(_on_point_changed)


func _disconnect_points() -> void:
	var count := points.size()
	for index in count:
		var point := points[index]
		if point and point.changed.is_connected(_on_point_changed):
			point.changed.disconnect(_on_point_changed)


func _on_point_changed() -> void:
	emit_changed()


func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	if property_name == "dash_spacing":
		property.hint_string = "0,1,0.001" if dash_mode == MoldDash.Mode.FIXED_COUNT else "0,1,0.001,or_greater"
	var visible := true
	match property_name:
		"cap": visible = not closed or dash_enabled
		"dash_count": visible = dash_enabled and dash_mode == MoldDash.Mode.FIXED_COUNT
		"dash_length", "dash_snap": visible = dash_enabled and dash_mode == MoldDash.Mode.LENGTH
		"dash_mode", "dash_spacing", "dash_offset", "dash_rounded": visible = dash_enabled
	if not visible: property.usage &= ~PROPERTY_USAGE_EDITOR


static func _point(value_position: Vector3) -> MoldPolylinePointResource:
	var result := MoldPolylinePointResource.new()
	result.position = value_position
	return result
