class_name GameManager
extends Node3D

const COLLECTOR_SPAWN_POS      := Vector3(-4.76, 1.5, 1.55)
const COLLECTOR_SPAWN_ROTATION := PI / 2

@export var collector_scene: PackedScene

var _f11_held: bool = false
var camera: Camera3D = null
var hud: HUD = null
var collector_ship: CollectorShip = null
var mothership: MiningMothership = null


func _ready() -> void:
	await get_tree().process_frame

	camera = get_viewport().get_camera_3d()

	hud = get_tree().get_first_node_in_group("hud") as HUD
	if not hud:
		hud = get_parent().get_node_or_null("HUD") as HUD

	mothership = get_tree().get_first_node_in_group("mothership") as MiningMothership
	if not mothership:
		mothership = get_parent().get_node_or_null("MiningMothership") as MiningMothership

	_spawn_collector()


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

		# Wire mothership landing pad and cargo bay before _ready() fires
		if mothership:
			var landing_pad := mothership.get_node_or_null("DockingRing") as Node3D
			var cargo_bay   := mothership.get_node_or_null("CargoBay") as Node3D
			if landing_pad:
				collector_ship.parking_bay_node = landing_pad
				collector_ship.position = landing_pad.global_position
				collector_ship.rotation.y = mothership.rotation.y
			if cargo_bay:
				collector_ship.intake_node = cargo_bay

		collector_ship.health_changed.connect(_on_collector_health_changed)
		collector_ship.energy_changed.connect(_on_collector_energy_changed)
		collector_ship.cargo_changed.connect(_on_cargo_changed)
		collector_ship.cargo_unloaded.connect(_on_cargo_unloaded)
		collector_ship.asteroid_mined.connect(_on_asteroid_mined)
		add_child(collector_ship)
		if hud:
			hud.collector_ship = collector_ship


func _on_cargo_changed(current: int, capacity: int) -> void:
	if hud:
		hud.update_cargo(current, capacity)


func _on_cargo_unloaded(amount: int) -> void:
	if mothership:
		mothership.collect_ore(amount)


func _on_collector_health_changed(current: float, _maximum: float) -> void:
	if hud:
		hud.update_collector_health(current)


func _on_collector_energy_changed(current: float, maximum: float) -> void:
	if hud:
		hud.update_energy(current, maximum)


func _on_asteroid_mined(hit_point: Vector3) -> void:
	var field := get_tree().get_first_node_in_group("space_anomalies") as SpaceAnomaly

	# Identify which asteroid body was actually struck
	var mined_body: StaticBody3D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as StaticBody3D
		if not asteroid:
			continue
		var d := hit_point.distance_to(asteroid.global_position)
		if d < nearest_dist:
			nearest_dist = d
			mined_body = asteroid

	var count := randi_range(10, 20)
	for i in count:
		var bug := BugAlien.new()
		var marker: Node3D = null
		if field and mined_body:
			marker = field.get_spawn_marker_for_body(mined_body)
		elif field:
			marker = field.get_random_spawn_marker()
		var spawn := marker.global_position if marker else hit_point
		var offset := Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.2, 0.2))
		add_child(bug)
		bug.global_position = spawn + offset
		bug.hole_marker = marker
