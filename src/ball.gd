class_name Ball
extends RigidBody3D

@export var speed: float = 7

var stopped: bool = true
var current_speed: float = speed


func _ready() -> void:
	add_to_group("Balls")
	body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	if stopped:
		return
	# Prevent flat trajectories (hopefully?)
	if abs(linear_velocity.normalized().y) < 0.2:
		apply_central_impulse(Vector3.DOWN)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if stopped:
		return
	state.linear_velocity = state.linear_velocity.normalized() * current_speed


func _on_body_entered(body: Node) -> void:
	if body is Brick:
		body.destroy()
	if body is Paddle:
		current_speed += .2


func launch() -> void:
	if stopped:
		apply_central_impulse(Vector3.UP.rotated(Vector3.FORWARD, randf_range(-.1, .1)) * 10)
		stopped = false
