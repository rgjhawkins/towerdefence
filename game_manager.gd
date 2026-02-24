class_name GameManager
extends Node3D

const COLLECTOR_SPAWN_POS := Vector3(-4.76, 1.5, 1.55)
const COLLECTOR_SPAWN_ROTATION := PI / 2

@export var collector_scene: PackedScene

var turrets: Array[Turret] = []
var _f11_held: bool = false
var camera: Camera3D = null
var hud: HUD = null
var collector_ship: CollectorShip = null
var space_station: SpaceStation = null


func _ready() -> void:
	await get_tree().process_frame

	_find_turrets(get_tree().root)
	print("Found turrets: ", turrets.size())

	camera = get_viewport().get_camera_3d()

	hud = get_tree().get_first_node_in_group("hud") as HUD
	if not hud:
		hud = get_parent().get_node_or_null("HUD") as HUD
	if hud:
		hud.turrets = turrets

	space_station = get_tree().get_first_node_in_group("space_station") as SpaceStation
	if not space_station:
		space_station = get_parent().get_node_or_null("SpaceStation") as SpaceStation
	if space_station and space_station.has_signal("scrap_collected"):
		space_station.scrap_collected.connect(_on_station_scrap_collected)

	_spawn_collector()


func _find_turrets(node: Node) -> void:
	if node is Turret:
		turrets.append(node)
		node.clicked.connect(_on_turret_clicked)
	for child in node.get_children():
		_find_turrets(child)


func _on_turret_clicked(turret: Turret) -> void:
	if hud:
		hud.select_turret(turret)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()

	if Input.is_physical_key_pressed(KEY_F11) and not _f11_held:
		_f11_held = true
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not Input.is_physical_key_pressed(KEY_F11):
		_f11_held = false


func _spawn_collector() -> void:
	if collector_scene:
		collector_ship = collector_scene.instantiate() as CollectorShip
		collector_ship.position = COLLECTOR_SPAWN_POS
		collector_ship.rotation.y = COLLECTOR_SPAWN_ROTATION
		collector_ship.health_changed.connect(_on_collector_health_changed)
		collector_ship.cargo_changed.connect(_on_cargo_changed)
		collector_ship.cargo_unloaded.connect(_on_cargo_unloaded)
		add_child(collector_ship)
		if hud:
			hud.collector_ship = collector_ship


func _on_cargo_changed(current: int, capacity: int) -> void:
	if hud:
		hud.update_cargo(current, capacity)


func _on_cargo_unloaded(amount: int) -> void:
	if hud:
		hud.add_station_scrap(amount)


func _on_station_scrap_collected(amount: int) -> void:
	if hud:
		hud.add_station_scrap(amount)


func _on_collector_health_changed(current: float, _maximum: float) -> void:
	if hud:
		hud.update_collector_health(current)
