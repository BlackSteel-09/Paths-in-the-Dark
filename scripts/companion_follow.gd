@tool
extends CharacterBody3D
## Paths in the Dark - Companion 3C.2
## Stateful social companion with decision persistence; no scene or player changes.

enum FollowMode { FOLLOW, WAIT, SCRIPTED }
enum Behaviour { IDLE, REACTION_DELAY, FOLLOW, SETTLE, CATCH_UP, WAITING, SCRIPTED_MOVE }
enum Formation { LEFT_SIDE, RIGHT_SIDE, LEFT_REAR, RIGHT_REAR, TRAIL, SLIGHT_AHEAD }
enum IdleFacing { PLAYER, TRAVEL, AWAY }

@export_group("References")
@export var player_path: NodePath = ^"../Player"
@export var world_path: NodePath = ^"../World"

@export_group("Commands")
@export var mode: FollowMode = FollowMode.FOLLOW
@export var allow_shift_e_debug_wait: bool = true
@export var spawn_beside_player: bool = true

@export_group("Personality - Formation")
@export_range(2.0, 90.0, 0.5) var formation_hold_min: float = 12.0
@export_range(2.0, 120.0, 0.5) var formation_hold_max: float = 28.0
@export_range(0.5, 4.0, 0.05) var side_min: float = 1.15
@export_range(0.5, 5.0, 0.05) var side_max: float = 2.25
@export_range(0.0, 4.0, 0.05) var rear_min: float = 0.25
@export_range(0.0, 6.0, 0.05) var rear_max: float = 1.65
@export_range(0.0, 1.0, 0.05) var left_side_preference: float = 0.55
@export_range(0.0, 1.0, 0.05) var ahead_chance: float = 0.04
@export_range(0.0, 1.0, 0.05) var trail_chance: float = 0.20

@export_group("Personality - Timing")
@export_range(0.0, 3.0, 0.05) var reaction_delay_min: float = 0.25
@export_range(0.0, 4.0, 0.05) var reaction_delay_max: float = 1.15
@export_range(0.0, 5.0, 0.05) var settle_delay_min: float = 0.35
@export_range(0.0, 6.0, 0.05) var settle_delay_max: float = 1.3
@export_range(2.0, 40.0, 0.5) var idle_decision_min: float = 6.0
@export_range(2.0, 60.0, 0.5) var idle_decision_max: float = 15.0
@export_range(0.0, 1.0, 0.05) var idle_reposition_chance: float = 0.20
@export_range(0.2, 2.0, 0.1) var idle_reposition_distance: float = 0.85

@export_group("Position / Safety")
@export_range(0.5, 4.0, 0.05) var comfort_min: float = 1.15
@export_range(1.0, 6.0, 0.05) var comfort_max: float = 2.95
@export_range(1.5, 8.0, 0.05) var start_moving_distance: float = 3.5
@export_range(3.0, 20.0, 0.25) var catchup_distance: float = 7.0
@export_range(10.0, 100.0, 0.5) var teleport_distance: float = 34.0
@export_range(0.1, 1.5, 0.05) var stop_distance: float = 0.42
@export var avoid_occupied_formation: bool = true
@export var avoid_water_formations: bool = true
@export_range(-20.0, 20.0, 0.1) var water_level: float = 0.0
@export_range(0.0, 4.0, 0.1) var max_formation_height_difference: float = 1.8

@export_group("Movement")
@export_range(0.5, 15.0, 0.1) var walk_speed: float = 6.5
@export_range(1.0, 20.0, 0.1) var catchup_speed: float = 12.025
@export_range(0.5, 8.0, 0.1) var settling_speed: float = 3.2
@export_range(1.0, 30.0, 0.5) var acceleration: float = 11.0
@export_range(1.0, 30.0, 0.5) var braking: float = 14.0
@export var gravity_strength: float = 18.0
@export var terrain_safety_fallback: bool = true
@export var terrain_clearance: float = 0.08
@export_range(0.3, 12.0, 0.1) var face_turn_speed: float = 5.0

@export_group("Personality - Facing")
@export_range(0.0, 1.0, 0.05) var face_player_weight: float = 0.45
@export_range(0.0, 1.0, 0.05) var face_travel_weight: float = 0.35
@export_range(0.0, 6.0, 0.1) var max_idle_face_distance: float = 4.0

@export_group("Debug")
@export var show_debug_visual: bool = true:
    set(value):
        show_debug_visual = value
        if is_inside_tree():
            _apply_debug_visibility()
@export var show_facing_arrow: bool = true:
    set(value):
        show_facing_arrow = value
        if is_inside_tree():
            _apply_debug_visibility()
