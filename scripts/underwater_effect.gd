extends CanvasLayer
## Underwater tint + native depth fog. Runtime-only; does not overwrite night.tres.

@export_group("Scene References")
@export var water_path: NodePath = ^"../Water"
@export var camera_path: NodePath = ^"../Player/Camera3D"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

@export_group("Submersion")
@export_range(0.05, 3.0, 0.05) var transition_depth: float = 0.7
@export_range(0.1, 10.0, 0.1) var fade_speed: float = 2.5

@export_group("Underwater Visibility")
@export_range(2.0, 30.0, 0.5) var underwater_visibility: float = 7.0
@export_range(0.0, 1.0, 0.05) var underwater_fog_opacity: float = 0.95
@export var underwater_fog_color: Color = Color("#061b30")
@export_range(0.0, 2.0, 0.05) var underwater_fog_energy: float = 0.65

@onready var overlay: ColorRect = $ColorRect
var _intensity: float = 0.0
var _environment_node: WorldEnvironment
var _runtime_environment: Environment
var _original_environment: Environment
var _base_fog_enabled: bool = false
var _base_fog_mode: Environment.FogMode = Environment.FOG_MODE_EXPONENTIAL
var _base_fog_density: float = 0.0
var _base_fog_begin: float = 0.0
var _base_fog_end: float = 0.0
var _base_fog_color: Color = Color.BLACK
var _base_fog_energy: float = 1.0
var _base_sky_affect: float = 0.0
var _base_fog_curve: float = 1.0

func _ready() -> void:
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.visible = false
    _environment_node = get_node_or_null(world_environment_path) as WorldEnvironment
    if _environment_node != null and _environment_node.environment != null:
        # Clone the loaded resource so your res://environment/night.tres is NEVER edited.
        _original_environment = _environment_node.environment
        _runtime_environment = _original_environment.duplicate(true) as Environment
        _base_fog_enabled = _original_environment.fog_enabled
        _base_fog_mode = _original_environment.fog_mode
        _base_fog_density = _original_environment.fog_density
        _base_fog_begin = _original_environment.fog_depth_begin
        _base_fog_end = _original_environment.fog_depth_end
        _base_fog_color = _original_environment.fog_light_color
        _base_fog_energy = _original_environment.fog_light_energy
        _base_sky_affect = _original_environment.fog_sky_affect
        _base_fog_curve = _original_environment.fog_depth_curve
        _environment_node.environment = _runtime_environment
    else:
        push_warning("UnderwaterEffect: WorldEnvironment missing; only screen tint will run.")
    set_process(true)

func _process(delta: float) -> void:
    var water: Node3D = get_node_or_null(water_path) as Node3D
    var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
    if water == null or camera == null:
        _apply_visuals(0.0, delta)
        return
    var surface_y: float = water.global_position.y
    var configured_level: Variant = water.get("water_level")
    if configured_level != null:
        surface_y = float(configured_level)
    var depth: float = surface_y - camera.global_position.y
    var target: float = clampf(depth / transition_depth, 0.0, 1.0)
    _apply_visuals(target, delta)

func _apply_visuals(target: float, delta: float) -> void:
    _intensity = move_toward(_intensity, target, fade_speed * delta)
    overlay.visible = _intensity > 0.001
    if overlay.material is ShaderMaterial:
        (overlay.material as ShaderMaterial).set_shader_parameter("submersion", _intensity)

    if _runtime_environment == null:
        return

    # Above water: restore EXACT original fog settings, including mode.
    if _intensity <= 0.001:
        _runtime_environment.fog_enabled = _base_fog_enabled
        _runtime_environment.fog_mode = _base_fog_mode
        _runtime_environment.fog_density = _base_fog_density
        _runtime_environment.fog_depth_begin = _base_fog_begin
        _runtime_environment.fog_depth_end = _base_fog_end
        _runtime_environment.fog_light_color = _base_fog_color
        _runtime_environment.fog_light_energy = _base_fog_energy
        _runtime_environment.fog_sky_affect = _base_sky_affect
        _runtime_environment.fog_depth_curve = _base_fog_curve
        return

    # Depth fog attenuates real 3D objects based on camera distance.
    _runtime_environment.fog_enabled = true
    _runtime_environment.fog_mode = Environment.FOG_MODE_DEPTH
    _runtime_environment.fog_depth_begin = lerpf(_base_fog_begin, 0.4, _intensity)
    _runtime_environment.fog_depth_end = lerpf(_base_fog_end, underwater_visibility, _intensity)
    _runtime_environment.fog_depth_curve = lerpf(_base_fog_curve, 1.0, _intensity)
    _runtime_environment.fog_density = lerpf(_base_fog_density, underwater_fog_opacity, _intensity)
    _runtime_environment.fog_light_color = _base_fog_color.lerp(underwater_fog_color, _intensity)
    _runtime_environment.fog_light_energy = lerpf(_base_fog_energy, underwater_fog_energy, _intensity)
    _runtime_environment.fog_sky_affect = lerpf(_base_sky_affect, 0.85, _intensity)

func _exit_tree() -> void:
    # Ensure the original saved resource is put back if the node is removed.
    if is_instance_valid(_environment_node) and _original_environment != null:
        _environment_node.environment = _original_environment
