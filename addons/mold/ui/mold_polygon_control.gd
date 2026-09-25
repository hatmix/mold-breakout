@tool
class_name MoldPolygonControl
extends MoldControl
@export var polygon: MoldPolygonResource=MoldPolygonResource.new():
 set(value):
  if polygon and polygon.changed.is_connected(_polygon_changed):polygon.changed.disconnect(_polygon_changed)
  polygon=value if value else MoldPolygonResource.new()
  if not polygon.changed.is_connected(_polygon_changed):polygon.changed.connect(_polygon_changed)
  _polygon_changed()
var _runtime_polygon: MoldPolygon
func _enter_tree() -> void:
 super._enter_tree()
 if not polygon.changed.is_connected(_polygon_changed):polygon.changed.connect(_polygon_changed)
func _polygon_changed() -> void:
 _runtime_polygon=null
 refresh()
func set_polygon(value: MoldPolygon) -> void:
 _runtime_polygon=value
 refresh()
func _build_geometry() -> Dictionary:
 var p:=_runtime_polygon if _runtime_polygon else polygon.to_polygon()
 if not p or p.count<3:return {}
 var vertices:=PackedVector2Array()
 for v in p._vertices:vertices.append(Vector2(v.x,v.y))
 var bounds:=Rect2(vertices[0],Vector2.ZERO)
 for v in vertices:bounds=bounds.expand(v)
 var uv:=PackedVector2Array()
 for v in vertices:uv.append((v-bounds.position)/bounds.size.max(Vector2(.0001,.0001)))
 return {"kind":2,"aa":local_aa_quality,"vertices":vertices,"uv":uv,"indices":p._triangles,"colors":p._colors,"parameters":{"shape_data":Vector4.ZERO,"dash_data":Vector4.ZERO,"mold_flags":Vector4.ZERO,"ui_geometry":Vector4(2,p.count,0,1),"ui_extent":Vector4(bounds.size.x,bounds.size.y,0,TAU)}}
