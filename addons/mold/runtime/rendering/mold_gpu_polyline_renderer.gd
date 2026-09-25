class_name MoldGpuPolylineRenderer
extends RefCounted

var _reveal := 1.0
var _parameters: Dictionary = {}
var _instance_parameters: Dictionary = {}
var _bounds_basis := Basis.IDENTITY
var _bounds_value := AABB()
var _bounds_geometry := -1

## World-owned dynamic XY stroke stream with separate topology and point updates.
## Points use eight packed floats: x, y, z, absolute thickness, r, g, b, a.
## Packed arrays avoid allocating one GDScript object per animated point.
enum BlendMode { ALPHA, ADDITIVE }
const MATERIAL_COMPATIBILITY_TAG := "MoldGpuPolyline"
const TEXTURE_WIDTH := 1024
const MAX_TEXELS := TEXTURE_WIDTH * 4096
var _owner: WeakRef
var _instance: MoldRenderInstance
var _material := ShaderMaterial.new()
var _custom_material: ShaderMaterial
var _point_image: Image
var _point_texture: ImageTexture
var _segment_texture: ImageTexture
var _segment_image: Image
var _segment_bytes := PackedByteArray()
var render_point_count: int:
	get: return _points.size()/8
var _points := PackedFloat32Array()
var _paths: Array[MoldGpuPolylineRange] = []
var _style := MoldStyle.additive(Color.WHITE)
var _state := MoldRenderState.new()
var _default_state := MoldRenderState.new()
var _disposed := false
var _material_dirty := true
var _visible := true
var _transform := Transform3D.IDENTITY
var _bounds := AABB()
var _manual_bounds := false
var _vertices_per_segment := 12
var _mesh_vertex_count := 0
var _segment_count := 0
var _join := MoldPolyline.Join.MITER
var _cap := MoldPolyline.Cap.BUTT
var _miter_limit := 4.0
var local_aa_quality := MoldWorldSettings.LocalAaQuality.HIGH
var is_valid: bool:
	get: return not _disposed and _owner != null and is_instance_valid(_owner.get_ref()) and _owner.get_ref()._is_available()
var point_count: int:
	get: return _points.size() / 8
var path_count: int:
	get: return _paths.size()
var segment_count: int:
	get: return _segment_count
var generated_vertex_count: int:
	get: return _segment_count * _vertices_per_segment
var local_bounds: AABB:
	get: return _bounds
var tint: Color:
	get: return _style.color
	set(value): _style.color = value
var join: int:
	get: return _join
	set(value):
		assert(value >= 0 and value <= MoldPolyline.Join.ROUND)
		_join = value
		_update_vertex_layout()
		_refresh_bounds()
var cap: int:
	get: return _cap
	set(value):
		assert(value >= 0 and value <= MoldPolyline.Cap.ROUND)
		_cap = value
		_update_vertex_layout()
		_refresh_bounds()
var miter_limit: float:
	get: return _miter_limit
	set(value):
		assert(is_finite(value) and value >= 1.0)
		_miter_limit = value
		_refresh_bounds()
var blend_mode: BlendMode:
	get: return BlendMode.ADDITIVE if _style.mode == MoldStyle.BlendMode.ADDITIVE else BlendMode.ALPHA
	set(value): configure(MoldStyle.additive(tint) if value == BlendMode.ADDITIVE else MoldStyle.transparent(tint), _state)

static func is_supported() -> bool:
	return DisplayServer.get_name() != "headless"

func _init(owner: Node3D, aa := MoldWorldSettings.LocalAaQuality.HIGH) -> void:
	_owner = weakref(owner)
	local_aa_quality = aa
	_instance = MoldRenderInstance.new(owner)

static func is_material_compatible(material: ShaderMaterial) -> bool:
	return is_instance_valid(material) and is_instance_valid(material.shader) and bool(material.get_meta(MATERIAL_COMPATIBILITY_TAG, false))

func set_material(material: ShaderMaterial) -> void:
	assert(is_valid)
	assert(material == null or is_material_compatible(material), "GPU material must opt into the MoldGpuPolyline contract.")
	if _custom_material == material: return
	_custom_material = material
	_material_dirty = true

func configure(style: MoldStyle, render_state: MoldRenderState = null) -> void:
	assert(is_valid)
	assert(style.color_mode in [MoldStyle.ColorMode.SINGLE, MoldStyle.ColorMode.DUAL_DIRECTIONAL])
	var state := render_state if render_state else _default_state
	_material_dirty = _material_dirty or (_style.appearance.key if _style.appearance else "") != (style.appearance.key if style.appearance else "") or _style.mode != style.mode or not _state.equals(state)
	_style.copy_from(style)
	_state.copy_from(state)

