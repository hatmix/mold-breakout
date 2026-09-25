@tool
extends RefCounted
## Canvas mesh and material ownership. This path uses its Control as the rendering host.
static var _materials: Dictionary = {}
static var _shaders: Dictionary = {}
var mesh: ArrayMesh
var build_count := 0
var _lease := ""
var _custom_revision := 0
var _owner: WeakRef
var _geometry: Dictionary = {}
var _parameters: Dictionary = {}
var _style: Dictionary = {}
var _texture: ImageTexture
var _contour: ImageTexture
var _metric := Vector3.ZERO
var _dirty := true
var _linear := false
var _material_parameters := RenderingServer.get_current_rendering_method()=="gl_compatibility"
var _bounds := Rect2()
var _material_inputs_valid := false
var _last_mode := -1
var _last_appearance := -1
var _last_effects: Dictionary = {}
var _last_linear := false
var _last_texture: ImageTexture
var _last_contour: ImageTexture
var _last_custom: ShaderMaterial
var _last_custom_revision := -1

func bind(owner: Control) -> void:
 _owner=weakref(owner)

func geometry(value: Dictionary) -> void:
 # The parameters entry contains uniforms; it does not change the mesh.
 var geometry_changed := _geometry.size()-int(_geometry.has("parameters")) != value.size()-int(value.has("parameters"))
 if not geometry_changed:
  for key in value:
   if key != "parameters" and (not _geometry.has(key) or _geometry[key] != value[key]):
    geometry_changed=true
    break
 _geometry=value
 if geometry_changed:_dirty=true

func invalidate_custom() -> void:
 _custom_revision+=1

func style(value: Dictionary) -> void:
 _style=value
 var owner: Control=_owner.get_ref()
 for key in value.get("parameters",{}):
  var v: Variant=value.parameters[key]
  if not _parameters.has(key) or _parameters[key]!=v:
   _parameters[key]=v
   _write_parameter(owner,key,v)
 _material()

func parameter(key: String, value: Variant) -> void:
 if _parameters.get(key)==value:return
 _parameters[key]=value
 var owner: Control=_owner.get_ref()
 _write_parameter(owner,key,value)

func _write_parameter(owner: Control, key: String, value: Variant) -> void:
 if _material_parameters:
  if owner.material:owner.material.set_shader_parameter(key,value)
 else:owner.set_instance_shader_parameter(key,value)

func prepare() -> void:
 var owner: Control=_owner.get_ref()
 var transform:=owner.get_global_transform_with_canvas()
 var metric:=Vector3(transform.x.length_squared(),transform.y.length_squared(),transform.x.dot(transform.y))
 if not metric.is_equal_approx(_metric):_metric=metric;_dirty=true
 var linear:=owner.get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method()!="gl_compatibility"
 if linear!=_linear:_linear=linear;_material()
 if not _dirty:return
 _dirty=false
 _build(transform)
 owner.queue_redraw()

func _build(transform: Transform2D) -> void:
 build_count+=1
 mesh=null
 if _geometry.is_empty():return
 var vertices: PackedVector2Array=_geometry.vertices.duplicate()
 var uv: PackedVector2Array=_geometry.uv.duplicate()
 var indices: PackedInt32Array=_geometry.indices
 if vertices.is_empty() or indices.is_empty():return
 var aa:=int(_geometry.get("aa",2))
 var kind:=int(_geometry.get("kind",0))
 if kind==0:
  var axes: Transform2D=_geometry.axes
  var px:=maxf((transform.basis_xform(axes.x)).length(),.00001)
  var py:=maxf((transform.basis_xform(axes.y)).length(),.00001)
  var pad:=Vector2(2.0/px,2.0/py) if aa>0 else Vector2.ZERO
  for i in vertices.size():
   uv[i]=(uv[i]-Vector2.ONE*.5)*(Vector2.ONE+pad)+Vector2.ONE*.5
   vertices[i]=axes*(uv[i]-Vector2.ONE*.5)
 elif kind==1:
  var data:=PackedFloat32Array()
  var coord: PackedFloat32Array=_geometry.coordinates
  var change: PackedFloat32Array=_geometry.changes
  var extrude: PackedFloat32Array=_geometry.extrusions
  var colors: PackedColorArray=_geometry.colors
  for i in vertices.size():
   var o:=i*4
   var e:=Vector2(extrude[o],extrude[o+1])
   var segment:=extrude[o+2]<.5
   var direction:=Vector2(coord[o],change[o]) if segment else e.normalized()
   var diameter:=maxf(transform.basis_xform(direction*extrude[o+3]).length()*2.0,.00001)
   var factor:=maxf(1.0,diameter+2.0)/diameter if aa>0 else 1.0
   vertices[i]+=e*(factor-1.0)
   for j in 4:data.append(0.0 if segment and j==0 else coord[o+j]+change[o+j]*(factor-1.0))
   var col:=colors[i]
   data.append_array(PackedFloat32Array([col.r,col.g,col.b,col.a]))
   if extrude[o+2]>1.5:uv[i].y+=2.0
  _texture=_make_texture(data,2)
 elif kind==2:
  var data:=PackedFloat32Array()
  var colors: PackedColorArray=_geometry.colors
  for i in vertices.size():
   var col:=colors[i].srgb_to_linear()
   data.append_array(PackedFloat32Array([vertices[i].x,vertices[i].y,0.0,0.0,col.r,col.g,col.b,col.a]))
  _contour=_make_texture(data,2)
 var arrays:=[]
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices
 arrays[Mesh.ARRAY_TEX_UV]=uv
 arrays[Mesh.ARRAY_INDEX]=indices
 mesh=ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
 _bounds=Rect2(vertices[0],Vector2.ZERO)
 for v in vertices:_bounds=_bounds.expand(v)
 _material()

