class_name MoldPolygonRenderer
extends RefCounted

## World-owned retained polygon. Auto fetches vertices on the GPU; CPU bakes a mesh.
## update_points preserves connectivity. The caller must keep it valid.
const TEXTURE_WIDTH := 1024
const MAX_POINTS := TEXTURE_WIDTH * 4096 / 2
var _owner: WeakRef
var _instance: MoldRenderInstance
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _triangles := PackedInt32Array()
var _clockwise_triangles := PackedInt32Array()
var _point_bytes := PackedByteArray()
var _mesh_vertex_bytes := PackedByteArray()
var _mesh_attribute_bytes := PackedByteArray()
var _attribute_stride := 0
var _color_offset := 0
var _reference_offset := 0
var _point_image: Image
var _parameters: Dictionary = {}
var _uniform_color := false
var _style_dirty := true
var _bounds_dirty := true
var _points_dirty := true
var _colors_dirty := true
var _synced_aa := -1
var _synced_viewport := Vector2(-1, -1)
var _synced_msaa := false
var _bounds := AABB()
var _transform := Transform3D.IDENTITY
var _visible := true
var _synced_layers := -1
var _synced_priority := -129
var _points: ImageTexture
var _material: ShaderMaterial
var _style := MoldStyle.transparent(Color.WHITE)
var _state := MoldRenderState.new()
var _disposed := false
var _backend := MoldPolygonBackend.Mode.AUTO
var _gpu := false
## Opt-in CPU timing of the most recent material synchronization pass.
var profile_synchronization := false
var last_synchronization_milliseconds := 0.0
## Cumulative point-texture submissions/payload bytes, excluding mesh uploads.
var point_upload_count := 0
var point_upload_bytes := 0
var local_aa_quality := MoldWorldSettings.LocalAaQuality.HIGH
var backend: MoldPolygonBackend.Mode:
	get: return _backend
	set(value):
		assert(value in [MoldPolygonBackend.Mode.AUTO, MoldPolygonBackend.Mode.CPU])
		if _backend == value: return
		_backend = value
		if not _vertices.is_empty(): _rebuild_mesh()
var is_valid: bool:
	get: return not _disposed and _owner != null and is_instance_valid(_owner.get_ref()) and _owner.get_ref()._is_available()
var is_using_gpu_backend: bool:
	get: return _gpu and is_valid
var generated_vertex_count: int:
	get: return _triangles.size()
var local_bounds: AABB:
	get: return _bounds
var is_visible: bool:
	get: return is_valid and _instance.visible

static func is_gpu_supported() -> bool:
	return DisplayServer.get_name() != "headless"

func _init(owner: Node3D, aa := MoldWorldSettings.LocalAaQuality.HIGH) -> void:
	_owner = weakref(owner)
	local_aa_quality = aa
	_instance = MoldRenderInstance.new(owner)
	configure(_style)

func set_polygon(polygon: MoldPolygon) -> void:
	assert(is_valid and polygon != null)
	assert(polygon.count <= MAX_POINTS, "Polygon exceeds point texture capacity.")
	# Keep renderer-owned points so later caller writes cannot change a pending rebuild.
	_vertices = polygon._vertices.duplicate()
	_colors = polygon._colors.duplicate()
	_triangles = polygon._triangles.duplicate()
	_update_uniform_color()
	_upload_points(true)
	_rebuild_mesh()
	recalculate_bounds()

func set_data(vertices: PackedVector3Array, colors := PackedColorArray(), triangles := PackedInt32Array()) -> void:
	set_polygon(MoldPolygon.new(vertices, colors, triangles))

func update_points(vertices: PackedVector3Array, colors := PackedColorArray(), recalculate := true) -> void:
	assert(is_valid and not _vertices.is_empty() and vertices.size() == _vertices.size(), "Point count changed; call set_data.")
	assert(colors.is_empty() or colors.size() == _vertices.size(), "One color per vertex is required.")
	for i in _vertices.size(): _vertices[i] = vertices[i]
	if not colors.is_empty():
		for i in _colors.size(): _colors[i] = colors[i]
		_update_uniform_color()
	_upload_points(not colors.is_empty())
	_update_mesh(not colors.is_empty())
	if recalculate: recalculate_bounds()