func set_transform(value: Transform3D) -> void:
	assert(is_valid)
	_transform = value

func set_reveal(value: float) -> void:
	if not is_valid or not is_finite(value): push_error("Reveal requires a valid renderer and finite fraction."); return
	_reveal=clampf(value,0.0,1.0)

func set_visible(value: bool) -> void:
	assert(is_valid)
	_visible = value

var _geometry := MoldPolyline.Geometry.FLAT_2D
var geometry: int:
	get: return _geometry
	set(value):
		assert(is_valid)
		assert(value in [MoldPolyline.Geometry.FLAT_2D, MoldPolyline.Geometry.BILLBOARD])
		if _geometry == value: return
		_geometry = value
		if _segment_count > 0: recalculate_distances()
		else: _update_vertex_layout()
		_refresh_bounds()

var _dash_source_id := 0
func set_polyline(polyline: MoldPolyline) -> void:
	if _dash_source_id!=0 and _dash_source_id==polyline._dash_source_id and geometry==polyline.geometry and _join==polyline.join and _cap==polyline.cap and _miter_limit==polyline.miter_limit:
		set_dash(polyline.dash)
		return
	_dash=polyline.dash
	var same_geometry := geometry == polyline.geometry
	_geometry = polyline.geometry
	assert(is_valid)
	var source_points := polyline._render_points
	var points := PackedFloat32Array()
	points.resize(source_points.size()*8)
	for i in source_points.size():
		var p := source_points[i]
		var o := i*8
		points[o] = p.position.x; points[o+1] = p.position.y; points[o+2] = p.position.z; points[o+3] = p.thickness*polyline.thickness
		points[o+4] = p.color.r; points[o+5] = p.color.g; points[o+6] = p.color.b; points[o+7] = p.color.a
	_join = polyline.join; _cap = polyline.cap; _miter_limit = polyline.miter_limit
	if same_geometry and _paths.size() == 1 and _paths[0].start_index == 0 and _paths[0].point_count == points.size()/8 and _paths[0].closed == polyline.closed:
		# Recompute the dash layout only after replacing the old distance metrics.
		update_points(points)
		recalculate_distances()
	else:
		set_data(points, [MoldGpuPolylineRange.new(0, points.size()/8, polyline.closed)])

	_dash_source_id=polyline._dash_source_id

func set_data(points: PackedFloat32Array, paths: Array[MoldGpuPolylineRange]) -> void:
	_dash_source_id=0
	assert(is_valid)
	assert(points.size()%8 == 0)
	for i in points.size(): assert(is_finite(points[i]), "GPU points must be finite.")
	for i in points.size()/8: assert(points[i*8+3] >= 0.0, "Point thickness must be nonnegative.")
	var count := 0
	for path in paths:
		assert(path.start_index >= 0 and path.point_count >= (3 if path.closed else 2) and path.start_index <= points.size()/8-path.point_count, "Invalid GPU path range.")
		count += path.point_count if path.closed else path.point_count-1
	assert(points.size()/4 <= MAX_TEXELS and count*3 <= MAX_TEXELS, "Split large GPU streams into multiple streams.")
	_segment_bytes.resize(_texture_float_count(count,3)*4)
	var write := 0
	for path in paths:
		var end := path.start_index+path.point_count
		var n := path.point_count if path.closed else path.point_count-1
		var distance := 0.0
		var first_segment := write
		for s in n:
			var a := path.start_index+s
			var b := path.start_index if a+1 == end else a+1
			var length := Vector3(points[b*8]-points[a*8],points[b*8+1]-points[a*8+1],points[b*8+2]-points[a*8+2] if geometry == MoldPolyline.Geometry.BILLBOARD else 0.0).length()
			var o := write*12
			write += 1
			_segment_bytes.encode_float((o)*4,(end-1 if path.closed else a) if s == 0 else a-1)
			_segment_bytes.encode_float((o+1)*4,a); _segment_bytes.encode_float((o+2)*4,b)
			_segment_bytes.encode_float((o+3)*4,(path.start_index if path.closed else b) if b+1 == end else b+1)
			_segment_bytes.encode_float((o+4)*4,0 if path.closed else (1 if s == 0 else 0)+(2 if s == n-1 else 0))
			_segment_bytes.encode_float((o+5)*4,distance); distance += length; _segment_bytes.encode_float((o+6)*4,distance)
		for s in range(first_segment,write):
			var prev := (write-1 if path.closed else s) if s==first_segment else s-1
			var following := (first_segment if path.closed else s) if s==write-1 else s+1
			_segment_bytes.encode_float((s*12+7)*4,maxf(distance,0.00001))
			_segment_bytes.encode_float((s*12+8)*4,_segment_bytes.decode_float((prev*12+6)*4)-_segment_bytes.decode_float((prev*12+5)*4))
			_segment_bytes.encode_float((s*12+9)*4,_segment_bytes.decode_float((following*12+6)*4)-_segment_bytes.decode_float((following*12+5)*4))
			_segment_bytes.encode_float((s*12+10)*4,1.0 if path.closed else 0.0)
	_points = points
	_copy_ranges(paths,_paths)
	_segment_count = count
	var height := _segment_bytes.size()/(TEXTURE_WIDTH*16)
	if not _segment_image or _segment_image.get_height() != height:
		_segment_image=Image.create_from_data(TEXTURE_WIDTH,height,false,Image.FORMAT_RGBAF,_segment_bytes)
		_segment_texture=ImageTexture.create_from_image(_segment_image)
	else:
		_segment_image.set_data(TEXTURE_WIDTH,height,false,Image.FORMAT_RGBAF,_segment_bytes)
		_segment_texture.update(_segment_image)
	_manual_bounds = false
	_upload_points()
	recalculate_bounds()
	_rebuild_mesh()

