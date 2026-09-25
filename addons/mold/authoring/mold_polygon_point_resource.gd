@tool
class_name MoldPolygonPointResource
extends Resource

@export var position := Vector3.ZERO:
	set(value): position = value; emit_changed()
@export var color := Color.WHITE:
	set(value): color = value; emit_changed()
