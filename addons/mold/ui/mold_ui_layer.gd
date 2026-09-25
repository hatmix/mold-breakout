@tool
class_name MoldUiLayer
extends Control
## Ordered native controls with generation-checked handles.
var _entries: Array[Dictionary]=[]
var _serial:=0
var _clearing:=false
var _clear_cursor:=0
func _init() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func create(shape: MoldShape, style: MoldStyle, order:=0) -> MoldUiHandle:
 var node:=MoldShapeControl.new()
 node.set_shape(shape)
 return _add(node,style,order)
func create_polyline(path: MoldPolyline, style: MoldStyle, order:=0) -> MoldUiHandle:
 var node:=MoldPolylineControl.new()
 node.set_polyline(path)
 return _add(node,style,order)
func create_polygon(polygon: MoldPolygon, style: MoldStyle, order:=0) -> MoldUiHandle:
 var node:=MoldPolygonControl.new()
 node.set_polygon(polygon)
 return _add(node,style,order)
func create_curve(curve: MoldCurve, stroke: MoldStroke, style: MoldStyle, sampling: MoldCurveSampling=null, order:=0) -> MoldUiHandle:
 var node:=MoldCurveControl.new()
 node.set_curve(curve,stroke,sampling)
 return _add(node,style,order)
func _add(node: MoldControl, style: MoldStyle, order: int) -> MoldUiHandle:
 var slot:=-1
 for i in _entries.size():
  if not is_instance_valid(_entries[i].node):slot=i;break
 if slot<0:slot=_entries.size();_entries.append({"node":null,"generation":0,"order":0,"serial":0})
 _serial+=1
 var entry:=_entries[slot]
 entry.generation+=1;entry.node=node;entry.order=order;entry.serial=_serial
 # Cleanup callbacks can reuse slots that clear has already visited.
 if _clearing:_clear_cursor=mini(_clear_cursor,slot)
 node.set_style(style)
 add_child(node)
 var ordered:=_entries.filter(func(e):return is_instance_valid(e.node))
 ordered.sort_custom(func(a,b):return a.order<b.order or (a.order==b.order and a.serial<b.serial))
 for i in ordered.size():move_child(ordered[i].node,i)
 return MoldUiHandle.new(self,slot,entry.generation)
func _valid(handle: MoldUiHandle) -> bool:
 return handle._slot>=0 and handle._slot<_entries.size() and _entries[handle._slot].generation==handle._generation and is_instance_valid(_entries[handle._slot].node)
func _resolve(handle: MoldUiHandle) -> MoldControl:
 return _entries[handle._slot].node if _valid(handle) else null
func _release(handle: MoldUiHandle) -> void:
 if not _valid(handle):return
 var node: MoldControl=_entries[handle._slot].node
 _entries[handle._slot].node=null
 remove_child(node)
 node.queue_free()
func clear() -> void:
 if _clearing:return
 _clearing=true
 _clear_cursor=0
 while _clear_cursor<_entries.size():
  var slot:=_clear_cursor
  _clear_cursor+=1
  _release(MoldUiHandle.new(self,slot,_entries[slot].generation))
 _clearing=false
func dispose() -> void:clear()