@export var print_state_changes: bool = false

var _player: Node3D
var _world: Node
var _visual: Node3D
var _arrow: Node3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state: Behaviour = Behaviour.IDLE
var _formation: Formation = Formation.LEFT_SIDE
var _idle_facing: IdleFacing = IdleFacing.TRAVEL
var _formation_timer: float = 0.0
var _reaction_timer: float = 0.0
var _settle_timer: float = 0.0
var _idle_timer: float = 0.0
var _idle_target: Vector3 = Vector3.ZERO
var _idle_repositioning: bool = false
var _side_offset: float = 1.5
var _rear_offset: float = 0.5
var _last_player_position: Vector3 = Vector3.ZERO
var _player_was_moving: bool = false
var _last_travel_forward: Vector3 = Vector3.FORWARD
var _script_target: Vector3 = Vector3.ZERO
var _script_speed: float = 3.2

func _ready() -> void:
    _visual = get_node_or_null("DebugVisual") as Node3D
    _arrow = get_node_or_null("DebugVisual/FacingArrow") as Node3D
    _apply_debug_visibility()
    if Engine.is_editor_hint():
        set_physics_process(false)
        return
    _rng.randomize()
    _player = get_node_or_null(player_path) as Node3D
    _world = get_node_or_null(world_path)
    if not is_instance_valid(_player):
        push_warning("Companion: Player not found at " + str(player_path))
        set_physics_process(false)
        return
    _last_player_position = _player.global_position
    _choose_formation(true)
    _set_idle_timer()
    floor_snap_length = 0.4
    if spawn_beside_player:
        global_position = _grounded_point(_formation_point())

func _unhandled_input(event: InputEvent) -> void:
    if Engine.is_editor_hint() or not allow_shift_e_debug_wait:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and Input.is_key_pressed(KEY_SHIFT):
            if mode == FollowMode.WAIT:
                resume_following()
            else:
                wait_here()
            get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint() or not is_instance_valid(_player):
        return
    var player_pos: Vector3 = _player.global_position
    var player_vel: Vector3 = (player_pos - _last_player_position) / maxf(delta, 0.001)
    player_vel.y = 0.0
    var player_speed: float = player_vel.length()
    var player_moving: bool = player_speed > 0.45
    if player_speed > 0.8:
        _last_travel_forward = player_vel.normalized()
    _last_player_position = player_pos

    var desired: Vector3 = global_position
    var target_speed: float = 0.0
    var gap_to_player: float = _flat_distance(global_position, player_pos)

    if mode == FollowMode.WAIT:
        _set_state(Behaviour.WAITING)
    elif mode == FollowMode.SCRIPTED:
        _set_state(Behaviour.SCRIPTED_MOVE)
        desired = _script_target
        target_speed = _script_speed
    else:
        if gap_to_player > teleport_distance:
            _choose_formation(true)
            global_position = _grounded_point(_formation_point())
            velocity = Vector3.ZERO
            _set_state(Behaviour.IDLE)
            _player_was_moving = player_moving
            return

        if gap_to_player > catchup_distance:
            _reaction_timer = 0.0
            _idle_repositioning = false
            _set_state(Behaviour.CATCH_UP)
        elif player_moving and not _player_was_moving:
            _reaction_timer = _random_range(reaction_delay_min, reaction_delay_max)
            _idle_repositioning = false
            _set_state(Behaviour.REACTION_DELAY)
        elif not player_moving and _player_was_moving:
            _settle_timer = _random_range(settle_delay_min, settle_delay_max)
            _set_state(Behaviour.SETTLE)
            _set_idle_timer()

        if _state == Behaviour.CATCH_UP and gap_to_player < catchup_distance * 0.58:
            _set_state(Behaviour.FOLLOW if player_moving else Behaviour.SETTLE)
        if _state == Behaviour.REACTION_DELAY:
            _reaction_timer -= delta
            if _reaction_timer <= 0.0 or gap_to_player > catchup_distance * 0.75:
                _set_state(Behaviour.FOLLOW)
        if _state == Behaviour.SETTLE:
            _settle_timer -= delta
            if _settle_timer <= 0.0:
                _set_state(Behaviour.FOLLOW if player_moving else Behaviour.IDLE)

        if _state == Behaviour.FOLLOW and not player_moving:
            if gap_to_player >= comfort_min and gap_to_player <= comfort_max:
                _set_state(Behaviour.IDLE)
            elif gap_to_player <= start_moving_distance and _flat_distance(global_position, _formation_point()) < stop_distance:
                _set_state(Behaviour.IDLE)
        if _state == Behaviour.IDLE and (player_moving and gap_to_player > start_moving_distance):
            _set_state(Behaviour.FOLLOW)
        if _state == Behaviour.IDLE and not player_moving:
            _idle_timer -= delta
            if _idle_timer <= 0.0:
                _choose_idle_decision()
                _set_idle_timer()

        _formation_timer -= delta
        if _formation_timer <= 0.0 and _state != Behaviour.CATCH_UP and _state != Behaviour.REACTION_DELAY:
            _choose_formation(false)

        match _state:
            Behaviour.FOLLOW:
                desired = _formation_point()
                target_speed = walk_speed
                if gap_to_player > 3.5:
                    target_speed = minf(catchup_speed, walk_speed + (gap_to_player - 3.5) * 0.75)
            Behaviour.CATCH_UP:
                desired = _formation_point()
                target_speed = catchup_speed
            Behaviour.SETTLE:
                if gap_to_player > comfort_max:
                    desired = _formation_point()
                    target_speed = settling_speed
            Behaviour.IDLE:
                if gap_to_player > start_moving_distance:
                    desired = _formation_point()
                    target_speed = settling_speed
                elif _idle_repositioning:
                    desired = _idle_target
                    target_speed = settling_speed
                    if _flat_distance(global_position, desired) <= stop_distance:
                        _idle_repositioning = false
            _:
                pass

    _move_toward_target(desired, target_speed, delta)
    if target_speed <= 0.01 or _flat_distance(global_position, desired) < stop_distance:
        _turn_idle(delta)
    _player_was_moving = player_moving

