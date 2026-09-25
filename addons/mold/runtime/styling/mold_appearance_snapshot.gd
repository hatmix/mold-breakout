class_name MoldAppearanceSnapshot
extends RefCounted

# Private copied data; runtime consumers never retain an editable Resource.
var _kind: int
var _values: Dictionary
var _automatic: bool
var _surface := false
var _key: String
var _packed_uniforms: PackedByteArray
var _variant_name: String
var _length: float
var _resolved: MoldAppearanceSnapshot
var _cache_resolutions := true
var kind: int:
	get: return _kind
var surface: bool:
	get: return _surface
var key: String:
	get: return _key
func _init(value_kind: int, values: Dictionary, automatic := true, surface_target := false) -> void:
	_kind=value_kind
	_values=values.duplicate(true)
	_values.make_read_only()
	_automatic=automatic
	_surface=surface_target
	_key=str(_kind)+"/"+str(_automatic)+"/"+str(_surface)+"/"+var_to_str(_values)
	_length=float(_values.get("_PaintLength" if kind == 1 else "_PencilLength",-1.0))
	_packed_uniforms=_pack_uniforms()
	_variant_name=("paint" if kind == 1 else "pencil")+("_surface" if surface else "_stroke")
func resolve(path_length: float, surface_target := false) -> MoldAppearanceSnapshot:
	if surface_target == _surface and (not _automatic or path_length < 0.0 or maxf(.001,path_length) == _length): return self
	var target_length := maxf(.001,path_length) if _automatic and path_length >= 0.0 else _length
	if _resolved and _resolved.surface == surface_target and _resolved._length == target_length: return _resolved
	var values := _values.duplicate()
	if _automatic and path_length >= 0.0:
		values["_PaintLength" if kind == 1 else "_PencilLength"]=maxf(.001,path_length)
	if surface_target == _surface and values == _values: return self
	var next := MoldAppearanceSnapshot.new(kind,values,_automatic,surface_target)
	# Only the authored snapshot keeps one reusable result. Resolved results must
	# not link to subsequent lengths when a live curve animates.
	next._cache_resolutions=false
	if _cache_resolutions: _resolved=next
	return next
func apply(material: ShaderMaterial) -> void:
	for name in _values: material.set_shader_parameter(name,_values[name])
	material.set_meta(&"mold_appearance_variant",_variant_name)
	material.set_meta(&"mold_appearance_data",_packed_uniforms)
func packed_uniforms() -> PackedByteArray:
	return _packed_uniforms.duplicate()
func _pack_uniforms() -> PackedByteArray:
	var data := PackedFloat32Array()
	var names := _values.keys()
	names.sort()
	for name in names:
		if _values[name] is float or _values[name] is int: data.append(float(_values[name]))
	while data.size()%4: data.append(0.0)
	for name in names:
		var value: Variant = _values[name]
		if value is Color:
			var color: Color = value.srgb_to_linear()
			data.append_array(PackedFloat32Array([color.r,color.g,color.b,color.a]))
		elif value is Vector4: data.append_array(PackedFloat32Array([value.x,value.y,value.z,value.w]))
	data.resize(32)
	return data.to_byte_array()
func shader_prefix() -> String:
	return "#define MOLD_APPEARANCE\n#define MOLD_%s\n" % ("PAINT" if kind == 1 else "PENCIL") + ("#define MOLD_SURFACE\n" if surface else "")
static func for_geometry(value: MoldAppearanceSnapshot, shape: MoldShape = null, path: MoldPolyline = null) -> MoldAppearanceSnapshot:
	if not value: return null
	if path: return value.resolve(path.length)
	if not shape: return value
	if not shape.is_2d: return value.resolve(-1.0,true)
	var length := -1.0
	if shape.is_line: length=shape.start_position.distance_to(shape.end_position)
	elif shape.kind == MoldShape.Kind.ELLIPSE_RIM: length=MoldEllipseGeometry.arc_length(Vector2(shape.size.x,shape.size.y)*.5,0,TAU)
	elif shape.kind == MoldShape.Kind.DISC_RIM: length=TAU*shape.radius
	elif shape.kind in [MoldShape.Kind.RECTANGLE_RIM,MoldShape.Kind.REGULAR_POLYGON_RIM]: length=shape.dash_path_length()
	return value.resolve(length,false)