func _update_uniform_color() -> void:
	_colors_dirty = true
	_uniform_color = true
	for i in range(1, _colors.size()):
		if _colors[i] != _colors[0]:
			_uniform_color = false
			break

func _upload_points(colors_changed := false) -> void:
	var height := maxi(1, ceili(float(_vertices.size() * 2) / TEXTURE_WIDTH))
	var width := mini(TEXTURE_WIDTH, _vertices.size() * 2)
	var resized := not _point_image or _point_image.get_width() != width or _point_image.get_height() != height
	_point_bytes.resize(width * height * 16)
	for i in _vertices.size():
		var p := _vertices[i]
		var o := i * 32
		_point_bytes.encode_float(o, p.x); _point_bytes.encode_float(o+4, p.y); _point_bytes.encode_float(o+8, p.z)
		if colors_changed or resized:
			var c := _colors[i]
			_point_bytes.encode_float(o+16, c.r); _point_bytes.encode_float(o+20, c.g)
			_point_bytes.encode_float(o+24, c.b); _point_bytes.encode_float(o+28, c.a)
	point_upload_count += 1
	point_upload_bytes += _point_bytes.size()
	if resized:
		_point_image = Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, _point_bytes)
		_points = ImageTexture.create_from_image(_point_image)
		_points_dirty = true
	else:
		_point_image.set_data(width, height, false, Image.FORMAT_RGBAF, _point_bytes)
		_points.update(_point_image)

func _rebuild_mesh() -> void:
	_points_dirty = true
	_gpu = _backend == MoldPolygonBackend.Mode.AUTO and is_gpu_supported()
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var references := PackedVector2Array()
	positions.resize(_triangles.size()); colors.resize(_triangles.size()); references.resize(_triangles.size())
	_clockwise_triangles.resize(_triangles.size())
	# Godot front faces are clockwise. Geometry2D returns counterclockwise triangles.
	for t in range(0, _triangles.size(), 3):
		var ia := _triangles[t]
		var ib := _triangles[t+1]
		var ic := _triangles[t+2]
		var a := _vertices[ia]
		var b := _vertices[ib]
		var c := _vertices[ic]
		if Vector2(b.x-a.x,b.y-a.y).cross(Vector2(c.x-a.x,c.y-a.y)) > 0:
			var swap := ib
			ib = ic; ic = swap
		for k in 3:
			var index := ia if k == 0 else (ib if k == 1 else ic)
			_clockwise_triangles[t+k] = index
			positions[t+k] = Vector3.ZERO if _gpu else _vertices[index]
			colors[t+k] = _colors[index]
			references[t+k] = Vector2(index, 0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = references
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_instance.mesh = mesh
	var format := mesh.surface_get_format(0)
	_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, positions.size())
	_color_offset = RenderingServer.mesh_surface_get_format_offset(format, positions.size(), Mesh.ARRAY_COLOR)
	_reference_offset = RenderingServer.mesh_surface_get_format_offset(format, positions.size(), Mesh.ARRAY_TEX_UV2)
	_mesh_vertex_bytes.resize(positions.size()*12)
	_mesh_attribute_bytes.resize(positions.size()*_attribute_stride)

