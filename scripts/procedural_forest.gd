@tool
extends Node3D
## Paths in the Dark — 2B. Seeded ambient forests with coherent groves and clearings.
## Requires the existing Stage 2A procedural_tree_gallery.gd and Stage 1D World.
## Keep Forest as a sibling of World under Main. Generated nodes are temporary.

const TREE_BUILDER = preload("res://scripts/procedural_tree_gallery.gd")
const CHUNK_SIZE: int = 32

@export_group("Forest")
@export var forest_enabled: bool = true:
	set(v): forest_enabled = v; _queue_full_rebuild()
@export_range(0.0, 3.0, 0.05, "or_greater") var density_multiplier: float = 1.0:
	set(v): density_multiplier = v; _queue_full_rebuild()
@export_range(0, 32, 1, "or_greater") var max_trees_per_chunk: int = 12:
	set(v): max_trees_per_chunk = v; _queue_full_rebuild()
@export var forest_seed: int = 133742:
	set(v): forest_seed = v; _queue_full_rebuild()
@export var terrain_path: NodePath = ^"../World":
	set(v): terrain_path = v; _queue_full_rebuild()

@export_group("Clustering")
@export var enable_clustering: bool = true:
	set(v): enable_clustering = v; _queue_full_rebuild()
@export_range(0.001, 0.05, 0.001) var grove_frequency: float = 0.008:
	set(v): grove_frequency = v; _queue_full_rebuild()
@export_range(-0.8, 0.8, 0.02) var grove_threshold: float = -0.12:
	set(v): grove_threshold = v; _queue_full_rebuild()
@export_range(0.05, 0.7, 0.01) var grove_edge_softness: float = 0.28:
	set(v): grove_edge_softness = v; _queue_full_rebuild()
@export_range(0.0, 1.0, 0.05) var local_patchiness: float = 0.35:
	set(v): local_patchiness = v; _queue_full_rebuild()
@export_range(0.0, 4.0, 0.1) var minimum_spacing: float = 1.8:
	set(v): minimum_spacing = v; _queue_full_rebuild()

@export_group("Terrain Filter")
@export var minimum_height: float = 0.5:
	set(v): minimum_height = v; _queue_full_rebuild()
@export var maximum_height: float = 20.0:
	set(v): maximum_height = v; _queue_full_rebuild()
@export_range(0.1, 2.0, 0.05) var maximum_slope: float = 0.6:
	set(v): maximum_slope = v; _queue_full_rebuild()

@export_group("Tree Appearance")
@export_range(1, 24, 1) var tree_variants: int = 8:
	set(v): tree_variants = v; _queue_full_rebuild(true)
@export_range(0.3, 2.0, 0.05) var tree_scale: float = 1.0:
	set(v): tree_scale = v; _queue_full_rebuild()
@export var bark_color: Color = Color("241a1f"):
	set(v): bark_color = v; _queue_full_rebuild(true)
@export var foliage_color: Color = Color("2c4030"):
	set(v): foliage_color = v; _queue_full_rebuild(true)
@export_range(0.5, 2.0, 0.05) var trunk_height: float = 1.0:
	set(v): trunk_height = v; _queue_full_rebuild(true)
@export_range(0.5, 2.0, 0.05) var canopy_size: float = 1.0:
	set(v): canopy_size = v; _queue_full_rebuild(true)
@export_range(0.0, 0.4, 0.01) var canopy_irregularity: float = 0.15:
	set(v): canopy_irregularity = v; _queue_full_rebuild(true)

@export_group("Tree Collision")
## Collisions are enabled at runtime only by default; editor geometry stays light.
@export var collision_enabled: bool = true:
	set(v):
		collision_enabled = v
		_request_collision_refresh()
@export_range(2.0, 100.0, 1.0, "or_greater") var collision_distance: float = 24.0:
	set(v):
		collision_distance = maxf(0.0, v)
		_request_collision_refresh()
@export_range(0.2, 1.5, 0.05) var trunk_collision_radius_multiplier: float = 0.85:
	set(v):
		trunk_collision_radius_multiplier = v
		_request_collision_refresh()
@export_flags_3d_physics var collision_layer: int = 1:
	set(v):
		collision_layer = v
		_request_collision_refresh()
@export var collision_in_editor: bool = false:
	set(v):
		collision_in_editor = v
		_request_collision_refresh()

