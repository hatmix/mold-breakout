class_name MoldBatch
extends RefCounted

const TRANSFORM_FLOATS_PER_INSTANCE := 12
const PROPERTY_TEXELS_PER_INSTANCE := 7
const BOUNDS_BLOCK_SIZE := 32

var key := Vector4i.ZERO
var slots := PackedInt32Array()
var secondary_memberships := PackedByteArray()
var transform_buffer := PackedFloat32Array()
# Allocated only for dense full-transform rebuilds; position updates use the float buffer.
var _rebuild_rows := PackedVector4Array()
var property_texels := PackedVector4Array()
var shader_data := PackedVector4Array()
var shader_data_2 := PackedVector4Array()
var mesh: Mesh
var appearance: MoldAppearanceSnapshot
var mode: MoldStyle.BlendMode
var custom_material: ShaderMaterial
var render_state: MoldRenderState
var is_2d := false
var local_aa_quality := MoldWorldSettings.LocalAaQuality.HIGH
var coverage_output := false
var transform_pending := false
var property_pending := false
var transform_revision := 1
var property_revision := 1
var is_immediate := false
var immediate_count := 0
var immediate_bounds: Array[AABB] = []
var mesh_key
var owns_mesh := false
var retained_count := 0
# Bounds at zero translation; invalidated only by changes to the linear transform.
var relative_bounds: Array[AABB] = []
var bounds_valid := PackedByteArray()
var bounds_blocks: Array[AABB] = []
var bounds_dirty := PackedByteArray()
var full_bounds_rebuild := false


func configure(value_key: Vector4i, value_mesh: Mesh, value_mode: MoldStyle.BlendMode, value_custom_material: ShaderMaterial, state: MoldRenderState, value_is_2d: bool, value_local_aa_quality: MoldWorldSettings.LocalAaQuality, value_coverage_output := false, value_appearance: MoldAppearanceSnapshot = null) -> void:
	appearance = value_appearance
	key = value_key
	mesh = value_mesh
	mode = value_mode
	custom_material = value_custom_material
	render_state = state.duplicate_state()
	is_2d = value_is_2d
	local_aa_quality = value_local_aa_quality
	coverage_output = value_coverage_output


func configure_immediate(value_key: Vector4i, value_mesh_key, value_mesh: Mesh, value_mode: MoldStyle.BlendMode, value_custom_material: ShaderMaterial, state: MoldRenderState, value_is_2d: bool, value_local_aa_quality: MoldWorldSettings.LocalAaQuality, value_coverage_output := false, value_appearance: MoldAppearanceSnapshot = null) -> void:
	configure(value_key, value_mesh, value_mode, value_custom_material, state, value_is_2d, value_local_aa_quality, value_coverage_output, value_appearance)
	is_immediate = true
	mesh_key = value_mesh_key
	owns_mesh = true


func count() -> int:
	return immediate_count if is_immediate else retained_count


func add_item(slot: int, transform: Transform3D, primary_color: Color, secondary_color: Color, custom_data: Vector4, dash_data: Vector4, flags: Vector4, gradient_data: Vector4, shader_value: Vector4, lod_data := Vector4(1.0, 0.0, 0.0, 0.0), secondary_membership := false, shader_value_2 := Vector4.ZERO) -> int:
	var index := retained_count
	var required := index + 1
	if slots.size() < required:
		var capacity := _next_power_of_two(required)
		slots.resize(capacity)
		relative_bounds.resize(capacity)
		bounds_valid.resize(capacity)
		bounds_blocks.resize((capacity + BOUNDS_BLOCK_SIZE - 1) / BOUNDS_BLOCK_SIZE)
		bounds_dirty.resize(bounds_blocks.size())
		secondary_memberships.resize(capacity)
		transform_buffer.resize(capacity * TRANSFORM_FLOATS_PER_INSTANCE)
		property_texels.resize(capacity * PROPERTY_TEXELS_PER_INSTANCE)
		shader_data.resize(capacity)
		shader_data_2.resize(capacity)
	slots[index] = slot
	secondary_memberships[index] = int(secondary_membership)
	_store_transform(index, transform)
	_store_properties(index, primary_color, secondary_color, custom_data, dash_data, flags, gradient_data, lod_data)
	shader_data[index] = shader_value
	shader_data_2[index] = shader_value_2
	retained_count += 1
	_mark_all_dirty()
	return index


