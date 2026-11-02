extends Control
## Only screen navigation and startup logic live here.
## All labels, buttons, positions, colours and fonts are editable in the .tscn scenes.

@export_file("*.tscn") var world_scene_path: String = "res://scenes/main.tscn"
@export_multiline var intro_text: String = "An eclipse is on the rise. We have to get back before our forces leave for the capital."
@export_range(0.005, 0.2, 0.001) var intro_letter_seconds: float = 0.042

@onready var menu_backdrop: ColorRect = $MenuBackdrop
@onready var boot: Control = $Boot
@onready var title_screen: Control = $Title
@onready var act_screen: Control = $Acts
@onready var intro_screen: Control = $Intro
@onready var intro_label: Label = $Intro/IntroText

var _world: Node = null
var _player: Node = null
var _companion: Node = null
var _screen: String = "boot"
var _busy: bool = false
var _load_failed: bool = false


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    boot.show()
    title_screen.hide()
    act_screen.hide()
    intro_screen.hide()

    $Title/Content/Play.pressed.connect(_show_acts)
    $Acts/Content/Act1/Select.pressed.connect(_begin_act_one)
    $Acts/Content/Back.pressed.connect(_show_title)

    var err: Error = ResourceLoader.load_threaded_request(world_scene_path)
    if err != OK:
        _show_error("Cannot load scene: " + world_scene_path)
        return
    set_process(true)


func _process(_delta: float) -> void:
    if _screen != "boot" or _load_failed:
        return
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(world_scene_path)
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        set_process(false)
        _complete_boot()
    elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        _show_error("Failed to load: " + world_scene_path)


func _complete_boot() -> void:
    var packed: PackedScene = ResourceLoader.load_threaded_get(world_scene_path) as PackedScene
    if packed == null:
        _show_error("Invalid world scene: " + world_scene_path)
        return

    _world = packed.instantiate()
    add_child(_world)
    move_child(_world, 0)
    _player = _world.get_node_or_null("Player")
    _companion = _world.get_node_or_null("Companion")

    if _player != null:
        if _player.has_method("set_story_controls_locked"):
            _player.call("set_story_controls_locked", true)
        _player.set_physics_process(false)
        _player.set_process_unhandled_input(false)

    if _companion != null:
        _companion.set_physics_process(false)
        _companion.set_process(false)
        if _companion.has_method("set_companion_visible"):
            _companion.call("set_companion_visible", false)
        elif _companion is Node3D:
            (_companion as Node3D).visible = false
        elif _companion is CanvasItem:
            (_companion as CanvasItem).visible = false

    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    # The procedural world is allowed a few frames to begin its own startup.
    # This is not a guarantee that every terrain chunk has finished generating.
    await get_tree().process_frame
    await get_tree().process_frame
    if not is_inside_tree():
        return

    _screen = "title"
    title_screen.modulate.a = 0.0
    title_screen.show()
    var tween: Tween = create_tween()
    tween.tween_property(boot, "modulate:a", 0.0, 0.8)
    tween.parallel().tween_property(title_screen, "modulate:a", 1.0, 0.9)
    await tween.finished
    boot.hide()


func _show_acts() -> void:
    if _busy:
        return
    _busy = true
    var tween: Tween = create_tween()
    tween.tween_property(title_screen, "modulate:a", 0.0, 0.65)
    await tween.finished
    title_screen.hide()
    act_screen.modulate.a = 0.0
    act_screen.show()
    _screen = "acts"
    tween = create_tween()
    tween.tween_property(act_screen, "modulate:a", 1.0, 0.65)
    await tween.finished
    _busy = false


func _show_title() -> void:
    if _busy:
        return
    _busy = true
    var tween: Tween = create_tween()
    tween.tween_property(act_screen, "modulate:a", 0.0, 0.4)
    await tween.finished
    act_screen.hide()
    title_screen.modulate.a = 0.0
    title_screen.show()
    _screen = "title"
    tween = create_tween()
    tween.tween_property(title_screen, "modulate:a", 1.0, 0.6)
    await tween.finished
    _busy = false


func _begin_act_one() -> void:
    if _busy:
        return
    _busy = true
    _screen = "intro"
    intro_label.text = intro_text
    intro_label.visible_characters = 0
    intro_screen.modulate.a = 0.0
    intro_screen.show()
    var tween: Tween = create_tween()
    tween.tween_property(intro_screen, "modulate:a", 1.0, 0.9)
    await tween.finished
    act_screen.hide()
    await get_tree().create_timer(0.7).timeout

    for i in range(intro_text.length()):
        intro_label.visible_characters = i + 1
        var delay: float = intro_letter_seconds
        if intro_text[i] == ".":
            delay += 0.56
        await get_tree().create_timer(delay).timeout
    await get_tree().create_timer(1.2).timeout

    tween = create_tween()
    tween.tween_property(intro_screen, "modulate:a", 0.0, 0.9)
    await tween.finished
    intro_screen.hide()
    menu_backdrop.hide()
    _start_game()


func _start_game() -> void:
    _screen = "game"
    if _player != null:
        _player.set_physics_process(true)
        _player.set_process_unhandled_input(true)
        if _player.has_method("set_story_controls_locked"):
            _player.call("set_story_controls_locked", false)
    if _companion != null:
        if _companion.has_method("set_companion_visible"):
            _companion.call("set_companion_visible", true)
        elif _companion is Node3D:
            (_companion as Node3D).visible = true
        elif _companion is CanvasItem:
            (_companion as CanvasItem).visible = true
        _companion.set_process(true)
        _companion.set_physics_process(true)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _busy = false


func _show_error(message: String) -> void:
    _load_failed = true
    push_error(message)
    $Boot/Group/BootStatus.text = message