func _move_toward_target(target: Vector3, max_speed: float, delta: float) -> void:
    var diff: Vector3 = target - global_position
    diff.y = 0.0
    var distance: float = diff.length()
    var desired_h: Vector3 = Vector3.ZERO
    if max_speed > 0.0 and distance > stop_distance:
        var speed: float = minf(max_speed, distance * 2.6)
        desired_h = diff / distance * speed
    var current_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
    var response: float = acceleration if desired_h.length_squared() > current_h.length_squared() else braking
    current_h = current_h.move_toward(desired_h, response * delta)
    velocity.x = current_h.x
    velocity.z = current_h.z
    if current_h.length() > 0.28:
        _turn_to(current_h, delta)
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= gravity_strength * delta
    move_and_slide()
    if terrain_safety_fallback and _has_world_height():
        var min_height: float = float(_world.call("get_height", global_position.x, global_position.z)) + terrain_clearance
        if global_position.y < min_height:
            global_position.y = min_height
            velocity.y = maxf(0.0, velocity.y)

func _choose_formation(force: bool) -> void:
    if not is_instance_valid(_player):
        return
    var candidates: Array[int] = []
    var is_left: bool = _rng.randf() < left_side_preference
    if _rng.randf() < ahead_chance:
        candidates.append(Formation.SLIGHT_AHEAD)
    elif _rng.randf() < trail_chance:
        candidates.append(Formation.TRAIL)
    else:
        candidates.append(Formation.LEFT_SIDE if is_left else Formation.RIGHT_SIDE)
        candidates.append(Formation.LEFT_REAR if is_left else Formation.RIGHT_REAR)
    candidates.append(Formation.RIGHT_REAR if is_left else Formation.LEFT_REAR)
    candidates.append(Formation.TRAIL)
    var candidate_side: float = _random_range(side_min, side_max)
    var candidate_rear: float = _random_range(rear_min, rear_max)
    for candidate in candidates:
        var point: Vector3 = _formation_point_for(candidate, candidate_side, candidate_rear)
        if _is_formation_safe(point):
            _formation = candidate
            _side_offset = candidate_side
            _rear_offset = candidate_rear
            break
    _formation_timer = _random_range(formation_hold_min, formation_hold_max)
    if force:
        _idle_repositioning = false

func _is_formation_safe(point: Vector3) -> bool:
    if _has_world_height():
        var elevation: float = float(_world.call("get_height", point.x, point.z))
        if avoid_water_formations and elevation < water_level + 0.1:
            return false
        if absf(elevation - float(_world.call("get_height", _player.global_position.x, _player.global_position.z))) > max_formation_height_difference:
            return false
    if avoid_occupied_formation and is_inside_tree() and get_world_3d() != null:
        var params := PhysicsShapeQueryParameters3D.new()
        var shape := SphereShape3D.new()
        shape.radius = 0.34
        params.shape = shape
        var check_y: float = float(_world.call("get_height", point.x, point.z)) if _has_world_height() else point.y
        params.transform = Transform3D(Basis(), Vector3(point.x, check_y + 0.9, point.z))
        params.collision_mask = collision_mask
        params.exclude = [get_rid()]
        var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(params, 1)
        if not hits.is_empty():
            return false
    return true

