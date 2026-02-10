extends Node3D

@export var alien_scene: PackedScene
@export var bomber_scene: PackedScene
@export var collector_scene: PackedScene

var turrets: Array[Turret] = []
var enemies: Array = []  # All enemies (MissileFrigate, Bomber, etc.)
var _f11_held: bool = false
var camera: Camera3D = null
var hud: Node = null
var collector_ship: Node3D = null
var space_station: Node3D = null
var level_manager: Node = null


func _ready() -> void:
	# Wait a frame for all nodes to be ready
	await get_tree().process_frame

	# Find all turrets in the scene
	_find_turrets(get_tree().root)
	print("Found turrets: ", turrets.size())

	# Get the camera
	camera = get_viewport().get_camera_3d()

	# Get the HUD
	hud = get_parent().get_node_or_null("HUD")
	if hud:
		hud.turret_selected.connect(_on_turret_selected)
		hud.turret_deselected.connect(_on_turret_deselected)
		hud.turret_upgraded.connect(_on_turret_upgraded)

	# Get the space station and connect its tractor beam
	space_station = get_parent().get_node_or_null("SpaceStation")
	if space_station and space_station.has_signal("scrap_collected"):
		space_station.scrap_collected.connect(_on_station_scrap_collected)

	# Spawn the collector ship at the hangar
	_spawn_collector()

	# Setup level manager
	_setup_level_manager()


func _find_turrets(node: Node) -> void:
	if node is Turret:
		turrets.append(node)
	for child in node.get_children():
		_find_turrets(child)


func _setup_level_manager() -> void:
	var LevelManagerScript = load("res://level_manager.gd")
	level_manager = LevelManagerScript.new()
	level_manager.game_manager = self
	add_child(level_manager)

	# Connect level manager signals
	level_manager.level_started.connect(_on_level_started)
	level_manager.wave_started.connect(_on_wave_started)
	level_manager.level_completed.connect(_on_level_completed)
	level_manager.all_levels_completed.connect(_on_all_levels_completed)

	# Start level 1
	level_manager.start_level(0)


func _on_wave_started(wave_number: int, total_waves: int) -> void:
	print("Wave %d of %d started" % [wave_number, total_waves])
	if hud:
		hud.update_wave(wave_number, total_waves)


func _on_level_started(level_number: int, total_waves: int) -> void:
	if hud:
		hud.update_level(level_number)
		hud.update_wave(0, total_waves)


func _on_level_completed(level_number: int) -> void:
	print("Level %d completed!" % (level_number + 1))
	# Auto-start next level after a brief pause
	await get_tree().create_timer(3.0).timeout
	level_manager.start_next_level()


func _on_all_levels_completed() -> void:
	print("Congratulations! All levels completed!")


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

	_update_turret_targets()


func spawn_frigate() -> void:
	if alien_scene == null:
		return

	var alien := alien_scene.instantiate()
	_setup_alien(alien, 30.0, 1.0)


func spawn_bomber_squadron(count: int = 3) -> void:
	if bomber_scene == null:
		return

	# Pick a random angle for the squadron to enter from
	var base_angle := randf() * TAU
	var spawn_distance := 35.0
	var angle_spacing := 0.15  # Angle offset between bombers (radians)

	for i in count:
		var bomber := bomber_scene.instantiate()
		# Offset each bomber's angle so they trail behind each other
		var bomber_angle := base_angle + (i * angle_spacing)
		var spawn_pos := Vector3(
			cos(bomber_angle) * spawn_distance,
			1.5,
			sin(bomber_angle) * spawn_distance
		)
		bomber.global_position = spawn_pos
		bomber.target_position = Vector3(0, 1, 0)
		bomber.formation_angle = bomber_angle + PI  # Point toward center
		bomber.add_to_group("aliens")
		bomber.died.connect(_on_alien_died)
		bomber.killed.connect(_on_alien_killed)
		enemies.append(bomber)
		add_child(bomber)


func _setup_alien(alien: Node3D, spawn_distance: float, height: float) -> void:
	alien.add_to_group("aliens")

	var angle := randf() * TAU
	var spawn_pos := Vector3(
		cos(angle) * spawn_distance,
		height,
		sin(angle) * spawn_distance
	)
	alien.global_position = spawn_pos
	alien.target_position = Vector3(0, 1, 0)

	alien.died.connect(_on_alien_died)
	alien.killed.connect(_on_alien_killed)
	enemies.append(alien)
	add_child(alien)


func _on_alien_died(alien: Node3D) -> void:
	enemies.erase(alien)


func _on_alien_killed(_alien: Node3D, _scrap_value: int) -> void:
	pass


func _on_turret_selected(index: int) -> void:
	for turret in turrets:
		turret.hide_selection()
	if index >= 0 and index < turrets.size():
		turrets[index].show_selection()


func _on_turret_deselected() -> void:
	for turret in turrets:
		turret.hide_selection()


func _spawn_collector() -> void:
	if collector_scene:
		collector_ship = collector_scene.instantiate()
		collector_ship.global_position = Vector3(-6.5, 1, 0)
		collector_ship.rotation.y = PI / 2
		collector_ship.health_changed.connect(_on_collector_health_changed)
		collector_ship.cargo_changed.connect(_on_cargo_changed)
		collector_ship.cargo_unloaded.connect(_on_cargo_unloaded)
		add_child(collector_ship)


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


func _on_turret_upgraded(index: int, stat: String, value: float) -> void:
	if index >= 0 and index < turrets.size():
		var turret := turrets[index]
		match stat:
			"rate_of_fire":
				turret.rate_of_fire = value
			"tracking_speed":
				turret.tracking_speed = value


func _has_clear_shot(turret_pos: Vector3, alien_pos: Vector3) -> bool:
	var station_pos := Vector3.ZERO
	var station_radius := 5.0

	var to_alien := alien_pos - turret_pos
	var distance_to_alien := to_alien.length()
	var dir := to_alien.normalized()

	var to_station := station_pos - turret_pos
	var projection := to_station.dot(dir)

	if projection <= 0 or projection >= distance_to_alien:
		return true

	var closest_point := turret_pos + dir * projection
	var distance_to_station := closest_point.distance_to(station_pos)

	return distance_to_station > station_radius


func _is_on_screen(pos: Vector3) -> bool:
	if camera == null:
		return true

	if not camera.is_position_in_frustum(pos):
		return false

	var screen_pos := camera.unproject_position(pos)
	var viewport_size := get_viewport().get_visible_rect().size

	return screen_pos.x >= 0 and screen_pos.x <= viewport_size.x and \
		   screen_pos.y >= 0 and screen_pos.y <= viewport_size.y


func _update_turret_targets() -> void:
	var targeted_enemies: Array = []

	for turret in turrets:
		if turret.target and is_instance_valid(turret.target):
			var enemy := turret.target
			if "is_alive" in enemy and enemy.is_alive and _is_on_screen(enemy.global_position) and _has_clear_shot(turret.global_position, enemy.global_position):
				targeted_enemies.append(enemy)
				continue

		var station_pos := Vector3.ZERO
		var closest_enemy: Node3D = null
		var closest_dist := INF

		for enemy in enemies:
			if "is_alive" in enemy and enemy.is_alive and _is_on_screen(enemy.global_position):
				if enemy not in targeted_enemies and _has_clear_shot(turret.global_position, enemy.global_position):
					var dist := station_pos.distance_to(enemy.global_position)
					if dist < closest_dist:
						closest_dist = dist
						closest_enemy = enemy

		if closest_enemy:
			turret.set_target(closest_enemy)
			targeted_enemies.append(closest_enemy)
		else:
			turret.clear_target()
