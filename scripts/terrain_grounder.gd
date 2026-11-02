@tool
extends Node
## Attach as a CHILD of a Node3D you want grounded in the editor.
## Place the grounded object under Main, as a sibling of World.
## Does not run during gameplay. The object's origin/pivot is treated as its ground point.

@export var enabled: bool = true
@export var vertical_offset: float = 0.0
@export var world_path: NodePath = ^"../../World"

func _process(_delta: float) -> void:
    if not Engine.is_editor_hint() or not enabled:
        return
    var target: Node3D = get_parent() as Node3D
    if target == null:
        return
    var world: Node = get_node_or_null(world_path)
    if world == null or not world.has_method("get_height"):
        return
    var world_pos: Vector3 = target.global_position
    var desired_y: float = float(world.call("get_height", world_pos.x, world_pos.z)) + vertical_offset
    if absf(world_pos.y - desired_y) > 0.0001:
        world_pos.y = desired_y
        target.global_position = world_pos