func _make_texture(data: PackedFloat32Array, stride: int) -> ImageTexture:
 var texels:=data.size()/4
 var width:=mini(1024,texels)
 width=maxi(stride,width-width%stride)
 var height:=ceili(float(texels)/width)
 data.resize(width*height*4)
 return ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RGBAF,data.to_byte_array()))

func _material() -> void:
 if _style.is_empty():return
 var owner: Control=_owner.get_ref()
 var effects: Dictionary=_style.get("effects",{})
 var mode:=int(_style.get("mode",1))
 var appearance:=int(_style.get("appearance",0))
 var custom: ShaderMaterial=_style.get("custom")
 if _material_inputs_valid and mode == _last_mode and appearance == _last_appearance and effects == _last_effects and _linear == _last_linear and _texture == _last_texture and _contour == _last_contour and custom == _last_custom and (not custom or _custom_revision == _last_custom_revision):
  return
 var key:=str([mode,appearance,effects,_linear,_texture.get_instance_id() if _texture else 0,_contour.get_instance_id() if _contour else 0,custom.get_instance_id() if custom else 0,_custom_revision if custom else 0,owner.get_instance_id() if custom or _material_parameters else 0])
 if key==_lease:return
 _release()
 if not _materials.has(key):
  var material: ShaderMaterial
  if custom:
   if not custom.shader or not "MOLD_UI_CONTRACT" in custom.shader.code:
    push_error("Custom Mold UI material must declare MOLD_UI_CONTRACT.")
    return
   material=custom.duplicate()
   if _material_parameters:
    var shader:=Shader.new()
    shader.code="#define MOLD_UI_MATERIAL_PARAMETERS\n"+custom.shader.code
    material.shader=shader
    for property in custom.get_property_list():
     if str(property.name).begins_with("shader_parameter/"):
      var value: Variant=custom.get(property.name)
      if value!=null:material.set(property.name,value)
  else:
   material=ShaderMaterial.new()
   var blend:="blend_mix"
   if mode in [2,9,10,12]:blend="blend_add"
   elif mode==7:blend="blend_sub"
   elif mode in [3,8,11,13]:blend="blend_mul"
   var prefix:=""
   if appearance:prefix="#define MOLD_APPEARANCE\n#define MOLD_%s\n"%("PAINT" if appearance==1 else "PENCIL")
   if _material_parameters:prefix+="#define MOLD_UI_MATERIAL_PARAMETERS\n"
   var shader_key:=mode | (appearance << 4) | (int(_material_parameters) << 6)
   if not _shaders.has(shader_key):
    var shader:=Shader.new()
    shader.code="shader_type canvas_item;\nrender_mode unshaded, %s;\n#define MOLD_UI_CONTRACT 1\n#define MOLD_UI_BLEND_MODE %d\n"%[blend,mode]+prefix+'#include "res://addons/mold/ui/rendering/mold_canvas.gdshaderinc"\n'
    _shaders[shader_key]=shader
   material.shader=_shaders[shader_key]
  for name in effects:material.set_shader_parameter(name,effects[name])
  if _material_parameters:
   for name in _parameters:material.set_shader_parameter(name,_parameters[name])
  material.set_shader_parameter("ui_linear_output",_linear)
  if _texture:material.set_shader_parameter("ui_vertices",_texture)
  if _contour:
   material.set_shader_parameter("mold_polygon_points",_contour)
   material.set_shader_parameter("mold_polygon_count",_geometry.vertices.size())
   material.set_shader_parameter("mold_polygon_aa_quality",_geometry.get("aa",2))
  _materials[key]={"material":material,"refs":0}
 _material_inputs_valid=true
 _last_mode=mode
 _last_appearance=appearance
 _last_effects=effects
 _last_linear=_linear
 _last_texture=_texture
 _last_contour=_contour
 _last_custom=custom
 _last_custom_revision=_custom_revision
 _lease=key
 _materials[key].refs+=1
 owner.material=_materials[key].material

func _release() -> void:
 _material_inputs_valid=false
 if _lease.is_empty():return
 _materials[_lease].refs-=1
 if _materials[_lease].refs==0:_materials.erase(_lease)
 _lease=""

func dispose() -> void:
 _release()
 mesh=null
 _texture=null
 _contour=null
 _geometry={}

func contains(point: Vector2) -> bool:
 return _bounds.has_point(point)

static func material_count() -> int:return _materials.size()

func editor_snapshot() -> Dictionary:
 return {"mesh":mesh,"bounds":_bounds,"parameters":_parameters.duplicate(),"vertices_texture":_texture,"contour_texture":_contour,"count":_geometry.get("vertices",PackedVector2Array()).size(),"aa":_geometry.get("aa",2),"custom":_style.get("custom")!=null}
