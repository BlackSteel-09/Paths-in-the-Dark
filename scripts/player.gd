extends CharacterBody3D
## Stage 1 temporary first-person exploration controller.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity_strength: float = 20.0

@onready var camera: Camera3D = $Camera3D
var world: Node3D

func _ready() -> void:
	world = get_node("../World")
	global_position.y = world.get_height(global_position.x, global_position.z) + 0.08
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F1:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	input_dir = input_dir.normalized()
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	# Stage 1 safety floor: terrain chunks are generated at runtime.
	# Keep the player's feet above the same height used by the mesh.
	# This is a temporary fallback; the StaticBody3D collisions remain active.
	if is_instance_valid(world):
		var floor_height: float = world.get_height(global_position.x, global_position.z)
		if global_position.y < floor_height + 0.08:
			global_position.y = floor_height + 0.08
			if velocity.y < 0.0:
				velocity.y = 0.0