func _update_mesh(colors_changed := false) -> void:
	var winding_changed := false
	for t in range(0, _triangles.size(), 3):
		var a := _triangles[t]
		var b := _triangles[t+1]
		var c := _triangles[t+2]
		var ab := _vertices[b]-_vertices[a]
		var ac := _vertices[c]-_vertices[a]
		if ab.x*ac.y-ab.y*ac.x > 0:
			var swap := b
			b = c; c = swap
		winding_changed = winding_changed or _clockwise_triangles[t+1] != b or _clockwise_triangles[t+2] != c
		_clockwise_triangles[t] = a; _clockwise_triangles[t+1] = b; _clockwise_triangles[t+2] = c
	# GPU fetches positions/colors from the texture; only changed references need upload.
	var attributes_changed := winding_changed or (not _gpu and colors_changed)
	if _gpu and not attributes_changed: return
	for vertex in _clockwise_triangles.size():
		var i := _clockwise_triangles[vertex]
		if not _gpu:
			var p := _vertices[i]
			var v := vertex*12
			_mesh_vertex_bytes.encode_float(v,p.x); _mesh_vertex_bytes.encode_float(v+4,p.y); _mesh_vertex_bytes.encode_float(v+8,p.z)
		if not attributes_changed: continue
		var color := _colors[i]
		var o := vertex*_attribute_stride
		_mesh_attribute_bytes[o+_color_offset] = int(clampf(color.r*255,0,255))
		_mesh_attribute_bytes[o+_color_offset+1] = int(clampf(color.g*255,0,255))
		_mesh_attribute_bytes[o+_color_offset+2] = int(clampf(color.b*255,0,255))
		_mesh_attribute_bytes[o+_color_offset+3] = int(clampf(color.a*255,0,255))
		_mesh_attribute_bytes.encode_float(o+_reference_offset,i)
		_mesh_attribute_bytes.encode_float(o+_reference_offset+4,0)
	if not _gpu: _instance.mesh.surface_update_vertex_region(0,0,_mesh_vertex_bytes)
	if attributes_changed: _instance.mesh.surface_update_attribute_region(0,0,_mesh_attribute_bytes)

static func shader_source(mode: int, state: MoldRenderState) -> String:
	return MoldShader.source(mode, state, MoldShader.Backend.POLYGON, mode == MoldStyle.BlendMode.OPAQUE)


func configure(style: MoldStyle, render_state: MoldRenderState = null) -> void:
	assert(is_valid)
	assert(style.mode != MoldStyle.BlendMode.CUSTOM, "Polygon custom materials require a polygon coverage contract and are not supported yet.")
	assert(style.color_mode in [MoldStyle.ColorMode.SINGLE, MoldStyle.ColorMode.DUAL_DIRECTIONAL])
	_style_dirty = true
	_style.copy_from(style)
	_state.copy_from(render_state)
	var shader := MoldShader.get_shader(_style.mode, _state, MoldShader.Backend.POLYGON, _style.mode == MoldStyle.BlendMode.OPAQUE, _style.appearance)
	if not _material:
		_material = ShaderMaterial.new()
		_instance.material_override = _material
	if _material.shader != shader:
		_material.shader = shader
		_parameters.clear()
		_style_dirty = true; _bounds_dirty = true; _points_dirty = true; _colors_dirty = true
		_synced_aa = -1; _synced_viewport = Vector2(-1, -1)
	if _style.appearance: _style.appearance.apply(_material)

func set_style(style: MoldStyle) -> void:
	configure(style, _state)
func set_color(color: Color) -> void:
	assert(is_valid)
	if _style.color != color:
		_style.color = color
		_style_dirty = true
func set_render_state(state: MoldRenderState) -> void:
	configure(_style, state)
func set_transform(value: Transform3D) -> void:
	assert(is_valid)
	if _transform != value:
		_transform = value
		_instance.transform = value
func set_visible(value: bool) -> void:
	assert(is_valid)
	if _visible != value:
		_visible = value
		_instance.visible = value
func recalculate_bounds() -> void:
	assert(is_valid and not _vertices.is_empty())
	var bounds := AABB(_vertices[0], Vector3.ZERO)
	for p in _vertices: bounds = bounds.expand(p)
	set_local_bounds(bounds)
func set_local_bounds(value: AABB) -> void:
	assert(is_valid)
	value = value.grow(0.001)
	if _bounds != value:
		_bounds_dirty = true
		_bounds = value
		_instance.custom_aabb = value