func add_immediate(bounds: AABB, transform: Transform3D, primary_color: Color, secondary_color: Color, custom_data: Vector4, dash_data: Vector4, flags: Vector4, gradient_data: Vector4, shader_value: Vector4, lod_data := Vector4(1.0, 0.0, 0.0, 0.0), shader_value_2 := Vector4.ZERO) -> int:
	assert(is_immediate, "Only immediate batches accept frame-local commands.")
	var index := immediate_count
	var required := index + 1
	if slots.size() < required:
		var capacity := _next_power_of_two(required)
		slots.resize(capacity)
		relative_bounds.resize(capacity)
		bounds_valid.resize(capacity)
		bounds_blocks.resize((capacity + BOUNDS_BLOCK_SIZE - 1) / BOUNDS_BLOCK_SIZE)
		bounds_dirty.resize(bounds_blocks.size())
		secondary_memberships.resize(capacity)
		transform_buffer.resize(capacity * TRANSFORM_FLOATS_PER_INSTANCE)
		property_texels.resize(capacity * PROPERTY_TEXELS_PER_INSTANCE)
		shader_data.resize(capacity)
		shader_data_2.resize(capacity)
		immediate_bounds.resize(capacity)
	slots[index] = -1
	immediate_bounds[index] = bounds
	_store_transform(index, transform)
	_store_properties(index, primary_color, secondary_color, custom_data, dash_data, flags, gradient_data, lod_data)
	shader_data[index] = shader_value
	shader_data_2[index] = shader_value_2
	immediate_count += 1
	_mark_all_dirty()
	return index


func clear_immediate() -> void:
	assert(is_immediate, "Only immediate batches can be cleared as a frame.")
	if immediate_count == 0: return
	immediate_count = 0
	_mark_all_dirty()


func custom_data_at(index: int) -> Vector4:
	return property_texels[index * PROPERTY_TEXELS_PER_INSTANCE + 2]


func remove_item(index: int) -> Vector2i:
	if index < 0 or index >= retained_count: return Vector2i(-1, 0)
	var swapped_slot := -1
	var swapped_secondary := 0
	var last := retained_count - 1
	if index != last:
		swapped_slot = slots[last]
		swapped_secondary = secondary_memberships[last]
		relative_bounds[index] = relative_bounds[last]
		bounds_valid[index] = bounds_valid[last]
		slots[index] = swapped_slot
		secondary_memberships[index] = swapped_secondary
		for component in TRANSFORM_FLOATS_PER_INSTANCE:
			transform_buffer[index * TRANSFORM_FLOATS_PER_INSTANCE + component] = transform_buffer[last * TRANSFORM_FLOATS_PER_INSTANCE + component]
		_copy_rows(property_texels, last * PROPERTY_TEXELS_PER_INSTANCE, index * PROPERTY_TEXELS_PER_INSTANCE, PROPERTY_TEXELS_PER_INSTANCE)
		shader_data[index] = shader_data[last]
		shader_data_2[index] = shader_data_2[last]
	retained_count = last
	_mark_all_dirty()
	return Vector2i(swapped_slot, swapped_secondary)


func write_position(index: int, origin: Vector3) -> void:
	if index < 0 or index >= count(): return
	store_position(index, origin)


# Internal bulk path: world has already validated the handle and membership.
func store_position(index: int, origin: Vector3) -> void:
	var offset := index * TRANSFORM_FLOATS_PER_INSTANCE
	transform_buffer[offset + 3] = origin.x
	transform_buffer[offset + 7] = origin.y
	transform_buffer[offset + 11] = origin.z
	bounds_dirty[index / BOUNDS_BLOCK_SIZE] = 1
	if not transform_pending:
		transform_revision += 1
		transform_pending = true


func write_transform(index: int, transform: Transform3D) -> void:
	if index < 0 or index >= count(): return
	_store_transform(index, transform)
	if not transform_pending:
		transform_revision += 1
		transform_pending = true


func rebuild_transforms(positions: PackedVector3Array, rotations: Array[Quaternion], local_scales: PackedVector3Array, shape_transforms: Array[Transform3D]) -> void:
	var count := retained_count
	bounds_valid.fill(0)
	bounds_dirty.fill(1)
	full_bounds_rebuild = true
	# Dense TRS writes benefit from three vector writes plus native conversion;
	# twelve interpreted scalar writes would penalize the full-transform API.
	_rebuild_rows.resize(slots.size() * 3)
	for index in count:
		var slot := slots[index]
		var transform := Transform3D(Basis(rotations[slot]).scaled_local(local_scales[slot]), positions[slot]) * shape_transforms[slot]
		var offset := index * 3
		_rebuild_rows[offset] = Vector4(transform.basis.x.x, transform.basis.y.x, transform.basis.z.x, transform.origin.x)
		_rebuild_rows[offset + 1] = Vector4(transform.basis.x.y, transform.basis.y.y, transform.basis.z.y, transform.origin.y)
		_rebuild_rows[offset + 2] = Vector4(transform.basis.x.z, transform.basis.y.z, transform.basis.z.z, transform.origin.z)
	transform_buffer = _rebuild_rows.to_byte_array().to_float32_array()
	if not transform_pending:
		transform_revision += 1
		transform_pending = true


