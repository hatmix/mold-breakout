@tool
class_name MoldControl
extends Control
## Native canvas graphic. Shape resources use local UI coordinates (+Y down).
const Backend=preload("rendering/mold_ui_backend.gd")
@export var style: MoldStyleResource = _default_style():
 set(value):
  if style and style.changed.is_connected(_style_changed):style.changed.disconnect(_style_changed)
  style=value if value else _default_style()
  if not style.changed.is_connected(_style_changed):style.changed.connect(_style_changed)
  _style_changed()
@export_group("Canvas")
@export_enum("Off:0", "Medium:1", "High:2") var local_aa_quality := 2:
 set(value):local_aa_quality=clampi(value,0,2);refresh()
@export var canvas_material: ShaderMaterial:
 set(value):
  canvas_material=value;_style_dirty=true
  if _renderer:_renderer.invalidate_custom()
var _renderer: RefCounted
var _geometry_dirty:=true
var _style_dirty:=true
var _runtime_style: MoldStyle
var _geometry_parameters: Dictionary={}
var _parameters: Dictionary={}
var _empty_effects: Dictionary={}
var _style_payload: Dictionary={}
var mesh_build_count: int:
 get:return _renderer.build_count if _renderer else 0

static func _default_style() -> MoldStyleResource:
 var s:=MoldStyleResource.new()
 s.mode=MoldStyle.BlendMode.TRANSPARENT
 s.gradient_space=MoldStyle.GradientSpace.OBJECT
 s.resource_local_to_scene=true
 return s
func _init() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
func _enter_tree() -> void:
 _renderer=Backend.new()
 _renderer.bind(self)
 if not style.changed.is_connected(_style_changed):style.changed.connect(_style_changed)
 refresh()
func _exit_tree() -> void:
 if _renderer:_renderer.dispose()
 _renderer=null
 material=null
func _notification(what: int) -> void:
 if what==NOTIFICATION_RESIZED:refresh()
func _process(_delta: float) -> void:
 _flush()
func _flush() -> void:
 if not _renderer:return
 if _geometry_dirty:
  _geometry_dirty=false
  var data:=_build_geometry()
  _geometry_parameters=data.get("parameters",{})
  _parameters.clear()
  _parameters.merge(_geometry_parameters)
  _renderer.geometry(data)
  _style_dirty=true
 if _style_dirty:
  _style_dirty=false
  if not _runtime_style and style.mode==MoldStyle.BlendMode.CUSTOM:
   push_error("World Custom blend is unsupported by native UI. Select a standard blend and assign Canvas Material.")
   return
  var value:=_runtime_style if _runtime_style else style.to_style()
  # Canvas gradients always use local coordinates; do not mutate shared world styles.
  if value.custom_material:
   push_error("World material handles cannot be used by Mold UI. Assign Canvas Material.")
   return
  var params:=_parameters
  params.merge(_geometry_parameters,true)
  params.primary_color=MoldMultiMeshRenderer.pack_color_vector(value.color,value.color_mode,value.color_interpolation)
  params.secondary_color=MoldMultiMeshRenderer.pack_color_vector(value.secondary_color,value.color_mode,value.color_interpolation)
  params.gradient_data=Vector4(value.gradient_direction.x,value.gradient_direction.y,value.gradient_direction.z,int(value.color_mode)+8*int(value.color_interpolation)+16)
  var flags: Vector4=_geometry_parameters.get("mold_flags",Vector4(0,1,0,0))
  flags.x=value.emission_strength
  flags.w=int(flags.w)+(0 if local_aa_quality==0 else (1 if local_aa_quality==1 else 33))
  params.mold_flags=flags
  params.mold_shader_data=value.shader_data
  params.mold_shader_data_2=value.shader_data_2
  _style_payload.parameters=params
  _style_payload.mode=value.mode
  _style_payload.appearance=value.appearance.kind if value.appearance else 0
  _style_payload.effects=value.appearance._values if value.appearance else _empty_effects
  _style_payload.custom=canvas_material
  _renderer.style(_style_payload)
 _renderer.prepare()
func _draw() -> void:
 if _renderer and _renderer.mesh:draw_mesh(_renderer.mesh,null)
func refresh() -> void:
 _geometry_dirty=true
 _style_dirty=true
 if Engine.is_editor_hint() and is_inside_tree():update_configuration_warnings()
func _style_changed() -> void:
 _runtime_style=null
 _style_dirty=true
 if Engine.is_editor_hint() and is_inside_tree():update_configuration_warnings()
func set_style(value: MoldStyle) -> void:
 _runtime_style=value
 _style_dirty=true
func set_color(value: Color) -> void:
 set_style((_runtime_style if _runtime_style else style.to_style()).with_color(value))
func _build_geometry() -> Dictionary:return {}
func _get_configuration_warnings() -> PackedStringArray:
 return PackedStringArray(["World Custom blend is unsupported by native UI. Select a standard blend and assign Canvas Material."]) if style and style.mode==MoldStyle.BlendMode.CUSTOM else PackedStringArray()

func editor_snapshot() -> Dictionary:
 _flush()
 return _renderer.editor_snapshot() if _renderer else {}
