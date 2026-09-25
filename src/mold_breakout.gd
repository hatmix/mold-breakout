extends Node3D



@export var brick_scene: PackedScene
@export var ball_scene: PackedScene
@export var color_palette: ColorPalette

var context: MoldContext
var max_bricks: int = 0
var level_built: bool = false
var adding_row: bool = false
var color_idx: int = 0

@onready var paddle: AnimatableBody3D = %Paddle
@onready var lose_area: Area3D = %LoseArea
@onready var bricks: Node3D = %Bricks


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	randomize()
	color_idx = randi_range(0, color_palette.colors.size())
	_build_level.call_deferred()


func _process(_delta: float) -> void:
	# Let the player keep up with the ball as it gets faster
	if get_tree().get_node_count_in_group("Balls"):
		paddle.speed = get_tree().get_first_node_in_group("Balls").current_speed

	if not level_built or adding_row:
		return
	var brick_count: int = get_tree().get_node_count_in_group("Bricks")
	if brick_count > max_bricks:
		max_bricks = brick_count
	elif brick_count < max_bricks * 0.5 and not adding_row:
		add_row()
	var ball_count: int = get_tree().get_node_count_in_group("Balls")
	if ball_count == 0:
		spawn_ball()


func spawn_ball() -> void:
	var ball: Ball = ball_scene.instantiate()
	add_child(ball)
	ball.global_position = Vector3(0, 2, 0)
	var tween: Tween = create_tween()
	tween.tween_property(ball, "visible", false, 0.25)
	tween.tween_property(ball, "visible", true, 0.25)
	tween.tween_property(ball, "visible", false, 0.25)
	tween.tween_property(ball, "visible", true, 0.25)
	tween.tween_property(ball, "visible", false, 0.25)
	tween.tween_property(ball, "visible", true, 0.25)
	tween.tween_callback(ball.launch)


func _build_level() -> void:
	await spawn_bricks()
	await spawn_bricks()
	await spawn_bricks()
	await spawn_bricks()
	level_built = true


func add_row() -> void:
	adding_row = true
	await spawn_bricks()
	adding_row = false


func spawn_bricks() -> void:
	color_idx = wrapi(color_idx + 1, 0, color_palette.colors.size())
	var row: float = 13.5
	for col: int in range(-3,4,1):
		var brick: Brick = brick_scene.instantiate()
		brick.color = color_palette.colors.get(color_idx)
		bricks.add_child(brick)
		brick.global_position = Vector3(col, row, 0)

	for steps: int in range(30):
		for brick: Node3D in get_tree().get_nodes_in_group("Bricks"):
			if is_instance_valid(brick):
				brick.global_position.y -= 1/60.0
				if brick.global_position.y < 3:
					brick.queue_free()
		await get_tree().process_frame
