@tool
extends Node2D
var mesh: Mesh
func _draw() -> void:
 if mesh:draw_mesh(mesh,null)