func write_color(index: int, color: Color, secondary: bool) -> void:
	if index < 0 or index >= count(): return
	property_texels[index * PROPERTY_TEXELS_PER_INSTANCE + int(secondary)] = Vector4(color.r, color.g, color.b, color.a)
	if not property_pending:
		property_revision += 1
		property_pending = true


func write_properties(index: int, primary_color: Color, secondary_color: Color, custom_data: Vector4, dash_data: Vector4, flags: Vector4, gradient_data: Vector4, shader_value: Vector4, lod_data := Vector4(1.0, 0.0, 0.0, 0.0), shader_value_2 := Vector4.ZERO) -> void:
	if index < 0 or index >= count(): return
	_store_properties(index, primary_color, secondary_color, custom_data, dash_data, flags, gradient_data, lod_data)
	shader_data[index] = shader_value
	shader_data_2[index] = shader_value_2
	if not property_pending:
		property_revision += 1
		property_pending = true


func transform_at(index: int) -> Transform3D:
	var offset := index * TRANSFORM_FLOATS_PER_INSTANCE
	var basis := Basis(
		Vector3(transform_buffer[offset], transform_buffer[offset + 4], transform_buffer[offset + 8]),
		Vector3(transform_buffer[offset + 1], transform_buffer[offset + 5], transform_buffer[offset + 9]),
		Vector3(transform_buffer[offset + 2], transform_buffer[offset + 6], transform_buffer[offset + 10]),
	)
	return Transform3D(basis, Vector3(transform_buffer[offset + 3], transform_buffer[offset + 7], transform_buffer[offset + 11]))


func _store_transform(index: int, transform: Transform3D) -> void:
	bounds_valid[index] = 0
	bounds_dirty[index / BOUNDS_BLOCK_SIZE] = 1
	var offset := index * TRANSFORM_FLOATS_PER_INSTANCE
	transform_buffer[offset + 0] = transform.basis.x.x
	transform_buffer[offset + 1] = transform.basis.y.x
	transform_buffer[offset + 2] = transform.basis.z.x
	transform_buffer[offset + 3] = transform.origin.x
	transform_buffer[offset + 4] = transform.basis.x.y
	transform_buffer[offset + 5] = transform.basis.y.y
	transform_buffer[offset + 6] = transform.basis.z.y
	transform_buffer[offset + 7] = transform.origin.y
	transform_buffer[offset + 8] = transform.basis.x.z
	transform_buffer[offset + 9] = transform.basis.y.z
	transform_buffer[offset + 10] = transform.basis.z.z
	transform_buffer[offset + 11] = transform.origin.z


func _store_properties(index: int, primary_color: Color, secondary_color: Color, custom_data: Vector4, dash_data: Vector4, flags: Vector4, gradient_data: Vector4, lod_data: Vector4) -> void:
	var offset := index * PROPERTY_TEXELS_PER_INSTANCE
	property_texels[offset] = Vector4(primary_color.r, primary_color.g, primary_color.b, primary_color.a)
	property_texels[offset + 1] = Vector4(secondary_color.r, secondary_color.g, secondary_color.b, secondary_color.a)
	property_texels[offset + 2] = custom_data
	property_texels[offset + 3] = dash_data
	property_texels[offset + 4] = flags
	property_texels[offset + 5] = gradient_data
	property_texels[offset + 6] = lod_data


func acknowledge_changes() -> void:
	transform_pending = false
	property_pending = false


func _mark_all_dirty() -> void:
	bounds_dirty.fill(1)
	if not transform_pending:
		transform_revision += 1
		transform_pending = true
	if not property_pending:
		property_revision += 1
		property_pending = true


static func _copy_rows(values: PackedVector4Array, source: int, destination: int, count: int) -> void:
	for offset in count:
		values[destination + offset] = values[source + offset]


static func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value: result <<= 1
	return result