@export_group("Streaming")
@export_range(0, 12, 1, "or_greater") var editor_radius: int = 2:
	set(v): editor_radius = v; _queue_full_rebuild()
@export_range(0, 12, 1, "or_greater") var runtime_radius: int = 2
@export_range(1, 8, 1) var chunks_per_frame: int = 2
@export var follow_editor_camera: bool = true
@export var preview_in_editor: bool = true:
	set(v): preview_in_editor = v; _queue_full_rebuild()
@export_tool_button("Rebuild Forest") var rebuild_forest = _queue_full_rebuild

var _root: Node3D
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _last_center: Vector2i = Vector2i(999999, 999999)
var _last_terrain_seed: int = -999999999
var _grove_noise: FastNoiseLite
var _patch_noise: FastNoiseLite
var _variant_trunks: Array[Mesh] = []
var _variant_crowns: Array[Mesh] = []
var _bark_material: StandardMaterial3D
var _foliage_material: StandardMaterial3D
var _rebuild_queued: bool = false
var _rebuild_meshes: bool = true
var _tree_placements: Dictionary = {} # Vector2i -> Array[Dictionary], world coords + variant + scale
var _collision_bodies: Dictionary = {} # Vector2i -> StaticBody3D
var _collision_elapsed: float = 1.0
var _force_collision_update: bool = true


func _ready() -> void:
	_ensure_root()
	_setup_noises()
	_build_variants()
	set_process(true)
	_queue_full_rebuild()

func _ensure_root() -> void:
	if is_instance_valid(_root):
		return
	_root = get_node_or_null("ForestChunks") as Node3D
	if _root == null:
		_root = Node3D.new()
		_root.name = "ForestChunks"
		add_child(_root)

func _queue_full_rebuild(rebuild_meshes: bool = false) -> void:
	_rebuild_meshes = _rebuild_meshes or rebuild_meshes
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_full_rebuild")

func _full_rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_ensure_root()
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()
	_chunks.clear()
	_tree_placements.clear()
	_collision_bodies.clear()
	_force_collision_update = true
	_pending.clear()
	_last_center = Vector2i(999999, 999999)
	_setup_noises()
	if _rebuild_meshes or _variant_trunks.is_empty():
		_build_variants()
	_rebuild_meshes = false

func _setup_noises() -> void:
	_grove_noise = FastNoiseLite.new()
	_grove_noise.seed = forest_seed + 51
	_grove_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_grove_noise.frequency = grove_frequency
	_grove_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_grove_noise.fractal_octaves = 2
	_patch_noise = FastNoiseLite.new()
	_patch_noise.seed = forest_seed + 113
	_patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch_noise.frequency = 0.038

func _build_variants() -> void:
	_variant_trunks.clear()
	_variant_crowns.clear()
	var builder: Node3D = TREE_BUILDER.new()
	builder.set("trunk_colour", bark_color)
	builder.set("leaf_colour", foliage_color)
	builder.set("trunk_height_multiplier", trunk_height)
	builder.set("canopy_radius_multiplier", canopy_size)
	builder.set("canopy_distortion", canopy_irregularity)
	builder.set("overall_scale", 1.0)
	for i in range(tree_variants):
		var rng := RandomNumberGenerator.new()
		rng.seed = (forest_seed + 7919 * i + 314159) & 0x7fffffffffffffff
		var prototype: Node3D = builder.call("_build_tree", rng, i)
		var trunk: MeshInstance3D = prototype.get_node("Trunk") as MeshInstance3D
		var crown: MeshInstance3D = prototype.get_node("Canopy") as MeshInstance3D
		_variant_trunks.append(trunk.mesh)
		_variant_crowns.append(crown.mesh)
		prototype.free()
	builder.free()
	_bark_material = StandardMaterial3D.new()
	_bark_material.albedo_color = bark_color
	_bark_material.roughness = 0.92
	_foliage_material = StandardMaterial3D.new()
	_foliage_material.albedo_color = foliage_color
	_foliage_material.roughness = 0.82

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	if not forest_enabled:
		return
	var terrain: Node = get_node_or_null(terrain_path)
	if terrain == null or not terrain.has_method("get_height"):
		return
	var seed_value: int = int(terrain.get("world_seed"))
	if seed_value != _last_terrain_seed:
		_last_terrain_seed = seed_value
		_queue_full_rebuild()
		return
	var camera_position: Vector3 = _get_focus_position()
	var center: Vector2i = Vector2i(floori((camera_position.x + 16.0) / 32.0), floori((camera_position.z + 16.0) / 32.0))
	var radius: int = maxi(0, editor_radius if Engine.is_editor_hint() else runtime_radius)
	if center != _last_center:
		_refresh_queue(center, radius)
	for i in range(chunks_per_frame):
		if _pending.is_empty():
			break
		_build_chunk(_pending.pop_front(), terrain)
	_update_nearby_collisions(delta)

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
		var delta: Vector2i = key - center
		if absi(delta.x) > radius + 1 or absi(delta.y) > radius + 1:
			var old: Node3D = _chunks[key]
			_chunks.erase(key)
			_tree_placements.erase(key)
			_collision_bodies.erase(key)
			old.queue_free()

