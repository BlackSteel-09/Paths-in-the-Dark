@tool
extends Node3D
## Paths in the Dark — Module 2A. Editor-visible procedural tree silhouettes.
## Attach to a Node3D that is a sibling of World (under Main).
## Preview meshes are transient: they are regenerated instead of saved in the scene.
## Trees use the terrain's get_height(x,z), including in the editor.

@export_group("Preview")
@export var show_trees: bool = true:
	set(value):
		show_trees = value
		_request_rebuild()
@export_range(1, 12, 1) var tree_count: int = 5:
	set(value):
		tree_count = value
		_request_rebuild()
@export_range(3.0, 24.0, 0.5) var tree_spacing: float = 9.0:
	set(value):
		tree_spacing = value
		_request_rebuild()
@export var tree_seed: int = 133742:
	set(value):
		tree_seed = value
		_request_rebuild()
@export var world_path: NodePath = ^"../World":
	set(value):
		world_path = value
		_request_rebuild()
@export var follow_terrain: bool = true
@export_tool_button("Regenerate Trees") var regenerate_trees = _request_rebuild

@export_group("Tree Shapes")
@export_range(0.3, 3.0, 0.05) var overall_scale: float = 1.0:
	set(value):
		overall_scale = value
		_request_rebuild()
@export_range(0.5, 2.0, 0.05) var trunk_height_multiplier: float = 1.0:
	set(value):
		trunk_height_multiplier = value
		_request_rebuild()
@export_range(0.5, 2.0, 0.05) var canopy_radius_multiplier: float = 1.0:
	set(value):
		canopy_radius_multiplier = value
		_request_rebuild()
@export_range(0.0, 0.4, 0.01) var canopy_distortion: float = 0.15:
	set(value):
		canopy_distortion = value
		_request_rebuild()

@export_group("Colours")
@export var trunk_colour: Color = Color("241a1f"):
	set(value):
		trunk_colour = value
		_request_rebuild()
@export var leaf_colour: Color = Color("2c4030"):
	set(value):
		leaf_colour = value
		_request_rebuild()

var _queued: bool = false
var _generated_root: Node3D
var _last_xz: Vector2 = Vector2(INF, INF)
var _last_ground_signature: float = INF
var _last_world_seed: int = -2147483648

func _ready() -> void:
	if not is_inside_tree():
		return
	# Editor gizmo movement changes the parent transform, not an exported
	# property. Listen for actual transform notifications instead of waiting
	# for a property edit to trigger a rebuild.
	set_notify_transform(true)
	set_process(true)
	_ensure_root()
	_request_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# This fires immediately when the gallery node is moved in the editor.
		# Updating only the existing tree transforms avoids rebuilding meshes.
		if is_inside_tree() and is_instance_valid(_generated_root):
			_update_grounding()

func _process(_delta: float) -> void:
	if not show_trees or not is_inside_tree():
		return
	# Backup for terrain edits and parent transform changes. A tool script's
	# transform notification is the primary update path during gizmo drags.
	_update_grounding()

func _request_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	call_deferred("_rebuild")

func _ensure_root() -> void:
	if is_instance_valid(_generated_root):
		return
	_generated_root = get_node_or_null("GeneratedTrees") as Node3D
	if _generated_root == null:
		_generated_root = Node3D.new()
		_generated_root.name = "GeneratedTrees"
		add_child(_generated_root)

func _clear_preview() -> void:
	_ensure_root()
	for child in _generated_root.get_children():
		_generated_root.remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	_clear_preview()
	if not show_trees:
		return
	for i in range(tree_count):
		var rng := RandomNumberGenerator.new()
		rng.seed = (tree_seed + i * 7919) & 0x7fffffffffffffff
		var tree: Node3D = _build_tree(rng, i)
		_generated_root.add_child(tree)
	_update_grounding()

func _update_grounding() -> void:
	if not is_inside_tree() or not is_instance_valid(_generated_root):
		return
	var world: Node = get_node_or_null(world_path)
	var count: int = _generated_root.get_child_count()
	for i in range(count):
		var tree: Node3D = _generated_root.get_child(i) as Node3D
		if tree == null:
			continue
		var horizontal_offset: float = (float(i) - float(count - 1) / 2.0) * tree_spacing
		var wx: float = global_position.x + horizontal_offset
		var wz: float = global_position.z
		var wy: float = global_position.y
		if follow_terrain and world != null and world.has_method("get_height"):
			wy = float(world.call("get_height", wx, wz))
		# Place the tree's base at the terrain height, without moving the gallery root.
		var desired: Vector3 = to_local(Vector3(wx, wy, wz))
		if tree.position.distance_squared_to(desired) > 0.000001:
			tree.position = desired
	_last_xz = Vector2(global_position.x, global_position.z)
	_last_ground_signature = float(world.call("get_height", global_position.x, global_position.z)) if follow_terrain and world != null and world.has_method("get_height") else 0.0
	_last_world_seed = int(world.get("world_seed")) if world != null and world.get("world_seed") != null else 0

