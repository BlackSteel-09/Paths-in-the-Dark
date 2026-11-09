@tool
extends Node
## Editor-only terrain following for the parent Node3D.
## Move the parent with the normal 3D gizmo:
##   X/Z: follow procedural terrain, keeping the current relative height.
##   Y: change the relative height (sink/raise), without snapping back.
## Rotation is never modified. Does nothing during gameplay.

@export var enabled: bool = true
@export var vertical_offset: float = 0.0
@export var world_path: NodePath = ^"../../World"

const EPSILON: float = 0.0001

var _target: Node3D
var _world: Node
var _initialized: bool = false
var _last_written_y: float = 0.0
var _last_offset: float = 0.0


func _ready() -> void:
    if not Engine.is_editor_hint():
        set_process(false)
        return
    _target = get_parent() as Node3D
    _last_offset = vertical_offset
    set_process(true)


func _process(_delta: float) -> void:
    if not Engine.is_editor_hint() or not enabled:
        return
    if not is_instance_valid(_target):
        _target = get_parent() as Node3D
    if _target == null:
        return
    if not is_instance_valid(_world) or not _world.has_method("get_height"):
        _world = _find_world()
    if _world == null:
        return

    var position_now: Vector3 = _target.global_position
    var terrain_y: float = float(_world.call("get_height", position_now.x, position_now.z))

    if not _initialized:
        _initialized = true
        # A newly dropped scene normally starts at Y=0: snap it once.
        # An already positioned scene retains its saved global Y and
        # reconstructs its offset from the terrain height on reopening.
        if absf(position_now.y) > EPSILON:
            vertical_offset = position_now.y - terrain_y
        _last_offset = vertical_offset
        _write_height(terrain_y + vertical_offset)
        return

    # Inspector edits to Vertical Offset continue to work, too.
    if absf(vertical_offset - _last_offset) > EPSILON:
        _last_offset = vertical_offset
        _write_height(terrain_y + vertical_offset)
        return

    # A changed Y since our last automatic placement is a manual gizmo
    # adjustment. Record the new terrain-relative offset rather than
    # replacing the user's adjustment.
    if absf(position_now.y - _last_written_y) > EPSILON:
        vertical_offset = position_now.y - terrain_y
        _last_offset = vertical_offset
        _last_written_y = position_now.y
        EditorInterface.mark_scene_as_unsaved()
        return

    # X/Z movement or terrain changes: follow ground, retain offset.
    var desired_y: float = terrain_y + vertical_offset
    if absf(position_now.y - desired_y) > EPSILON:
        _write_height(desired_y)


func _write_height(desired_y: float) -> void:
    var p: Vector3 = _target.global_position
    if absf(p.y - desired_y) > EPSILON:
        p.y = desired_y
        _target.global_position = p
        EditorInterface.mark_scene_as_unsaved()
    _last_written_y = desired_y


func _find_world() -> Node:
    # Preserve the old explicit path for scenes already configured with it.
    var candidate: Node = get_node_or_null(world_path)
    if candidate != null and candidate.has_method("get_height"):
        return candidate

    # Fallback for assets placed deeper under Locations or other containers.
    var ancestor: Node = get_parent()
    while ancestor != null:
        if ancestor.has_method("get_height"):
            return ancestor
        candidate = ancestor.get_node_or_null("World")
        if candidate != null and candidate.has_method("get_height"):
            return candidate
        ancestor = ancestor.get_parent()

    var root: Node = get_tree().edited_scene_root
    if root != null:
        candidate = root.find_child("World", true, false)
        if candidate != null and candidate.has_method("get_height"):
            return candidate
    return null
