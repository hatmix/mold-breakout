class_name Brick
extends StaticBody3D


@export var color: Color = Color.WHITE:
	set(v):
		color = v
		if is_node_ready():
			mold_node.style.color = color
			mold_node.style.secondary_color = color.lerp(Color.BLACK, 0.25)
			mold_hull.style.color = color.lerp(Color.BLACK, 0.25)

@onready var mold_node: MoldNode3D = %MoldNode3D
@onready var mold_hull: MoldNode3D = %MoldNode3DHull


func _ready() -> void:
	add_to_group("Bricks")
	mold_node.style.set_deferred("color", color)
	mold_node.style.set_deferred("secondary_color", color.lerp(Color.BLACK, 0.5))
	mold_hull.style.set_deferred("color", color.lerp(Color.BLACK, 0.5))


func destroy() -> void:
	queue_free()
