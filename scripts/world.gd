@tool
extends Node3D
## Stage 1D: editor camera driven terrain streaming; native Godot atmosphere remains untouched.
## Noise is an approximation of the original Three.js custom seeded noise.

@export_group("Terrain")
@export var world_seed: int = 133742:
	set(value):
		world_seed = value
		_request_editor_rebuild()
const CHUNK_SIZE: int = 32
@export_range(8, 64, 8) var chunk_segments: int = 32:
	set(value):
		chunk_segments = value
		_request_editor_rebuild()
@export var view_radius: int = 2
@export var water_level: float = 0.0:
	set(value):
		water_level = value
		_request_editor_rebuild()

@export_group("Editor Preview")
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		_request_editor_rebuild()
@export var preview_radius: int = 2:
	set(value):
		preview_radius = value
		_request_editor_rebuild()
@export var follow_editor_camera: bool = true:
	set(value):
		follow_editor_camera = value
		_request_editor_rebuild()
@export_range(1, 8, 1) var preview_chunks_per_frame: int = 2
@export_tool_button("Refresh Terrain Preview") var refresh_preview = _request_editor_rebuild

var _preview_rebuild_queued: bool = false

func _request_editor_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview_rebuild_queued:
		return
	_preview_rebuild_queued = true
	call_deferred("_rebuild_editor_preview")

func _rebuild_editor_preview() -> void:
	_preview_rebuild_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_clear_generated_chunks()
	if not preview_in_editor:
		return
	_setup_noise()
	_setup_material()
	_editor_update_center()

func _get_editor_camera_position() -> Vector3:
	if not follow_editor_camera:
		return global_position
	var viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if viewport != null:
		var editor_camera: Camera3D = viewport.get_camera_3d()
		if editor_camera != null:
			return editor_camera.global_position
	return global_position

func _editor_update_center() -> void:
	var center: Vector2i = world_to_chunk(_get_editor_camera_position())
	if center != last_center:
		_refresh_chunks(center, maxi(0, preview_radius))

func _clear_generated_chunks() -> void:
	chunks.clear()
	pending_chunks.clear()
	last_center = Vector2i(999999, 999999)
	if is_instance_valid(chunk_root):
		# Detach immediately, defer deletion for editor safety.
		remove_child(chunk_root)
		chunk_root.queue_free()
	chunk_root = Node3D.new()
	chunk_root.name = "TerrainChunks"
	add_child(chunk_root)

var continent_noise: FastNoiseLite
var local_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var chunks: Dictionary = {}
var pending_chunks: Array[Vector2i] = []
var player: Node3D
var chunk_root: Node3D
var last_center: Vector2i = Vector2i(999999, 999999)
var ground_material: StandardMaterial3D

func _ready() -> void:
	_setup_noise()
	_setup_material()
	chunk_root = get_node_or_null("TerrainChunks") as Node3D
	if not is_instance_valid(chunk_root):
		chunk_root = Node3D.new()
		chunk_root.name = "TerrainChunks"
		add_child(chunk_root)
	if Engine.is_editor_hint():
		_request_editor_rebuild()
		return
	# Runtime behaviour remains identical: stream around player.
	player = get_node_or_null("../Player") as Node3D
	_refresh_chunks(world_to_chunk(player.global_position) if player != null else Vector2i.ZERO, maxi(0, view_radius))
	_build_next_chunk(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if not preview_in_editor:
			return
		_editor_update_center()
		for i in range(preview_chunks_per_frame):
			if pending_chunks.is_empty():
				break
			_build_next_chunk(false)
		return
	if player == null:
		return
	var center: Vector2i = world_to_chunk(player.global_position)
	if center != last_center:
		_refresh_chunks(center, maxi(0, view_radius))
	if not pending_chunks.is_empty():
		_build_next_chunk(true)

func _setup_noise() -> void:
	continent_noise = _new_noise(world_seed, 0.0025)
	local_noise = _new_noise(world_seed + 19, 0.015)
	detail_noise = _new_noise(world_seed + 37, 0.035)

func _new_noise(seed_value: int, frequency_value: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency_value
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n

func get_height(x: float, z: float) -> float:
	var continent := continent_noise.get_noise_2d(x + 152000.0, z - 84000.0) * 8.0
	var local_h := local_noise.get_noise_2d(x, z) * 7.0
	var detail := detail_noise.get_noise_2d(x + 2857.0, z + 2857.0) * 2.5
	var hill := sin(x * 0.004) * cos(z * 0.004) * 2.5
	return 3.0 + continent + local_h + detail + hill

func world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x + CHUNK_SIZE * 0.5) / CHUNK_SIZE), floori((pos.z + CHUNK_SIZE * 0.5) / CHUNK_SIZE))