## Distance metrics retain SetData's rest lengths. Reuses texture dimensions.
func update_points(points: PackedFloat32Array, recalculate := true) -> void:
	_dash_source_id=0
	assert(is_valid)
	assert(points.size() == _points.size(), "Point count changed; call set_data.")
	_points = points
	_upload_points()
	if recalculate: recalculate_bounds()

func copy_points() -> PackedFloat32Array:
	assert(is_valid)
	return _points.duplicate()

static func _texture_float_count(records: int, texels: int = 2) -> int:
	return TEXTURE_WIDTH*maxi(1,(records*texels+TEXTURE_WIDTH-1)/TEXTURE_WIDTH)*4

func _upload_points() -> void:
	var data := _points.to_byte_array()
	data.resize(_texture_float_count(render_point_count)*4)
	var height := data.size()/(TEXTURE_WIDTH*16)
	if not _point_image or _point_image.get_height() != height:
		_point_image = Image.create_from_data(TEXTURE_WIDTH,height,false,Image.FORMAT_RGBAF,data)
		_point_texture = ImageTexture.create_from_image(_point_image)
	else:
		_point_image.set_data(TEXTURE_WIDTH,height,false,Image.FORMAT_RGBAF,data)
		_point_texture.update(_point_image)

func recalculate_bounds() -> void:
	assert(is_valid)
	_manual_bounds = false
	var minimum := Vector3(_points[0],_points[1],_points[2]) if render_point_count else Vector3.ZERO
	var maximum := minimum
	var radius := 0.0
	for i in render_point_count:
		var p := Vector3(_points[i*8],_points[i*8+1],_points[i*8+2])
		minimum = minimum.min(p); maximum = maximum.max(p)
		radius = maxf(radius,_points[i*8+3]*0.5)
	_bounds = AABB(minimum,maximum-minimum).grow(radius*maxf(2.0,_miter_limit)+0.25)
	_instance.custom_aabb = _bounds
	_bounds_geometry = -1

func set_local_bounds(bounds: AABB) -> void:
	assert(is_valid)
	assert(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x >= 0 and bounds.size.y >= 0 and bounds.size.z >= 0)
	_bounds = bounds.grow(0.25)
	_manual_bounds = true
	_instance.custom_aabb = _bounds
	_bounds_geometry = -1

func _refresh_bounds() -> void:
	if not _manual_bounds: recalculate_bounds()

var _dash := MoldDash.new()
var dash: MoldDash:
	get: return _dash.duplicate_dash()

## Phase changes update uniforms and preserve the point stream and carrier.
func set_dash(value: MoldDash) -> void:
	if not is_valid: return
	var candidate := value if value else MoldDash.new()
	if _dash.equals(candidate): return
	var next := _vertex_layout(candidate)
	if next<0: return
	_dash=candidate.duplicate_dash()
	if next!=_vertices_per_segment:
		_vertices_per_segment=next
		_rebuild_mesh()

