extends Node3D

@export var alien_scene: PackedScene
@export var collector_scene: PackedScene
@export var spawn_rate: float = 1.0  # Aliens per second
@export var max_aliens: int = 5  # Maximum aliens at once

var turrets: Array[Turret] = []
var aliens: Array[MissileFrigate] = []
var total_aliens_spawned: int = 0
var time_since_spawn: float = 0.0
var _f11_held: bool = false
var camera: Camera3D = null
var hud: Node = null
var collector_ship: Node3D = null
var space_station: Node3D = null


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



func _find_turrets(node: Node) -> void:
	if node is Turret:
		turrets.append(node)
	for child in node.get_children():
		_find_turrets(child)


func _process(delta: float) -> void:
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

	time_since_spawn += delta

	var spawn_interval := 1.0 / spawn_rate
	if time_since_spawn >= spawn_interval and total_aliens_spawned < max_aliens:
		_spawn_alien()
		time_since_spawn = 0.0

	_update_turret_targets()


func _spawn_alien() -> void:
	if alien_scene == null:
		return

	var alien: MissileFrigate = alien_scene.instantiate()
	alien.add_to_group("aliens")

	# Spawn from random position on edge of play area
	var spawn_distance := 30.0
	var angle := randf() * TAU
	var spawn_pos := Vector3(
		cos(angle) * spawn_distance,
		1,
		sin(angle) * spawn_distance
	)
	alien.global_position = spawn_pos
	alien.target_position = Vector3(0, 1, 0)  # Station at center, same height

	alien.died.connect(_on_alien_died)
	alien.killed.connect(_on_alien_killed)
	alien.reached_station.connect(_on_alien_reached_station)
	aliens.append(alien)
	total_aliens_spawned += 1

	add_child(alien)


func _on_alien_died(alien: MissileFrigate) -> void:
	aliens.erase(alien)


func _on_alien_killed(_alien: MissileFrigate, _scrap_value: int) -> void:
	# Scrap is now collected manually from wreckage
	pass


func _on_alien_reached_station(_alien: MissileFrigate, damage: float) -> void:
	if hud:
		hud.take_damage(damage)


func _on_turret_selected(index: int) -> void:
	# Hide all selections first
	for turret in turrets:
		turret.hide_selection()

	# Show selection on the chosen turret
	if index >= 0 and index < turrets.size():
		turrets[index].show_selection()


func _on_turret_deselected() -> void:
	for turret in turrets:
		turret.hide_selection()


func _spawn_collector() -> void:
	if collector_scene:
		collector_ship = collector_scene.instantiate()
		# Spawn at hangar position (station is at 0,0,0, hangar is at 0, -0.5, 3.5)
		collector_ship.global_position = Vector3(-6.5, 1, 0)  # Start on docking platform
		collector_ship.rotation.y = PI / 2  # Facing away from station
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
	var station_radius := 5.0  # Radius of the station

	# Direction from turret to alien
	var to_alien := alien_pos - turret_pos
	var distance_to_alien := to_alien.length()
	var dir := to_alien.normalized()

	# Find closest point on the line to the station center
	var to_station := station_pos - turret_pos
	var projection := to_station.dot(dir)

	# If station is behind the turret or beyond the alien, clear shot
	if projection <= 0 or projection >= distance_to_alien:
		return true

	# Find the closest point on the line to station
	var closest_point := turret_pos + dir * projection
	var distance_to_station := closest_point.distance_to(station_pos)

	# If line passes too close to station center, no clear shot
	return distance_to_station > station_radius


func _is_on_screen(pos: Vector3) -> bool:
	if camera == null:
		return true

	# Check if position is in front of camera
	if not camera.is_position_in_frustum(pos):
		return false

	# Also check screen coordinates are within viewport
	var screen_pos := camera.unproject_position(pos)
	var viewport_size := get_viewport().get_visible_rect().size

	return screen_pos.x >= 0 and screen_pos.x <= viewport_size.x and \
		   screen_pos.y >= 0 and screen_pos.y <= viewport_size.y


func _update_turret_targets() -> void:
	# Collect already targeted aliens
	var targeted_aliens: Array[MissileFrigate] = []

	for turret in turrets:
		# Check if turret already has a valid target
		if turret.target and is_instance_valid(turret.target):
			var alien := turret.target as MissileFrigate
			if alien and alien.is_alive and _is_on_screen(alien.global_position) and _has_clear_shot(turret.global_position, alien.global_position):
				# Keep current target
				targeted_aliens.append(alien)
				continue

		# Need a new target - find closest alien to station that is on screen, not targeted, and has clear shot
		var station_pos := Vector3.ZERO
		var closest_alien: MissileFrigate = null
		var closest_dist := INF

		for alien in aliens:
			if alien.is_alive and _is_on_screen(alien.global_position):
				if alien not in targeted_aliens and _has_clear_shot(turret.global_position, alien.global_position):
					var dist := station_pos.distance_to(alien.global_position)
					if dist < closest_dist:
						closest_dist = dist
						closest_alien = alien

		if closest_alien:
			turret.set_target(closest_alien)
			targeted_aliens.append(closest_alien)
		else:
			turret.clear_target()
