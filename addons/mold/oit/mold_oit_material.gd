@tool
class_name MoldOitMaterial
extends ShaderMaterial
## Unlit textured alpha material shared by native and OIT rendering.
const SURFACE = preload("mold_oit_surface.gdshader")
@export var color := Color(1,1,1,0.5):
	set(value):
		color = value
		set_shader_parameter("surface_color", value)
		emit_changed()
@export var texture: Texture2D:
	set(value):
		texture = value
		set_shader_parameter("surface_texture", value)
		emit_changed()
func _init() -> void:
	shader = SURFACE
	set_shader_parameter("surface_color", color)
