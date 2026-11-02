@tool
extends Node3D
## Paths in the Dark — Stage 2D. Grass streaming for editor and runtime.
## Standalone system. Does not modify terrain, forest, player or native environment.
## Put under Main at position (0,0,0), alongside World.

const CHUNK_SIZE: int = 32
const GRASS_SHADER = preload("res://shaders/procedural_grass.gdshader")

@export_group("Grass")
@export var grass_enabled: bool = true:
    set(value):
        grass_enabled = value
        _queue_rebuild()
@export_range(0.0, 4.0, 0.05, "or_greater") var density_multiplier: float = 1.0:
    set(value):
        density_multiplier = value
        _queue_rebuild()
@export_range(0, 6000, 100, "or_greater") var max_candidates_per_chunk: int = 2100:
    set(value):
        max_candidates_per_chunk = value
        _queue_rebuild()
@export var grass_seed: int = 133742:
    set(value):
        grass_seed = value
        _queue_rebuild()
@export var terrain_path: NodePath = ^"../World":
    set(value):
        terrain_path = value
        _queue_rebuild()

@export_group("Terrain Filter")
@export var minimum_height: float = 0.3:
    set(value):
        minimum_height = value
        _queue_rebuild()
@export var maximum_height: float = 15.0:
    set(value):
        maximum_height = value
        _queue_rebuild()
@export_range(0.05, 2.0, 0.05, "or_greater") var maximum_slope: float = 0.6:
    set(value):
        maximum_slope = value
        _queue_rebuild()

@export_group("Appearance")
@export var grass_color: Color = Color("33503a"):
    set(value):
        grass_color = value
        _update_shader_settings()
@export_range(0.1, 3.0, 0.05, "or_greater") var height_multiplier: float = 1.0:
    set(value):
        height_multiplier = value
        _queue_rebuild()
@export_range(0.1, 4.0, 0.05, "or_greater") var width_multiplier: float = 1.0:
    set(value):
        width_multiplier = value
        _queue_rebuild()
@export_range(0.0, 1.0, 0.05) var color_variation: float = 0.25:
    set(value):
        color_variation = value
        _update_shader_settings()

@export_group("Wind & Growth")
@export_range(0.0, 1.5, 0.05) var wind_strength: float = 0.3:
    set(value):
        wind_strength = value
        _update_shader_settings()
@export_range(0.0, 8.0, 0.1) var wind_speed: float = 2.0:
    set(value):
        wind_speed = value
        _update_shader_settings()
@export_range(0.1, 8.0, 0.1, "or_greater") var growth: float = 1.0:
    set(value):
        growth = value
        _update_shader_settings()

@export_group("Optional Patchiness")
@export var enable_patchiness: bool = false:
    set(value):
        enable_patchiness = value
        _queue_rebuild()
@export_range(0.005, 0.15, 0.001) var patch_frequency: float = 0.035:
    set(value):
        patch_frequency = value
        _queue_rebuild()
@export_range(-0.8, 0.8, 0.05) var patch_threshold: float = -0.25:
    set(value):
        patch_threshold = value
        _queue_rebuild()

@export_group("Streaming & Editor")
@export var preview_in_editor: bool = true:
    set(value):
        preview_in_editor = value
        _queue_rebuild()
@export var follow_editor_camera: bool = true
@export_range(0, 10, 1, "or_greater") var editor_radius: int = 2:
    set(value):
        editor_radius = value
        _queue_rebuild()
@export_range(0, 10, 1, "or_greater") var runtime_radius: int = 2:
    set(value):
        runtime_radius = value
        _queue_rebuild()
@export_range(1, 8, 1) var chunks_per_frame: int = 1
@export_tool_button("Rebuild Grass") var rebuild_grass = _queue_rebuild

var _root: Node3D
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _last_center: Vector2i = Vector2i(999999, 999999)
var _last_terrain_seed: int = -999999999
var _queued_rebuild: bool = false
var _grass_mesh: ArrayMesh
var _grass_material: ShaderMaterial
var _patch_noise: FastNoiseLite

func _ready() -> void:
    _ensure_root()
    _build_resources()
    _setup_patch_noise()
    _queue_rebuild()