func _vertex_layout(value: MoldDash = null) -> int:
	var pattern_dash := value if value != null else _dash
	if not MoldPathDashes.validate(pattern_dash,0,false): return -1
	if not pattern_dash.is_enabled: return 12 if _join == MoldPolyline.Join.MITER and _cap != MoldPolyline.Cap.ROUND else 36
	var slots := 1
	for i in segment_count:
		var o := i*12
		var length := _segment_bytes.decode_float((o+7)*4)
		var closed := _segment_bytes.decode_float((o+10)*4)>0
		if not MoldPathDashes.validate(pattern_dash,length,closed): return -1
		var pattern := MoldPathDashes.resolve(pattern_dash,length,closed)
		if pattern.z>0 and pattern.z<1:
			slots=maxi(slots,ceili((_segment_bytes.decode_float((o+6)*4)-_segment_bytes.decode_float((o+5)*4))/length*pattern.x)+2)
	if slots*36*segment_count>16777216:
		push_error("GPU dash carrier exceeds the vertex budget; split or simplify the stream.")
		return -1
	return slots*36

func _update_vertex_layout() -> void:
	var next := _vertex_layout()
	if next<0 or next == _vertices_per_segment: return
	_vertices_per_segment = next
	_rebuild_mesh()

func _rebuild_mesh() -> void:
	var next := _vertex_layout()
	if next<0: return
	_vertices_per_segment = next
	if _instance.mesh and _mesh_vertex_count == generated_vertex_count: return
	_mesh_vertex_count=generated_vertex_count
	_instance.mesh = null
	if not segment_count: return
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	vertices.resize(generated_vertex_count)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.custom_aabb = _bounds
	_instance.mesh = mesh

static func shader_source(mode: int, state: MoldRenderState) -> String:
	return MoldShader.source(mode, state, MoldShader.Backend.GPU_POLYLINE, mode == MoldStyle.BlendMode.OPAQUE)


func _set_parameter(name: StringName, value: Variant) -> void:
	if not _parameters.has(name) or _parameters[name] != value:
		_material.set_shader_parameter(name, value)
		_parameters[name] = value

func _set_instance_parameter(name: StringName, value: Variant) -> void:
	if not _instance_parameters.has(name) or _instance_parameters[name] != value:
		_instance.set(name, value)
		_instance_parameters[name] = value

func _sync(viewport_size: Vector2, msaa: bool) -> void:
	if not _disposed: _instance.sync_environment()
	if _disposed: return
	if _material_dirty:
		_material = _custom_material.duplicate() if _custom_material else ShaderMaterial.new()
		if not _custom_material:
			_material.shader = MoldShader.get_shader(_style.mode, _state, MoldShader.Backend.GPU_POLYLINE, _style.mode == MoldStyle.BlendMode.OPAQUE, _style.appearance)
			if _style.appearance: _style.appearance.apply(_material)
		_instance.material_override = _material
		_material_dirty = false
		_parameters.clear()
	_set_instance_parameter(&"visible", _visible and segment_count > 0)
	_set_instance_parameter(&"transform", _transform)
	_set_instance_parameter(&"layers", _state.render_layer_mask)
	var basis := _instance.global_basis if geometry == MoldPolyline.Geometry.BILLBOARD else Basis.IDENTITY
	if _bounds_value != _bounds or _bounds_basis != basis or _bounds_geometry != geometry:
		_instance.custom_aabb = MoldPolyline.billboard_local_bounds(_bounds,basis) if geometry == MoldPolyline.Geometry.BILLBOARD else _bounds
		_bounds_value = _bounds; _bounds_basis = basis; _bounds_geometry = geometry
	var priority := clampi(_state.sorting_order,-128,127)
	if _parameters.get(&"_priority") != priority:
		_material.render_priority = priority
		_parameters[&"_priority"] = priority
	_set_parameter(&"primary_color",MoldMultiMeshRenderer.pack_color_vector(_style.color,_style.color_mode,_style.color_interpolation))
	if _custom_material:
		_set_parameter(&"mold_custom_instance_data",
			MoldMultiMeshRenderer.create_single_custom_data_texture(_style.shader_data))
		_set_parameter(&"mold_custom_instance_data_2",
			MoldMultiMeshRenderer.create_single_custom_data_texture(_style.shader_data_2))
	_set_parameter(&"secondary_color",MoldMultiMeshRenderer.pack_color_vector(_style.secondary_color,_style.color_mode,_style.color_interpolation))
	_set_parameter(&"emission_strength",_style.emission_strength)
	var d := _style.gradient_direction
	_set_parameter(&"gradient_data",Vector4(d.x,d.y,d.z,_style.color_mode+8*_style.color_interpolation+16*_style.gradient_space))
	var aa := 0 if local_aa_quality == 0 else (1 if local_aa_quality == 1 else 33)
	_set_parameter(&"mold_flags",Vector4(_style.emission_strength,0,0,aa+12))
	_set_parameter(&"mold_gpu_points",_point_texture)
	_set_parameter(&"mold_gpu_segments",_segment_texture)
	_set_parameter(&"mold_gpu_dash",Vector4(_dash.count if _dash.mode==MoldDash.Mode.FIXED_COUNT else -_dash.dash_length,_dash.spacing,_dash.snap,_dash.offset-floorf(_dash.offset)) if _dash.is_enabled else Vector4.ZERO)
	_set_parameter(&"mold_gpu_dash_cap",2 if _dash.type==MoldDash.Type.ROUNDED else -1)
	_set_parameter(&"mold_gpu_vertices_per_segment",_vertices_per_segment)
	_set_parameter(&"mold_gpu_join",_join)
	_set_parameter(&"mold_gpu_cap",_cap)
	_set_parameter(&"mold_gpu_geometry",geometry)
	_set_parameter(&"mold_gpu_miter_limit",_miter_limit)
	_set_parameter(&"mold_viewport_size",viewport_size)
	_set_parameter(&"dash_data",Vector4(1.0-_reveal,0,0,0))
	_set_parameter(&"mold_msaa_enabled",msaa)
	if _style.appearance or _instance._appearance_oit_active: _instance.sync_oit(_style,_state,local_aa_quality,"gpu_polyline")

