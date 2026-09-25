@tool
class_name MoldPolylineControl
extends MoldControl
@export var polyline: MoldPolylineResource=MoldPolylineResource.new():
 set(value):
  if polyline and polyline.changed.is_connected(_path_changed):polyline.changed.disconnect(_path_changed)
  polyline=value if value else MoldPolylineResource.new()
  if not polyline.changed.is_connected(_path_changed):polyline.changed.connect(_path_changed)
  _path_changed()
@export_range(0,1) var reveal:=1.0:
 set(value):
  reveal=clampf(value,0,1)
  if _geometry_parameters.has("ui_geometry"):
   _geometry_parameters.ui_geometry.w=reveal
   _style_dirty=true
var _runtime_path: MoldPolyline
func _enter_tree() -> void:
 super._enter_tree()
 if not polyline.changed.is_connected(_path_changed):polyline.changed.connect(_path_changed)
func _path_changed() -> void:
 _runtime_path=null
 refresh()
func set_polyline(value: MoldPolyline) -> void:
 if not value or value.geometry!=MoldPolyline.Geometry.FLAT_2D:
  push_error("Mold UI paths require Flat2D geometry.")
  return
 _runtime_path=value
 refresh()
func _resolve_path() -> MoldPolyline:return _runtime_path if _runtime_path else polyline.to_polyline()
func _build_geometry() -> Dictionary:
 var path:=_resolve_path()
 if not path or path.geometry!=MoldPolyline.Geometry.FLAT_2D:return {}
 var buffers:=MoldMeshCache.MeshBuffers.new()
 MoldPolylineMeshGenerator.generate(buffers,path)
 var vertices:=PackedVector2Array()
 for p in buffers.vertices:vertices.append(Vector2(p.x,p.y))
 return {"kind":1,"aa":local_aa_quality,"vertices":vertices,"uv":buffers.uvs,"indices":buffers.indices,"extrusions":buffers.extrusions,"coordinates":buffers.polyline_coordinates,"changes":buffers.polyline_changes,"colors":buffers.colors,"parameters":{"shape_data":Vector4.ZERO,"dash_data":Vector4.ZERO,"mold_flags":Vector4(0,0,0,12),"ui_geometry":Vector4(1,0,path.point_color_interpolation,reveal),"ui_extent":Vector4(1,1,0,TAU)}}

func _get_configuration_warnings() -> PackedStringArray:
 var warnings:=super._get_configuration_warnings()
 var resource: MoldPolylineResource = get("curve") if self is MoldCurveControl else polyline
 if resource and resource.geometry!=MoldPolyline.Geometry.FLAT_2D:
  warnings.append("Native UI requires Flat 2D geometry. Change Geometry to Flat 2D; make geometry unique first if the resource is shared with world nodes.")
 return warnings
