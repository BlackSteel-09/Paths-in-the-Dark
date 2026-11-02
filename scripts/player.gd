extends CharacterBody3D
## Paths in the Dark — Module 3A first-person controller.
## Attach to existing Player (CharacterBody3D); requires child Camera3D.
## TerrainGrounder remains editor-only and does not conflict at runtime.

@export_group("Movement — Original Feel")
@export var walk_speed: float = 6.5
@export var sprint_multiplier: float = 1.85
@export var acceleration_response: float = 13.5
@export var deceleration_response: float = 7.2
@export var gravity_strength: float = 18.0
@export var floor_snap_distance: float = 0.35
@export var max_slope_angle: float = 46.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0022
@export var keyboard_turn_speed: float = 1.65
@export var eye_height: float = 1.7
@export var pitch_limit_degrees: float = 83.0
@export var capture_mouse_on_start: bool = true

@export_group("Head Bob")
@export var head_bob_enabled: bool = true
@export var walk_bob_amplitude: float = 0.034
@export var sprint_bob_amplitude: float = 0.052
@export var bob_frequency: float = 9.0
@export var bob_return_speed: float = 9.0

@export_group("World & Safety")
@export var world_path: NodePath = ^"../World"
@export var use_height_safety_fallback: bool = true
@export var height_safety_margin: float = 0.08
@export var place_on_ground_at_start: bool = true

@export_group("Debug Flight")
@export var allow_debug_flight: bool = true
@export var flight_vertical_speed: float = 7.5

@onready var camera: Camera3D = $Camera3D
var _world: Node = null
var _camera_base_position: Vector3
var _bob_phase: float = 0.0
var _bob_offset: float = 0.0
var _controls_locked: bool = false
var _flight_active: bool = false

func _ready() -> void:
	_world = get_node_or_null(world_path)
	_camera_base_position = camera.position
	_camera_base_position.y = eye_height
	camera.position = _camera_base_position
	floor_snap_length = floor_snap_distance
	floor_max_angle = deg_to_rad(max_slope_angle)
	if place_on_ground_at_start and _has_world_height():
		global_position.y = _height_at(global_position.x, global_position.z) + height_safety_margin
	if capture_mouse_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if _controls_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(
			camera.rotation.x - event.relative.y * mouse_sensitivity,
			-deg_to_rad(pitch_limit_degrees),
			deg_to_rad(pitch_limit_degrees)
		)

func _physics_process(delta: float) -> void:
	var direction_input := Vector2.ZERO
	var sprinting := false

	if not _controls_locked:
		if Input.is_key_pressed(KEY_A):
			direction_input.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			direction_input.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			direction_input.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			direction_input.y += 1.0
		if Input.is_key_pressed(KEY_LEFT):
			rotate_y(keyboard_turn_speed * delta)
		if Input.is_key_pressed(KEY_RIGHT):
			rotate_y(-keyboard_turn_speed * delta)
		sprinting = Input.is_key_pressed(KEY_SHIFT)

	direction_input = direction_input.normalized()
	var world_direction: Vector3 = global_transform.basis * Vector3(direction_input.x, 0.0, direction_input.y)
	world_direction.y = 0.0
	world_direction = world_direction.normalized()
	var desired_speed: float = walk_speed * (sprint_multiplier if sprinting else 1.0)
	var desired_horizontal: Vector3 = world_direction * desired_speed
	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var response: float = acceleration_response if direction_input.length_squared() > 0.0 else deceleration_response
	var blend: float = 1.0 - exp(-response * delta)
	current_horizontal = current_horizontal.lerp(desired_horizontal, blend)
	velocity.x = current_horizontal.x
	velocity.z = current_horizontal.z

	if allow_debug_flight and not _controls_locked and Input.is_key_pressed(KEY_Q):
		_flight_active = true
		if sprinting:
			velocity.y = flight_vertical_speed
		else:
			velocity.y -= gravity_strength * delta
	elif _flight_active:
		velocity.y = 0.0
	elif is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= gravity_strength * delta

	move_and_slide()

	# Existing project has streamed procedural terrain. Preserve a selectable
	# safety floor until all terrain collision seams are verified.
	if use_height_safety_fallback and not _flight_active and _has_world_height():
		var ground_y: float = _height_at(global_position.x, global_position.z)
		if global_position.y < ground_y + height_safety_margin:
			global_position.y = ground_y + height_safety_margin
			if velocity.y < 0.0:
				velocity.y = 0.0

	if _flight_active and _has_world_height():
		var surface_y: float = _height_at(global_position.x, global_position.z)
		if global_position.y <= surface_y + height_safety_margin:
			global_position.y = surface_y + height_safety_margin
			_flight_active = false
			velocity.y = 0.0

	_update_head_bob(delta, current_horizontal.length(), sprinting)

func _update_head_bob(delta: float, horizontal_speed: float, sprinting: bool) -> void:
	var moving: bool = horizontal_speed > 0.15 and not _controls_locked and not _flight_active
	var target: float = 0.0
	if head_bob_enabled and moving:
		_bob_phase += delta * bob_frequency * (horizontal_speed / maxf(walk_speed, 0.01))
		var amplitude: float = sprint_bob_amplitude if sprinting else walk_bob_amplitude
		target = absf(sin(_bob_phase)) * amplitude
	var alpha: float = 1.0 - exp(-bob_return_speed * delta)
	_bob_offset = lerpf(_bob_offset, target, alpha)
	camera.position = _camera_base_position + Vector3(0.0, _bob_offset, 0.0)

func _has_world_height() -> bool:
	return is_instance_valid(_world) and _world.has_method("get_height")

func _height_at(x: float, z: float) -> float:
	return float(_world.call("get_height", x, z))

func set_story_controls_locked(locked: bool) -> void:
	_controls_locked = locked
	if locked:
		velocity.x = 0.0
		velocity.z = 0.0

func are_story_controls_locked() -> bool:
	return _controls_locked