func _formation_point_for(which: Formation, side: float, rear: float) -> Vector3:
    var forward: Vector3 = -_player.global_transform.basis.z
    forward.y = 0.0
    forward = forward.normalized()
    var right: Vector3 = _player.global_transform.basis.x
    right.y = 0.0
    right = right.normalized()
    var offset: Vector3 = Vector3.ZERO
    match which:
        Formation.LEFT_SIDE: offset = -right * side - forward * 0.25
        Formation.RIGHT_SIDE: offset = right * side - forward * 0.25
        Formation.LEFT_REAR: offset = -right * side * 0.75 - forward * rear
        Formation.RIGHT_REAR: offset = right * side * 0.75 - forward * rear
        Formation.TRAIL: offset = -forward * maxf(1.7, rear + 0.85)
        Formation.SLIGHT_AHEAD: offset = right * side * 0.85 + forward * 0.65
    return _player.global_position + offset

func _formation_point() -> Vector3:
    return _formation_point_for(_formation, _side_offset, _rear_offset)

func _choose_idle_decision() -> void:
    var r: float = _rng.randf()
    if r < idle_reposition_chance:
        var a: float = _rng.randf_range(-PI, PI)
        var direction := Vector3(cos(a), 0.0, sin(a))
        var target := global_position + direction * _rng.randf_range(0.5, idle_reposition_distance)
        if _is_formation_safe(target) and _flat_distance(target, _player.global_position) <= comfort_max:
            _idle_target = target
            _idle_repositioning = true
        return
    _idle_repositioning = false
    var turn_chance: float = _rng.randf()
    if turn_chance < face_player_weight:
        _idle_facing = IdleFacing.PLAYER
    elif turn_chance < face_player_weight + face_travel_weight:
        _idle_facing = IdleFacing.TRAVEL
    else:
        _idle_facing = IdleFacing.AWAY

func _turn_idle(delta: float) -> void:
    if not is_instance_valid(_player):
        return
    var face: Vector3 = _last_travel_forward
    if _idle_facing == IdleFacing.PLAYER and _flat_distance(global_position, _player.global_position) < max_idle_face_distance:
        face = _player.global_position - global_position
    elif _idle_facing == IdleFacing.AWAY:
        face = -_last_travel_forward
    _turn_to(face, delta)

func _turn_to(direction: Vector3, delta: float) -> void:
    direction.y = 0.0
    if direction.length_squared() < 0.0001:
        return
    rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, face_turn_speed * delta))

func _set_state(next: Behaviour) -> void:
    if _state == next:
        return
    _state = next
    if print_state_changes:
        print("Companion state: ", Behaviour.keys()[_state], " / formation ", Formation.keys()[_formation])

func _set_idle_timer() -> void:
    _idle_timer = _random_range(idle_decision_min, idle_decision_max)

func _random_range(a: float, b: float) -> float:
    return _rng.randf_range(minf(a, b), maxf(a, b))

func _grounded_point(point: Vector3) -> Vector3:
    if _has_world_height():
        point.y = float(_world.call("get_height", point.x, point.z)) + terrain_clearance
    else:
        point.y = _player.global_position.y if is_instance_valid(_player) else point.y
    return point

func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()

func _has_world_height() -> bool:
    return is_instance_valid(_world) and _world.has_method("get_height")

func _apply_debug_visibility() -> void:
    if not is_instance_valid(_visual):
        _visual = get_node_or_null("DebugVisual") as Node3D
    if _visual != null:
        _visual.visible = show_debug_visual
    if not is_instance_valid(_arrow):
        _arrow = get_node_or_null("DebugVisual/FacingArrow") as Node3D
    if _arrow != null:
        _arrow.visible = show_facing_arrow

## Stable public API, used by eventual story and dialogue code.
func wait_here() -> void:
    mode = FollowMode.WAIT
    _idle_repositioning = false

func resume_following() -> void:
    mode = FollowMode.FOLLOW
    _reaction_timer = 0.0
    _choose_formation(true)
    _set_state(Behaviour.FOLLOW)

func go_to_position(world_position: Vector3, speed: float = 3.2) -> void:
    _script_target = world_position
    _script_speed = maxf(0.1, speed)
    mode = FollowMode.SCRIPTED

func set_companion_visible(enabled: bool) -> void:
    visible = enabled
    set_physics_process(enabled)
    set_collision_layer_value(2, enabled)