func _ensure_root() -> void:
    if is_instance_valid(_root):
        return
    _root = get_node_or_null("GrassChunks") as Node3D
    if _root == null:
        _root = Node3D.new()
        _root.name = "GrassChunks"
        add_child(_root)

func _queue_rebuild() -> void:
    if not is_inside_tree() or _queued_rebuild:
        return
    _queued_rebuild = true
    call_deferred("_rebuild")

func _rebuild() -> void:
    _queued_rebuild = false
    if not is_inside_tree():
        return
    _ensure_root()
    for child in _root.get_children():
        _root.remove_child(child)
        child.queue_free()
    _chunks.clear()
    _pending.clear()
    _last_center = Vector2i(999999, 999999)
    _setup_patch_noise()
    _build_resources()

func _setup_patch_noise() -> void:
    _patch_noise = FastNoiseLite.new()
    _patch_noise.seed = grass_seed + 751
    _patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    _patch_noise.frequency = patch_frequency

func _build_resources() -> void:
    _grass_mesh = _make_crossed_blades()
    _grass_material = ShaderMaterial.new()
    _grass_material.shader = GRASS_SHADER
    _update_shader_settings()

func _update_shader_settings() -> void:
    if _grass_material == null:
        return
    _grass_material.set_shader_parameter("grass_color", grass_color)
    _grass_material.set_shader_parameter("wind_strength", wind_strength)
    _grass_material.set_shader_parameter("wind_speed", wind_speed)
    _grass_material.set_shader_parameter("growth", growth)
    _grass_material.set_shader_parameter("color_variation", color_variation)

func _make_crossed_blades() -> ArrayMesh:
    # Four triangles per crossed tuft. Godot shader uses double-sided rendering.
    # Each face has a broad base and a tapered tip; UV.y controls wind strength.
    var vertices := PackedVector3Array()
    var uv := PackedVector2Array()
    var indices := PackedInt32Array()
    for axis in range(2):
        var base: int = vertices.size()
        if axis == 0:
            vertices.append_array(PackedVector3Array([
                Vector3(-0.05, 0.0, 0.0), Vector3(0.05, 0.0, 0.0),
                Vector3(0.04, 0.55, 0.025), Vector3(0.0, 1.0, 0.03)
            ]))
        else:
            vertices.append_array(PackedVector3Array([
                Vector3(0.0, 0.0, -0.05), Vector3(0.0, 0.0, 0.05),
                Vector3(0.025, 0.55, 0.04), Vector3(0.03, 1.0, 0.0)
            ]))
        uv.append_array(PackedVector2Array([
            Vector2(0.0, 0.0), Vector2(1.0, 0.0),
            Vector2(0.8, 0.55), Vector2(0.5, 1.0)
        ]))
        indices.append_array(PackedInt32Array([
            base, base + 1, base + 2,
            base, base + 2, base + 3
        ]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uv
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _process(_delta: float) -> void:
    if Engine.is_editor_hint() and not preview_in_editor:
        return
    if not grass_enabled:
        return
    var terrain: Node = get_node_or_null(terrain_path)
    if terrain == null or not terrain.has_method("get_height"):
        return
    var current_seed: int = int(terrain.get("world_seed"))
    if current_seed != _last_terrain_seed:
        _last_terrain_seed = current_seed
        _queue_rebuild()
        return
    var focus: Vector3 = _get_focus_position()
    var center := Vector2i(floori((focus.x + 16.0) / 32.0), floori((focus.z + 16.0) / 32.0))
    var radius: int = maxi(0, editor_radius if Engine.is_editor_hint() else runtime_radius)
    if center != _last_center:
        _refresh_queue(center, radius)
    for i in range(chunks_per_frame):
        if _pending.is_empty():
            break
        var key: Vector2i = _pending.pop_front()
        _build_chunk(key, terrain)

func _get_focus_position() -> Vector3:
    if Engine.is_editor_hint():
        if follow_editor_camera:
            var viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0)
            if viewport != null:
                var camera: Camera3D = viewport.get_camera_3d()
                if camera != null:
                    return camera.global_position
        return global_position
    var player: Node3D = get_node_or_null("../Player") as Node3D
    return player.global_position if player != null else global_position

func _refresh_queue(center: Vector2i, radius: int) -> void:
    _last_center = center
    _pending.clear()
    for x in range(center.x - radius, center.x + radius + 1):
        for z in range(center.y - radius, center.y + radius + 1):
            var key := Vector2i(x, z)
            if not _chunks.has(key):
                _pending.append(key)
    _pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        return (a - center).length_squared() < (b - center).length_squared()
    )
    for key in _chunks.keys():
        var offset: Vector2i = key - center
        if absi(offset.x) > radius + 1 or absi(offset.y) > radius + 1:
            var old: Node3D = _chunks[key]
            _chunks.erase(key)
            _root.remove_child(old)
            old.queue_free()