func _chunk_rng(cx: int, cz: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_code: int = forest_seed ^ (cx * 73856093) ^ (cz * 19349663) ^ 2000003
	rng.seed = seed_code & 0x7fffffffffffffff
	return rng

func _density_mask(x: float, z: float) -> float:
	if not enable_clustering:
		return 1.0
	var large: float = _grove_noise.get_noise_2d(x, z)
	var smooth: float = smoothstep(grove_threshold - grove_edge_softness, grove_threshold + grove_edge_softness, large)
	var small: float = _patch_noise.get_noise_2d(x, z)
	var patch: float = lerpf(1.0, clampf(0.8 + small * 1.1, 0.1, 1.4), local_patchiness)
	return clampf(smooth * patch, 0.0, 1.0)

func _build_chunk(key: Vector2i, terrain: Node) -> void:
	if _chunks.has(key) or not forest_enabled or _variant_trunks.is_empty():
		return
	var rng := _chunk_rng(key.x, key.y)
	var candidates: int = mini(max_trees_per_chunk, maxi(0, roundi((12.0 + float(rng.randi_range(-1, 1))) * density_multiplier)))
	var placements: Array[Vector3] = []
	var variants: Array[int] = []
	var yaw_angles: Array[float] = []
	var scales: Array[float] = []
	for i in range(candidates):
		var wx: float = float(key.x * CHUNK_SIZE) + rng.randf_range(-16.0, 16.0)
		var wz: float = float(key.y * CHUNK_SIZE) + rng.randf_range(-16.0, 16.0)
		if rng.randf() > _density_mask(wx, wz):
			continue
		var y: float = float(terrain.call("get_height", wx, wz))
		if y <= minimum_height or y >= maximum_height:
			continue
		var sx: float = (float(terrain.call("get_height", wx + 1.0, wz)) - float(terrain.call("get_height", wx - 1.0, wz))) * 0.5
		var sz: float = (float(terrain.call("get_height", wx, wz + 1.0)) - float(terrain.call("get_height", wx, wz - 1.0))) * 0.5
		if Vector2(sx, sz).length() > maximum_slope:
			continue
		var too_close: bool = false
		for other in placements:
			if Vector2(wx - other.x, wz - other.z).length_squared() < minimum_spacing * minimum_spacing:
				too_close = true
				break
		if too_close:
			continue
		placements.append(Vector3(wx, y, wz))
		variants.append(rng.randi_range(0, tree_variants - 1))
		yaw_angles.append(rng.randf_range(0.0, TAU))
		scales.append(tree_scale * rng.randf_range(0.7, 1.4))
	var chunk_node := Node3D.new()
	chunk_node.name = "Forest_%d_%d" % [key.x, key.y]
	_root.add_child(chunk_node)
	_chunks[key] = chunk_node
	var tree_data: Array[Dictionary] = []
	for i in range(placements.size()):
		tree_data.append({"position": placements[i], "variant": variants[i], "scale": scales[i]})
	_tree_placements[key] = tree_data
	_force_collision_update = true
	for v in range(tree_variants):
		var transforms: Array[Transform3D] = []
		for i in range(placements.size()):
			if variants[i] != v:
				continue
			var basis := Basis(Vector3.UP, yaw_angles[i]).scaled(Vector3.ONE * scales[i])
			transforms.append(Transform3D(basis, placements[i]))
		if transforms.is_empty():
			continue
		_add_instances(chunk_node, _variant_trunks[v], _bark_material, transforms, "Trunks_%d" % v)
		_add_instances(chunk_node, _variant_crowns[v], _foliage_material, transforms, "Crowns_%d" % v)

func _add_instances(parent: Node3D, mesh: Mesh, material: Material, transforms: Array[Transform3D], label: String) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var instanced := MultiMeshInstance3D.new()
	instanced.name = label
	instanced.multimesh = multimesh
	instanced.material_override = material
	parent.add_child(instanced)


# Physics objects are deliberately NOT MultiMesh instances. One StaticBody3D per
# chunk holds a small number of cylinder shapes near the player. Distant tree
# meshes remain rendered without physics objects.
func _request_collision_refresh() -> void:
	_force_collision_update = true
	_collision_elapsed = 1.0
	if is_inside_tree():
		call_deferred("_refresh_collisions_after_setting_change")

func _refresh_collisions_after_setting_change() -> void:
	if not is_inside_tree():
		return
	_clear_collisions()
	_force_collision_update = true

func _clear_collisions() -> void:
	for key in _collision_bodies.keys():
		var body: StaticBody3D = _collision_bodies[key]
		if is_instance_valid(body):
			body.collision_layer = 0
			body.collision_mask = 0
			if body.get_parent() != null:
				body.get_parent().remove_child(body)
			body.queue_free()
	_collision_bodies.clear()

func _update_nearby_collisions(delta: float) -> void:
	_collision_elapsed += delta
	if not _force_collision_update and _collision_elapsed < 0.2:
		return
	_collision_elapsed = 0.0
	_force_collision_update = false
	if not collision_enabled or (Engine.is_editor_hint() and not collision_in_editor):
		if not _collision_bodies.is_empty():
			_clear_collisions()
		return
	var focus: Vector3 = _get_focus_position()
	var max_dist_sq: float = collision_distance * collision_distance
	for key in _tree_placements.keys():
		var trees: Array[Dictionary] = _tree_placements[key]
		var nearby: Array[Dictionary] = []
		for tree in trees:
			var pos: Vector3 = tree["position"]
			var dx: float = pos.x - focus.x
			var dz: float = pos.z - focus.z
			if dx * dx + dz * dz <= max_dist_sq:
				nearby.append(tree)
		var old_body: StaticBody3D = _collision_bodies.get(key) as StaticBody3D
		if nearby.is_empty():
			if is_instance_valid(old_body):
				_remove_chunk_collision(key)
			continue
		# Recreate only when nearby trunk membership changes. Distances are checked
		# frequently, but the physics hierarchy is not rebuilt every frame.
		if is_instance_valid(old_body) and old_body.get_meta("tree_count", -1) == nearby.size():
			var positions: Array = old_body.get_meta("tree_positions", [])
			var same: bool = positions.size() == nearby.size()
			if same:
				for i in range(nearby.size()):
					if positions[i] != nearby[i]["position"]:
						same = false
						break
			if same:
				continue
		if is_instance_valid(old_body):
			_remove_chunk_collision(key)
		_create_chunk_collision(key, nearby)

func _remove_chunk_collision(key: Vector2i) -> void:
	var body: StaticBody3D = _collision_bodies.get(key) as StaticBody3D
	_collision_bodies.erase(key)
	if is_instance_valid(body):
		body.collision_layer = 0
		body.collision_mask = 0
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		body.queue_free()

func _create_chunk_collision(key: Vector2i, nearby: Array[Dictionary]) -> void:
	var chunk_node: Node3D = _chunks.get(key) as Node3D
	if not is_instance_valid(chunk_node):
		return
	var body := StaticBody3D.new()
	body.name = "TreeTrunkCollisions"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	chunk_node.add_child(body)
	var world_positions: Array[Vector3] = []
	for tree in nearby:
		var pos: Vector3 = tree["position"]
		var variant_idx: int = tree["variant"]
		var scale_factor: float = tree["scale"]
		var bounds: AABB = _variant_trunks[variant_idx].get_aabb()
		var height: float = maxf(0.4, bounds.size.y * scale_factor)
		var radius: float = maxf(0.15, maxf(bounds.size.x, bounds.size.z) * 0.5 * scale_factor * trunk_collision_radius_multiplier)
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = maxf(height, 2.0 * radius)
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position = body.to_local(pos + Vector3.UP * (cylinder.height * 0.5))
		body.add_child(shape)
		world_positions.append(pos)
	body.set_meta("tree_count", nearby.size())
	body.set_meta("tree_positions", world_positions)
	_collision_bodies[key] = body
