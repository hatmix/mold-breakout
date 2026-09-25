class_name MoldBezierKnot
extends RefCounted
enum HandleMode { FREE, ALIGNED, MIRRORED, AUTO }
var _position: Vector3
var _in_offset: Vector3
var _out_offset: Vector3
var position: Vector3:
	get: return _position
var in_offset: Vector3:
	get: return _in_offset
var out_offset: Vector3:
	get: return _out_offset
func _init(p := Vector3.ZERO, incoming := Vector3.ZERO, outgoing := Vector3.ZERO) -> void:
	_position=p; _in_offset=incoming; _out_offset=outgoing
func with_position(value: Vector3) -> MoldBezierKnot: return MoldBezierKnot.new(value,in_offset,out_offset)
func with_in_offset(value: Vector3) -> MoldBezierKnot: return MoldBezierKnot.new(position,value,out_offset)
func with_out_offset(value: Vector3) -> MoldBezierKnot: return MoldBezierKnot.new(position,in_offset,value)
func move_handle(incoming: bool,offset: Vector3,mode := HandleMode.FREE) -> MoldBezierKnot:
	var other := out_offset if incoming else in_offset
	if mode==HandleMode.MIRRORED: other=-offset
	elif mode==HandleMode.ALIGNED and offset.length()>0.00000001: other=-offset.normalized()*other.length()
	return MoldBezierKnot.new(position,offset,other) if incoming else MoldBezierKnot.new(position,other,offset)
