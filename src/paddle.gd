class_name Paddle
extends AnimatableBody3D

@export var speed = 7.0


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir:
		global_position.x = clamp(global_position.x + input_dir * speed * delta, -3, 3)