func _refresh_chunks(center: Vector2i, radius: int) -> void:
	last_center = center
	pending_chunks.clear()
	for x in range(center.x - radius, center.x + radius + 1):
		for z in range(center.y - radius, center.y + radius + 1):
			var key: Vector2i = Vector2i(x, z)
			if not chunks.has(key):
				pending_chunks.append(key)
	pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared()
	)
	for key in chunks.keys():
		var offset: Vector2i = key - center
		if absi(offset.x) > radius + 1 or absi(offset.y) > radius + 1:
			var old: Node3D = chunks[key]
			chunks.erase(key)
			old.queue_free()

func _build_next_chunk(with_collision: bool) -> void:
	if pending_chunks.is_empty():
		return
	var key: Vector2i = pending_chunks.pop_front()
	if chunks.has(key):
		return
	_build_chunk(key, with_collision)

func _build_chunk(key: Vector2i, with_collision: bool) -> void:
	var origin_x := float(key.x * CHUNK_SIZE)
	var origin_z := float(key.y * CHUNK_SIZE)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var resolution := chunk_segments + 1
	var step := float(CHUNK_SIZE) / float(chunk_segments)
	for zi in range(resolution):
		for xi in range(resolution):
			var lx := -CHUNK_SIZE * 0.5 + float(xi) * step
			var lz := -CHUNK_SIZE * 0.5 + float(zi) * step
			var wx := origin_x + lx
			var wz := origin_z + lz
			var h := get_height(wx, wz)
			verts.append(Vector3(lx, h, lz))
			var e := 0.5
			var nx := get_height(wx - e, wz) - get_height(wx + e, wz)
			var nz := get_height(wx, wz - e) - get_height(wx, wz + e)
			normals.append(Vector3(nx, e * 2.0, nz).normalized())
			colors.append(_ground_color(h, wx, wz))
	for zi in range(chunk_segments):
		for xi in range(chunk_segments):
			var a := zi * resolution + xi
			var b := a + 1
			var c := a + resolution
			var d := c + 1
			# Godot front faces use clockwise winding; previous order faced downward.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh.surface_set_material(0, ground_material)
	var body := StaticBody3D.new()
	body.name = "Chunk_%s_%s" % [key.x, key.y]
	body.position = Vector3(origin_x, 0.0, origin_z)
	var visual := MeshInstance3D.new()
	visual.name = "Ground"
	visual.mesh = terrain_mesh
	body.add_child(visual)
	if with_collision:
		var collision := CollisionShape3D.new()
		collision.name = "TerrainCollision"
		collision.shape = terrain_mesh.create_trimesh_shape()
		body.add_child(collision)
	chunk_root.add_child(body)
	chunks[key] = body

func _ground_color(height_value: float, x: float, z: float) -> Color:
	var variation := detail_noise.get_noise_2d(x + 444.0, z + 444.0) * 0.065
	if height_value < water_level:
		return Color(0.17, 0.12, 0.23).lightened(variation + 0.05)
	var elevation := clampf(height_value / 14.0, 0.0, 1.0)
	return Color(
	0.045 + elevation * 0.025 + variation,
	0.105 - elevation * 0.012 + variation,
	0.090 + elevation * 0.018 + variation
)

func _setup_material() -> void:
	ground_material = StandardMaterial3D.new()
	ground_material.vertex_color_use_as_albedo = true
	ground_material.roughness = 1.0
	ground_material.metallic = 0.0