func _make_material(colour: Color, roughness_value: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness_value
	mat.metallic = 0.0
	return mat

func _build_tree(rng: RandomNumberGenerator, index: int) -> Node3D:
	var tree := Node3D.new()
	tree.name = "Tree_%02d" % (index + 1)
	var scale_factor: float = overall_scale * rng.randf_range(0.7, 1.4)
	var height: float = rng.randf_range(3.0, 5.0) * scale_factor * trunk_height_multiplier
	var trunk_mesh: ArrayMesh = _create_trunk_mesh(rng, height, scale_factor)
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = trunk_mesh
	trunk.material_override = _make_material(trunk_colour, 0.92)
	tree.add_child(trunk)
	var crown := MeshInstance3D.new()
	crown.name = "Canopy"
	crown.mesh = _create_canopy_mesh(rng, height, scale_factor)
	crown.material_override = _make_material(leaf_colour, 0.82)
	tree.add_child(crown)
	tree.rotation.y = rng.randf_range(0.0, TAU)
	return tree

func _create_trunk_mesh(rng: RandomNumberGenerator, height: float, scale_factor: float) -> ArrayMesh:
	# Original geometry: six radial sides, 3 vertical segments, tapered trunk.
	var rings: Array[PackedVector3Array] = []
	for j in range(4):
		var ring := PackedVector3Array()
		var t: float = float(j) / 3.0
		var radius: float = lerpf(0.6, 0.3, t) * scale_factor
		for k in range(6):
			var angle: float = TAU * float(k) / 6.0
			var x: float = cos(angle) * radius + rng.randf_range(-0.04, 0.04) * scale_factor
			var z: float = sin(angle) * radius + rng.randf_range(-0.04, 0.04) * scale_factor
			ring.append(Vector3(x, t * height, z))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(3):
		for k in range(6):
			var next: int = (k + 1) % 6
			var a: Vector3 = rings[j][k]
			var b: Vector3 = rings[j][next]
			var c: Vector3 = rings[j + 1][k]
			var d: Vector3 = rings[j + 1][next]
			# Outward-facing geometry in Godot's clockwise winding convention.
			_triangle(surface, a, b, c)
			_triangle(surface, b, d, c)
	for k in range(6):
		var next: int = (k + 1) % 6
		_triangle(surface, Vector3(0.0, 0.0, 0.0), rings[0][next], rings[0][k])
		_triangle(surface, Vector3(0.0, height, 0.0), rings[3][k], rings[3][next])
	surface.generate_normals()
	return surface.commit()

func _create_canopy_mesh(rng: RandomNumberGenerator, height: float, scale_factor: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blob_count: int = rng.randi_range(3, 5)
	var blob_radius: float = rng.randf_range(1.8, 2.6) * scale_factor * canopy_radius_multiplier
	for i in range(blob_count):
		var radius: float = blob_radius * rng.randf_range(0.8, 1.2)
		var angle: float = float(i) / float(blob_count) * TAU + rng.randf()
		var distance: float = rng.randf() * 1.0 * scale_factor
		var center := Vector3(cos(angle) * distance, height + 1.0 * scale_factor + rng.randf() * scale_factor, sin(angle) * distance)
		_add_icosphere_blob(surface, center, radius, rng)
	surface.generate_normals()
	return surface.commit()

func _add_icosphere_blob(surface: SurfaceTool, center: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	# Icosahedron subdivided once, corresponding to THREE.IcosahedronGeometry(r, 1).
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var vertices: Array[Vector3] = [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1)
	]
	for i in range(vertices.size()):
		vertices[i] = vertices[i].normalized()
	var faces := PackedInt32Array([
		0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11,
		1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
		3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9,
		4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1
	])
	# Subdivision midpoints are cached per original edge to avoid seams.
	var cache: Dictionary = {}
	var subdivided: Array[PackedInt32Array] = []
	for f in range(0, faces.size(), 3):
		var a: int = faces[f]
		var b: int = faces[f + 1]
		var c: int = faces[f + 2]
		var ab: int = _midpoint(vertices, cache, a, b)
		var bc: int = _midpoint(vertices, cache, b, c)
		var ca: int = _midpoint(vertices, cache, c, a)
		subdivided.append(PackedInt32Array([a, ab, ca]))
		subdivided.append(PackedInt32Array([b, bc, ab]))
		subdivided.append(PackedInt32Array([c, ca, bc]))
		subdivided.append(PackedInt32Array([ab, bc, ca]))
	var distorted: Array[Vector3] = []
	for v in vertices:
		var base: Vector3 = v * radius
		var ripple: float = 1.0 + sin(base.x * 2.5) * canopy_distortion + cos(base.y * 3.0) * canopy_distortion * 0.8 + sin(base.z * 2.0) * canopy_distortion * 0.65
		ripple += rng.randf_range(-0.025, 0.025)
		distorted.append(center + base * ripple)
	for face in subdivided:
		# Reverse source face order for Godot's visible front-facing surfaces.
		_triangle(surface, distorted[face[0]], distorted[face[2]], distorted[face[1]])

func _midpoint(vertices: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var key: Vector2i = Vector2i(lo, hi)
	if cache.has(key):
		return int(cache[key])
	var index: int = vertices.size()
	vertices.append((vertices[a] + vertices[b]).normalized())
	cache[key] = index
	return index

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