func _set_parameter(name: StringName, value: Variant) -> void:
	if not _parameters.has(name) or _parameters[name] != value:
		_material.set_shader_parameter(name, value)
		_parameters[name] = value

func _sync(viewport_size := Vector2(-1, -1), msaa := false) -> void:
	if not profile_synchronization:
		_sync_core(viewport_size, msaa)
		return
	var start := Time.get_ticks_usec()
	_sync_core(viewport_size, msaa)
	last_synchronization_milliseconds = (Time.get_ticks_usec() - start) / 1000.0

func _sync_core(viewport_size: Vector2, msaa: bool) -> void:
	if not is_valid or _vertices.is_empty(): return
	if _gpu != (_backend == MoldPolygonBackend.Mode.AUTO and is_gpu_supported()): _rebuild_mesh()
	if _synced_layers != _state.render_layer_mask:
		_synced_layers = _state.render_layer_mask
		_instance.layers = _synced_layers
	var priority := clampi(_state.sorting_order,-128,127)
	if _synced_priority != priority:
		_synced_priority = priority
		_material.render_priority = priority
	if _colors_dirty:
		_set_parameter(&"mold_polygon_uniform_color", _uniform_color)
		var color := _colors[0]
		_set_parameter(&"mold_polygon_constant_color", Vector4(color.r, color.g, color.b, color.a))
		_colors_dirty = false
	if _points_dirty:
		_set_parameter(&"mold_polygon_points", _points)
		_set_parameter(&"mold_polygon_count", _vertices.size())
		_set_parameter(&"mold_polygon_gpu", _gpu)
		_points_dirty = false
	if _bounds_dirty:
		var b := _bounds
		_set_parameter(&"mold_polygon_bounds", Vector4(b.position.x,b.position.y,b.size.x,b.size.y))
		_bounds_dirty = false
	if _style_dirty:
		_set_parameter(&"primary_color", MoldMultiMeshRenderer.pack_color_vector(_style.color, _style.color_mode, _style.color_interpolation))
		_set_parameter(&"secondary_color", MoldMultiMeshRenderer.pack_color_vector(_style.secondary_color, _style.color_mode, _style.color_interpolation))
		var d := _style.gradient_direction
		_set_parameter(&"gradient_data", Vector4(d.x,d.y,d.z,_style.color_mode+8*_style.color_interpolation+16*_style.gradient_space))
		_set_parameter(&"emission_strength", _style.emission_strength)
	if _style_dirty or _synced_aa != local_aa_quality:
		_set_parameter(&"mold_flags", Vector4(_style.emission_strength,0,0,0 if local_aa_quality == 0 else (1 if local_aa_quality == 1 else 33)))
		_set_parameter(&"mold_polygon_aa_quality", local_aa_quality)
		_synced_aa = local_aa_quality
	_style_dirty = false
	if viewport_size.x < 0:
		var viewport: Viewport = _owner.get_ref().get_viewport()
		viewport_size = viewport.get_visible_rect().size
		msaa = viewport.msaa_3d != Viewport.MSAA_DISABLED
	if _synced_viewport != viewport_size or _synced_msaa != msaa:
		_set_parameter(&"mold_viewport_size", viewport_size)
		_set_parameter(&"mold_msaa_enabled", msaa)
		_synced_viewport = viewport_size; _synced_msaa = msaa
	if _style.appearance or _instance._appearance_oit_active: _instance.sync_oit(_style,_state,local_aa_quality,"polygon")

func release() -> void:
	dispose()
func dispose() -> void:
	if _disposed: return
	var owner: Node = _owner.get_ref()
	if is_instance_valid(owner): owner.release_polygon_renderer(self)
	else: _dispose_from_world()
func _dispose_from_world() -> void:
	if _disposed: return
	_disposed = true
	_instance.mesh = null
	_instance.material_override = null
	_instance.dispose()
	_points = null
	_material = null
	_vertices.clear(); _colors.clear(); _triangles.clear(); _clockwise_triangles.clear(); _point_bytes.clear()
	_point_image = null
	_parameters.clear()
