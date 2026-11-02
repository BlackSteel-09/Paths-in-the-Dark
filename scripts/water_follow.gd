@tool
extends MeshInstance3D

@export_group("Water Surface")
@export var water_level: float = 0.0:
	set(value):
		water_level = value
		if is_inside_tree():
			_update_water_position()

@export_group("Follow Settings")
@export var follow_editor_camera: bool = true
@export var follow_player: bool = true
@export var player_path: NodePath = ^"../Player"

var _player: Node3D


func _ready() -> void:
	set_process(true)
	_update_water_position()


func _process(_delta: float) -> void:
	_update_water_position()


func _update_water_position() -> void:
	var target: Node3D = null

	if Engine.is_editor_hint():
		if not follow_editor_camera:
			return

		var editor_viewport := EditorInterface.get_editor_viewport_3d(0)

		if editor_viewport != null:
			target = editor_viewport.get_camera_3d()

	elif follow_player:
		if not is_instance_valid(_player):
			_player = get_node_or_null(player_path) as Node3D

		target = _player

	if target == null:
		return

	var new_position := Vector3(
		target.global_position.x,
		water_level,
		target.global_position.z
	)

	if global_position.distance_squared_to(new_position) > 0.0001:
		global_position = new_position
