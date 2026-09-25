@tool
class_name MoldStyleResource
extends Resource

@export var mode: MoldStyle.BlendMode = MoldStyle.BlendMode.OPAQUE:
	set(value):
		if mode == value: return
		mode = value
		notify_property_list_changed()
		emit_changed()
@export var color := Color.WHITE:
	set(value):
		if color == value: return
		color = value
		emit_changed()
@export var custom_material: ShaderMaterial:
	set(value):
		if custom_material == value: return
		custom_material = value
		emit_changed()
@export var secondary_color := Color.WHITE:
	set(value):
		if secondary_color == value: return
		secondary_color = value
		emit_changed()
@export var shader_data := Vector4.ZERO:
	set(value):
		if shader_data == value: return
		shader_data = value
		emit_changed()
@export var shader_data_2 := Vector4.ZERO:
	set(value):
		if shader_data_2 == value: return
		shader_data_2 = value
		emit_changed()
@export var color_mode: MoldStyle.ColorMode = MoldStyle.ColorMode.SINGLE:
	set(value):
		if color_mode == value: return
		color_mode = value
		notify_property_list_changed()
		emit_changed()
## Blends the style’s primary and secondary colors; the result multiplies point colors.
@export var style_color_interpolation: MoldStyle.ColorInterpolation = MoldStyle.ColorInterpolation.LINEAR_RGB:
	set(value):
		if style_color_interpolation == value: return
		style_color_interpolation = value
		emit_changed()
@export var gradient_space: MoldStyle.GradientSpace = MoldStyle.GradientSpace.WORLD:
	set(value):
		if gradient_space == value: return
		gradient_space = value
		emit_changed()
@export var gradient_direction := Vector3.UP:
	set(value):
		if gradient_direction == value: return
		gradient_direction = value
		emit_changed()
@export_range(0.0, 16.0, 0.01, "or_greater") var emission_strength := 0.0:
	set(value):
		var next := maxf(value, 0.0) if is_finite(value) else 0.0
		if is_equal_approx(emission_strength, next): return
		emission_strength = next
		emit_changed()


@export var appearance: MoldAppearanceResource = MoldAppearanceResource.new():
	set(value):
		if appearance and appearance.changed.is_connected(_appearance_changed): appearance.changed.disconnect(_appearance_changed)
		appearance=value
		if appearance and not appearance.changed.is_connected(_appearance_changed): appearance.changed.connect(_appearance_changed)
		_appearance_changed()
var _appearance_snapshot: MoldAppearanceSnapshot
func _init() -> void:
	if appearance: appearance.changed.connect(_appearance_changed)
func _appearance_changed() -> void:
	_appearance_snapshot=appearance.snapshot() if appearance else null
	emit_changed()

## Supply owned scratch storage to avoid allocating a style during refresh.
func to_style(material_handle: MoldMaterialHandle = null, destination: MoldStyle = null) -> MoldStyle:
	if mode == MoldStyle.BlendMode.CUSTOM and (not material_handle or not material_handle.is_valid):
		push_error("A valid custom material handle is required.")
		return null
	var result := destination if destination else MoldStyle.new()
	if mode == MoldStyle.BlendMode.CUSTOM:
		result._init(mode,color,Color.TRANSPARENT,0.0,MoldStyle.ColorMode.SINGLE,MoldStyle.ColorInterpolation.LINEAR_RGB,MoldStyle.GradientSpace.WORLD,Vector3.UP,material_handle,null,shader_data,shader_data_2)
	elif color_mode == MoldStyle.ColorMode.DUAL_DIRECTIONAL:
		result._init(mode,color,secondary_color,emission_strength,color_mode,style_color_interpolation,gradient_space,gradient_direction)
	elif color_mode == MoldStyle.ColorMode.DUAL_RADIAL or color_mode == MoldStyle.ColorMode.DUAL_RADIAL_BOUNDS or color_mode == MoldStyle.ColorMode.DUAL_ANGULAR:
		result._init(mode,color,secondary_color,emission_strength,color_mode,style_color_interpolation)
	else:
		var blend := mode
		if blend < MoldStyle.BlendMode.OPAQUE or blend > MoldStyle.BlendMode.COLOR_BURN or blend == 5: blend=MoldStyle.BlendMode.OPAQUE
		result._init(blend,color)
	result.appearance=_appearance_snapshot
	return result


func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	var path_style := false
	if property_name in ["color_mode", "gradient_space", "gradient_direction"]:
		for connection in get_signal_connection_list("changed"):
			if connection.callable.get_object() is MoldPolylineNode3D:
				path_style = true; break
		if path_style and property_name == "color_mode": property.hint_string = "Single:0,DualDirectional:1"
	var visible := true
	if property_name == "appearance": visible = mode != MoldStyle.BlendMode.CUSTOM
	elif property_name == "custom_material": visible = mode == MoldStyle.BlendMode.CUSTOM
	elif property_name in ["shader_data", "shader_data_2"]: visible = mode == MoldStyle.BlendMode.CUSTOM
	elif property_name == "color_mode": visible = mode != MoldStyle.BlendMode.CUSTOM
	elif property_name in ["secondary_color", "style_color_interpolation", "emission_strength"]: visible = mode != MoldStyle.BlendMode.CUSTOM and color_mode != MoldStyle.ColorMode.SINGLE
	elif property_name in ["gradient_space", "gradient_direction"]: visible = not path_style and mode != MoldStyle.BlendMode.CUSTOM and color_mode == MoldStyle.ColorMode.DUAL_DIRECTIONAL
	if not visible: property.usage &= ~PROPERTY_USAGE_EDITOR
