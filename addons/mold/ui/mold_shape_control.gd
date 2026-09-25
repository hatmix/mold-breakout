@tool
class_name MoldShapeControl
extends MoldControl

enum Sizing { RECT, AUTHORED }
@export var shape: MoldShapeResource = _default_shape():
 set(value):
  if shape and shape.changed.is_connected(_shape_changed):shape.changed.disconnect(_shape_changed)
  shape=value if value else _default_shape()
  if not shape.changed.is_connected(_shape_changed):shape.changed.connect(_shape_changed)
  _shape_changed()
@export var sizing: Sizing=Sizing.RECT:
 set(value):sizing=value;refresh()
var _runtime_shape: MoldShape
static func _default_shape() -> MoldShapeResource:
 var s:=MoldShapeResource.new()
 s.kind=MoldShape.Kind.RECTANGLE
 s.size_2d=Vector2(100,100)
 s.roundness=0
 s.resource_local_to_scene=true
 return s
func _enter_tree() -> void:
 super._enter_tree()
 if not shape.changed.is_connected(_shape_changed):shape.changed.connect(_shape_changed)
func _shape_changed() -> void:
 _runtime_shape=null
 refresh()
func set_shape(value: MoldShape) -> void:
 if not value or not value.is_2d or value.billboard_mode!=MoldShape.BillboardMode.DISABLED:
  push_error("MoldShapeControl requires a planar shape without billboarding.")
  return
 _runtime_shape=value
 sizing=Sizing.AUTHORED
 refresh()
func _build_geometry() -> Dictionary:
 var s:=_runtime_shape if _runtime_shape else shape.to_shape()
 if not s or not s.is_2d or s.billboard_mode!=MoldShape.BillboardMode.DISABLED:return {}
 if sizing==Sizing.RECT and not s.is_line:
  var resource:=shape.duplicate() as MoldShapeResource
  resource.size_2d=size.max(Vector2(.0001,.0001))
  if s.kind==MoldShape.Kind.ELLIPSE_RIM: resource.size_2d=Vector2(maxf(0,size.x-s.thickness),maxf(0,size.y-s.thickness))
  resource.radius=maxf(.0001,minf(size.x,size.y)*.5-(s.thickness*.5 if s.kind==MoldShape.Kind.DISC_RIM else (s.thickness*.5/cos(PI/s.sides) if s.kind==MoldShape.Kind.REGULAR_POLYGON_RIM else 0.0)))
  s=resource.to_shape()
 if s.is_empty:return {}
 var layout:=MoldShapeLayout.resolve(s)
 var t: Transform3D=layout.local_transform
 var axes:=Transform2D(Vector2(t.basis.x.x,t.basis.x.y),Vector2(t.basis.y.x,t.basis.y.y),Vector2(t.origin.x,t.origin.y)+(size*.5 if sizing==Sizing.RECT else Vector2.ZERO))
 var uv:=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
 var vertices:=PackedVector2Array()
 for v in uv:vertices.append(axes*(v-Vector2.ONE*.5))
 return {"kind":0,"aa":local_aa_quality,"axes":axes,"vertices":vertices,"uv":uv,"indices":PackedInt32Array([0,1,2,0,2,3]),"parameters":{"shape_data":layout.custom_data,"dash_data":s.dash.to_gpu_data(s.dash_path_length()) if s.dash else Vector4.ZERO,"mold_flags":Vector4(0,1,0,4 if s.is_line else 0),"ui_geometry":Vector4(0,0,0,1),"ui_extent":Vector4(layout.scale.x,layout.scale.y,s.start_radians,s.span_radians)}}

func _get_configuration_warnings() -> PackedStringArray:
 var warnings:=super._get_configuration_warnings()
 if shape and not shape._is_2d_kind(shape.kind):
  warnings.append("Native UI requires a planar shape. Select a 2D Kind; make geometry unique first if the resource is shared with world nodes.")
 if shape and shape.billboard_mode!=MoldShape.BillboardMode.DISABLED:
  warnings.append("Billboarding is unsupported by native UI, so this shape cannot render. Open the shape resource separately and set Billboard Mode to Disabled. Make Geometry Unique first if other nodes need the shared resource's billboarding.")
 return warnings
