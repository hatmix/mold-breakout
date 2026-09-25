class_name MoldStyle
extends RefCounted

enum BlendMode {
	OPAQUE = 0,
	TRANSPARENT = 1,
	ADDITIVE = 2,
	MULTIPLICATIVE = 3,
	DITHER = 4,
	CUSTOM = 6,
	SUBTRACTIVE = 7,
	LINEAR_BURN = 8,
	SCREEN = 9,
	LIGHTEN = 10,
	DARKEN = 11,
	COLOR_DODGE = 12,
	COLOR_BURN = 13,
}

enum ColorMode {
	SINGLE = 0,
	DUAL_DIRECTIONAL = 1,
	DUAL_RADIAL = 2,
	DUAL_RADIAL_BOUNDS = 3,
	DUAL_ANGULAR = 4,
}
enum ColorInterpolation { LINEAR_RGB = 0, OKLAB = 1 }
enum GradientSpace { WORLD = 0, OBJECT = 1 }

var appearance: MoldAppearanceSnapshot
var mode: BlendMode
var color: Color
var secondary_color: Color
var custom_material: MoldMaterialHandle
var emission_strength: float
var color_mode: ColorMode
var color_interpolation: ColorInterpolation
var gradient_space: GradientSpace
var gradient_direction: Vector3
var shader_data: Vector4
var shader_data_2: Vector4


func _init(value_mode: BlendMode = BlendMode.OPAQUE, value_color: Color = Color.WHITE, secondary: Color = Color.TRANSPARENT, emission: float = 0.0, value_color_mode: ColorMode = ColorMode.SINGLE, interpolation: ColorInterpolation = ColorInterpolation.LINEAR_RGB, space: GradientSpace = GradientSpace.WORLD, direction: Vector3 = Vector3.UP, material: MoldMaterialHandle = null, value_appearance: MoldAppearanceSnapshot = null, value_shader_data := Vector4.ZERO, value_shader_data_2 := Vector4.ZERO) -> void:
	appearance = value_appearance
	mode = value_mode
	color = value_color
	secondary_color = secondary
	custom_material = material
	emission_strength = maxf(0.0, emission)
	color_mode = value_color_mode
	color_interpolation = interpolation
	gradient_space = space
	gradient_direction = direction.normalized() if direction.length_squared() >= 0.000001 else Vector3.UP
	shader_data = value_shader_data
	shader_data_2 = value_shader_data_2


## Copy into owned storage without creating another style object.
func copy_from(value: MoldStyle) -> void:
	_init(value.mode,value.color,value.secondary_color,value.emission_strength,value.color_mode,value.color_interpolation,value.gradient_space,value.gradient_direction,value.custom_material,value.appearance,value.shader_data,value.shader_data_2)


static func opaque(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.OPAQUE, value)
static func transparent(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.TRANSPARENT, value)
static func additive(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.ADDITIVE, value)
static func multiplicative(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.MULTIPLICATIVE, value)
static func subtractive(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.SUBTRACTIVE, value)
static func linear_burn(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.LINEAR_BURN, value)
static func screen(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.SCREEN, value)
static func lighten(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.LIGHTEN, value)
static func darken(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.DARKEN, value)
static func color_dodge(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.COLOR_DODGE, value)
static func color_burn(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.COLOR_BURN, value)
static func dither(value: Color) -> MoldStyle: return MoldStyle.new(BlendMode.DITHER, value)
static func custom(material: MoldMaterialHandle, value: Color, data := Vector4.ZERO, data_2 := Vector4.ZERO) -> MoldStyle:
	if not material or not material.is_valid:
		push_error("A valid custom material handle is required.")
		return null
	return MoldStyle.new(BlendMode.CUSTOM, value, Color.TRANSPARENT, 0.0, ColorMode.SINGLE, ColorInterpolation.LINEAR_RGB, GradientSpace.WORLD, Vector3.UP, material, null, data, data_2)