func _chunk_rng(cx: int, cz: int) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    var seed_code: int = grass_seed ^ (cx * 73856093) ^ (cz * 19349663) ^ 3000007
    rng.seed = seed_code & 0x7fffffffffffffff
    return rng

func _patch_acceptance(x: float, z: float) -> float:
    if not enable_patchiness:
        return 1.0
    var n: float = _patch_noise.get_noise_2d(x, z)
    return smoothstep(patch_threshold - 0.2, patch_threshold + 0.2, n)

func _build_chunk(key: Vector2i, terrain: Node) -> void:
    if _chunks.has(key):
        return
    var rng := _chunk_rng(key.x, key.y)
    var count: int = mini(max_candidates_per_chunk, maxi(0, floori(1024.0 * 1.8 * density_multiplier)))
    if count == 0:
        _chunks[key] = _make_chunk_node(key)
        return
    var transforms: Array[Transform3D] = []
    var custom_colors: Array[Color] = []
    var min_y: float = INF
    var max_y: float = -INF
    for i in range(count):
        # Centred 32-unit chunks matching the World mesh geometry.
        var lx: float = rng.randf_range(-16.0, 16.0)
        var lz: float = rng.randf_range(-16.0, 16.0)
        var wx: float = float(key.x * CHUNK_SIZE) + lx
        var wz: float = float(key.y * CHUNK_SIZE) + lz
        if rng.randf() > _patch_acceptance(wx, wz):
            continue
        var y: float = float(terrain.call("get_height", wx, wz))
        if y <= minimum_height or y >= maximum_height:
            continue
        var dx: float = float(terrain.call("get_height", wx + 1.0, wz)) - y
        var dz: float = float(terrain.call("get_height", wx, wz + 1.0)) - y
        if Vector2(dx, dz).length() >= maximum_slope:
            continue
        var yaw: float = rng.randf_range(0.0, TAU)
        var scale_y: float = height_multiplier * rng.randf_range(0.55, 1.50)
        var basis := Basis(Vector3.UP, yaw).scaled(Vector3(width_multiplier, scale_y, width_multiplier))
        transforms.append(Transform3D(basis, Vector3(lx, y, lz)))
        custom_colors.append(Color(rng.randf(), rng.randf(), 0.0, 1.0))
        min_y = minf(min_y, y)
        max_y = maxf(max_y, y)
    var chunk_node: Node3D = _make_chunk_node(key)
    _chunks[key] = chunk_node
    if transforms.is_empty():
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_custom_data = true
    mm.mesh = _grass_mesh
    mm.instance_count = transforms.size()
    for i in range(transforms.size()):
        mm.set_instance_transform(i, transforms[i])
        mm.set_instance_custom_data(i, custom_colors[i])
    # Extend bounds to cover wind and future supernatural growth.
    mm.custom_aabb = AABB(Vector3(-19.0, min_y - 2.0, -19.0), Vector3(38.0, max_y - min_y + 15.0, 38.0))
    var draw := MultiMeshInstance3D.new()
    draw.name = "GrassInstances"
    draw.multimesh = mm
    draw.material_override = _grass_material
    chunk_node.add_child(draw)

func _make_chunk_node(key: Vector2i) -> Node3D:
    var node := Node3D.new()
    node.name = "Grass_%d_%d" % [key.x, key.y]
    node.position = Vector3(float(key.x * CHUNK_SIZE), 0.0, float(key.y * CHUNK_SIZE))
    _root.add_child(node)
    return node
