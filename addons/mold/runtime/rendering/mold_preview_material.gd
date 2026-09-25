class_name MoldPreviewMaterial
extends RefCounted

# Materials belong to their preview; immutable shaders come from MoldShader.

static func create_custom_shape(source: ShaderMaterial, value_shape: MoldShape, color: Color, shader_data: Vector4, state: MoldRenderState, shader_data_2: Vector4) -> ShaderMaterial:
	var layout := MoldShapeLayout.resolve(value_shape)
	var custom := source.duplicate() as ShaderMaterial
	custom.render_priority = clampi(state.sorting_order, -128, 127)
	var custom_deformation := MoldShapeLayout.deformation_kind(value_shape)
	var custom_flags := 1 \
		+ 2 * int(value_shape.billboard_mode != MoldShape.BillboardMode.DISABLED) \
		+ 4 * int(value_shape.is_line) \
		+ 16 * int(value_shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA_Y)
	custom.set_shader_parameter(&"mold_instance_data", MoldMultiMeshRenderer.create_single_instance_texture(
		color, layout.custom_data, value_shape.dash.to_gpu_data(value_shape.dash_path_length()),
		Vector4(0.0, float(value_shape.is_2d), custom_deformation, float(custom_flags)),
		Vector4(0.0, 1.0, 0.0, float(32 * value_shape.kind)),
		_angular_lod_data(value_shape)))
	custom.set_shader_parameter(&"mold_custom_instance_data",
		MoldMultiMeshRenderer.create_single_custom_data_texture(shader_data))
	custom.set_shader_parameter(&"mold_custom_instance_data_2",
		MoldMultiMeshRenderer.create_single_custom_data_texture(shader_data_2))
	return custom

static func update_shape(material: ShaderMaterial, value_shape: MoldShape, value_style: MoldStyle, state: MoldRenderState) -> ShaderMaterial:
	var layout := MoldShapeLayout.resolve(value_shape)
	var appearance := MoldAppearanceSnapshot.for_geometry(value_style.appearance,value_shape)
	if not is_instance_valid(material): material = ShaderMaterial.new()
	var shader := MoldShader.get_shader(value_style.mode, state, MoldShader.Backend.PREVIEW, value_shape.is_2d or value_shape.is_line, appearance)
	if material.shader != shader: material.shader = shader
	if appearance: appearance.apply(material)
	material.render_priority = clampi(state.sorting_order, -128, 127)
	# Oklab a/b channels can be negative. Raw vectors prevent Godot from
	# interpreting the packed data as a display color and clamping its chroma.
	material.set_shader_parameter(&"primary_color", MoldMultiMeshRenderer.pack_color_vector(value_style.color, value_style.color_mode, value_style.color_interpolation))
	material.set_shader_parameter(&"secondary_color", MoldMultiMeshRenderer.pack_color_vector(value_style.secondary_color, value_style.color_mode, value_style.color_interpolation))
	material.set_shader_parameter(&"emission_strength", value_style.emission_strength)
	material.set_shader_parameter(&"shape_data", layout.custom_data)
	material.set_shader_parameter(&"dash_data", value_shape.dash.to_gpu_data(value_shape.dash_path_length()))
	var angular_lod := _angular_lod_data(value_shape)
	material.set_shader_parameter(&"angular_data", Vector2(angular_lod.z, angular_lod.w))
	var deformation := MoldShapeLayout.deformation_kind(value_shape)
	var packed_flags := 33 \
		+ 2 * int(value_shape.billboard_mode != MoldShape.BillboardMode.DISABLED) \
		+ 4 * int(value_shape.is_line) \
		+ 16 * int(value_shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA_Y)
	material.set_shader_parameter(&"mold_flags", Vector4(value_style.emission_strength, float(value_shape.is_2d), deformation, float(packed_flags)))
	var direction := value_style.gradient_direction
	if value_style.color_mode == MoldStyle.ColorMode.DUAL_RADIAL and value_shape.kind in [MoldShape.Kind.RECTANGLE, MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.REGULAR_POLYGON, MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.ELLIPSE_RIM]:
		direction = layout.scale
	if not value_shape.is_2d and value_style.color_mode in [MoldStyle.ColorMode.DUAL_RADIAL, MoldStyle.ColorMode.DUAL_RADIAL_BOUNDS]:
		direction = layout.scale
	var packed := value_style.color_mode + 8 * value_style.color_interpolation + 16 * value_style.gradient_space + 32 * value_shape.kind
	material.set_shader_parameter(&"gradient_data", Vector4(direction.x, direction.y, direction.z, float(packed)))
	return material

static func _angular_lod_data(value_shape: MoldShape) -> Vector4:
	if not value_shape.is_line and value_shape.kind in [MoldShape.Kind.RECTANGLE,
			MoldShape.Kind.RECTANGLE_RIM, MoldShape.Kind.REGULAR_POLYGON,
			MoldShape.Kind.REGULAR_POLYGON_RIM, MoldShape.Kind.ELLIPSE_RIM]:
		return Vector4(1.0, 0.0, value_shape.start_radians, value_shape.span_radians)
	return Vector4(1.0, 0.0, 0.0, TAU)


static func create_custom_polyline(source: ShaderMaterial, color: Color, shader_data: Vector4, state: MoldRenderState, shader_data_2: Vector4) -> ShaderMaterial:
	var custom := source.duplicate() as ShaderMaterial
	custom.render_priority = clampi(state.sorting_order, -128, 127)
	custom.set_shader_parameter(&"mold_instance_data", MoldMultiMeshRenderer.create_single_instance_texture(
		color, Vector4.ZERO, Vector4.ZERO,
		Vector4(0.0, 0.0, 0.0, 13.0), Vector4(0.0, 1.0, 0.0, 0.0)))
	custom.set_shader_parameter(&"mold_custom_instance_data",
		MoldMultiMeshRenderer.create_single_custom_data_texture(shader_data))
	custom.set_shader_parameter(&"mold_custom_instance_data_2",
		MoldMultiMeshRenderer.create_single_custom_data_texture(shader_data_2))
	return custom

static func update_polyline(material: ShaderMaterial, value_polyline: MoldPolyline, value_style: MoldStyle, state: MoldRenderState) -> ShaderMaterial:
	var appearance := value_style.appearance.resolve(value_polyline.length) if value_style.appearance else null
	if not is_instance_valid(material): material = ShaderMaterial.new()
	var shader := MoldShader.get_shader(value_style.mode, state, MoldShader.Backend.PREVIEW, true, appearance)
	if material.shader != shader: material.shader = shader
	if appearance: appearance.apply(material)
	material.render_priority = clampi(state.sorting_order, -128, 127)
	material.set_shader_parameter(&"primary_color", MoldMultiMeshRenderer.pack_color_vector(
		value_style.color, value_style.color_mode, value_style.color_interpolation))
	material.set_shader_parameter(&"secondary_color", MoldMultiMeshRenderer.pack_color_vector(
		value_style.secondary_color, value_style.color_mode, value_style.color_interpolation))
	material.set_shader_parameter(&"emission_strength", value_style.emission_strength)
	material.set_shader_parameter(&"shape_data", Vector4.ZERO)
	material.set_shader_parameter(&"dash_data", Vector4.ZERO)
	material.set_shader_parameter(&"mold_flags", Vector4(value_style.emission_strength, 0.0, 0.0, 45.0))
	var direction := value_style.gradient_direction
	var packed := value_style.color_mode + 8 * value_style.color_interpolation + 16 * value_style.gradient_space
	material.set_shader_parameter(&"gradient_data", Vector4(direction.x, direction.y, direction.z, float(packed)))
	return material