func dispose() -> void:
	if _disposed: return
	var owner: Node = _owner.get_ref()
	if is_instance_valid(owner): owner.release_gpu_polyline_renderer(self)
	else: _dispose_from_world()

func _dispose_from_world() -> void:
	if _disposed: return
	_disposed = true
	_instance.mesh = null
	_instance.material_override = null
	_instance.dispose()
	_point_image = null; _point_texture = null; _segment_texture = null; _material = null; _custom_material = null
	_parameters.clear(); _instance_parameters.clear()
	_points = PackedFloat32Array(); _paths.clear()
	_points = PackedFloat32Array(); _paths.clear()
	_segment_image=null; _segment_bytes=PackedByteArray()


func _copy_ranges(source: Array[MoldGpuPolylineRange], destination: Array[MoldGpuPolylineRange]) -> void:
	destination.resize(source.size())
	for i in source.size():
		var path := source[i]
		if not destination[i]: destination[i]=MoldGpuPolylineRange.new(path.start_index,path.point_count,path.closed)
		else:
			destination[i].start_index=path.start_index
			destination[i].point_count=path.point_count
			destination[i].closed=path.closed

func recalculate_distances() -> void:
	if not is_valid or not _segment_image: return
	var points := _points
	var paths := _paths
	var write := 0
	for path in paths:
		var end := path.start_index+path.point_count
		var n := path.point_count if path.closed else path.point_count-1
		var distance := 0.0
		var first_segment := write
		for s in n:
			var a := path.start_index+s
			var b := path.start_index if a+1 == end else a+1
			var length := Vector3(points[b*8]-points[a*8],points[b*8+1]-points[a*8+1],points[b*8+2]-points[a*8+2] if geometry == MoldPolyline.Geometry.BILLBOARD else 0.0).length()
			var o := write*12
			write += 1
			_segment_bytes.encode_float((o)*4,(end-1 if path.closed else a) if s == 0 else a-1)
			_segment_bytes.encode_float((o+1)*4,a); _segment_bytes.encode_float((o+2)*4,b)
			_segment_bytes.encode_float((o+3)*4,(path.start_index if path.closed else b) if b+1 == end else b+1)
			_segment_bytes.encode_float((o+4)*4,0 if path.closed else (1 if s == 0 else 0)+(2 if s == n-1 else 0))
			_segment_bytes.encode_float((o+5)*4,distance); distance += length; _segment_bytes.encode_float((o+6)*4,distance)
		for s in range(first_segment,write):
			var prev := (write-1 if path.closed else s) if s==first_segment else s-1
			var following := (first_segment if path.closed else s) if s==write-1 else s+1
			_segment_bytes.encode_float((s*12+7)*4,maxf(distance,0.00001))
			_segment_bytes.encode_float((s*12+8)*4,_segment_bytes.decode_float((prev*12+6)*4)-_segment_bytes.decode_float((prev*12+5)*4))
			_segment_bytes.encode_float((s*12+9)*4,_segment_bytes.decode_float((following*12+6)*4)-_segment_bytes.decode_float((following*12+5)*4))
			_segment_bytes.encode_float((s*12+10)*4,1.0 if path.closed else 0.0)
	_segment_image.set_data(TEXTURE_WIDTH,_segment_bytes.size()/(TEXTURE_WIDTH*16),false,Image.FORMAT_RGBAF,_segment_bytes)
	_segment_texture.update(_segment_image)
	_update_vertex_layout()
