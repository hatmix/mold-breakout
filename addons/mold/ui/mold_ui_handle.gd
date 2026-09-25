class_name MoldUiHandle
extends RefCounted
var _owner: WeakRef
var _slot: int
var _generation: int
var is_valid: bool:
 get:
  var owner=_owner.get_ref()
  return is_instance_valid(owner) and owner._valid(self)
var control: MoldControl:
 get:
  var owner=_owner.get_ref()
  return owner._resolve(self) if is_instance_valid(owner) else null
func _init(owner: MoldUiLayer, slot: int, generation: int) -> void:
 _owner=weakref(owner);_slot=slot;_generation=generation
func release() -> void:
 var owner=_owner.get_ref()
 if is_instance_valid(owner):owner._release(self)
func set_shape(value: MoldShape) -> void:
 if control is MoldShapeControl:control.set_shape(value)
func set_polyline(value: MoldPolyline) -> void:
 if control is MoldPolylineControl:control.set_polyline(value)
func set_curve(value: MoldCurve, stroke: MoldStroke, sampling: MoldCurveSampling=null) -> void:
 if control is MoldCurveControl:control.set_curve(value,stroke,sampling)
func set_polygon(value: MoldPolygon) -> void:
 if control is MoldPolygonControl:control.set_polygon(value)
func set_style(value: MoldStyle) -> void:
 if control:control.set_style(value)
func set_color(value: Color) -> void:
 if control:control.set_color(value)
func set_reveal(value: float) -> void:
 if control is MoldPolylineControl:control.reveal=value
static func _xy(value: Variant) -> Vector2:
 assert(value is Vector2 or value is Vector3,"UI transforms require Vector2 or planar Vector3.")
 return Vector2(value.x,value.y)
func set_position(value: Variant) -> void:
 if control:control.position=_xy(value)
func set_rotation(value: Variant) -> void:
 if control:
  if value is Quaternion:
   assert(absf(value.x)+absf(value.y)<.00001,"UI rotations must be planar.")
   control.rotation=2.0*atan2(value.z,value.w)
  else:control.rotation=float(value)
func set_scale(value: Variant) -> void:
 if control:control.scale=_xy(value)
func set_visible(value: bool) -> void:
 if control:control.visible=value
func set_transform(position: Variant, rotation: Variant, scale: Variant) -> void:
 set_position(position);set_rotation(rotation);set_scale(scale)