static func dual_radial(inner: Color, outer: Color, blend_mode: BlendMode = BlendMode.OPAQUE, interpolation: ColorInterpolation = ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> MoldStyle:
	return MoldStyle.new(blend_mode, inner, outer, emission, ColorMode.DUAL_RADIAL, interpolation)


static func dual_radial_bounds(inner: Color, outer: Color, blend_mode: BlendMode = BlendMode.OPAQUE, interpolation: ColorInterpolation = ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> MoldStyle:
	return MoldStyle.new(blend_mode, inner, outer, emission, ColorMode.DUAL_RADIAL_BOUNDS, interpolation)


static func dual_angular(start: Color, end: Color, blend_mode: BlendMode = BlendMode.OPAQUE, interpolation: ColorInterpolation = ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> MoldStyle:
	return MoldStyle.new(blend_mode, start, end, emission, ColorMode.DUAL_ANGULAR, interpolation)


static func dual_directional(negative: Color, positive: Color, direction_or_emission: Variant = Vector3.UP, space: GradientSpace = GradientSpace.WORLD, blend_mode: BlendMode = BlendMode.OPAQUE, interpolation: ColorInterpolation = ColorInterpolation.LINEAR_RGB, emission: float = 0.0) -> MoldStyle:
	var direction := Vector3.UP
	if direction_or_emission is Vector3: direction = direction_or_emission
	elif direction_or_emission is float or direction_or_emission is int: emission = float(direction_or_emission)
	else: push_error("MoldStyle.dual_directional direction must be a Vector3.")
	return MoldStyle.new(blend_mode, negative, positive, emission, ColorMode.DUAL_DIRECTIONAL, interpolation, space, direction)


func with_color(value: Color) -> MoldStyle: return MoldStyle.new(mode, value, secondary_color, emission_strength, color_mode, color_interpolation, gradient_space, gradient_direction, custom_material, appearance, shader_data, shader_data_2)
func with_secondary_color(value: Color) -> MoldStyle: return MoldStyle.new(mode, color, value, emission_strength, color_mode, color_interpolation, gradient_space, gradient_direction, custom_material, appearance, shader_data, shader_data_2)
func with_gradient_direction(direction: Vector3, space: GradientSpace = GradientSpace.WORLD) -> MoldStyle: return MoldStyle.new(mode, color, secondary_color, emission_strength, color_mode, color_interpolation, space, direction, custom_material, appearance, shader_data, shader_data_2)
func with_color_interpolation(interpolation: ColorInterpolation) -> MoldStyle: return MoldStyle.new(mode, color, secondary_color, emission_strength, color_mode, interpolation, gradient_space, gradient_direction, custom_material, appearance, shader_data, shader_data_2)
func with_shader_data(data: Vector4) -> MoldStyle: return MoldStyle.new(mode, color, secondary_color, emission_strength, color_mode, color_interpolation, gradient_space, gradient_direction, custom_material, appearance, data, shader_data_2)
func with_shader_data_2(data: Vector4) -> MoldStyle: return MoldStyle.new(mode, color, secondary_color, emission_strength, color_mode, color_interpolation, gradient_space, gradient_direction, custom_material, appearance, shader_data, data)
func duplicate_style() -> MoldStyle: return MoldStyle.new(mode, color, secondary_color, emission_strength, color_mode, color_interpolation, gradient_space, gradient_direction, custom_material, appearance, shader_data, shader_data_2)


func validate_for_shape(shape: MoldShape) -> bool:
	if mode == BlendMode.CUSTOM and color_mode != ColorMode.SINGLE:
		push_error("Custom materials support Single color mode only.")
		return false
	var supported := color_mode == ColorMode.SINGLE or color_mode == ColorMode.DUAL_DIRECTIONAL or ((color_mode == ColorMode.DUAL_RADIAL or color_mode == ColorMode.DUAL_RADIAL_BOUNDS or color_mode == ColorMode.DUAL_ANGULAR) and not shape.is_line)
	if supported: return true
	push_error("This color mode is not supported by the supplied shape.")
	return false

func validate_for_polyline() -> bool:
	if color_mode == ColorMode.SINGLE or color_mode == ColorMode.DUAL_DIRECTIONAL: return true
	push_error("Polylines and curves support Single and DualDirectional colors.")
	return false

func with_appearance(value: MoldAppearanceSnapshot) -> MoldStyle:
	var result := duplicate_style()
	result.appearance=value
	return result
