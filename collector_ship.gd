extends Node3D

signal scrap_collected(amount: int)
signal health_changed(current: float, maximum: float)
signal cargo_changed(current: int, capacity: int)
signal cargo_unloaded(amount: int)
signal destroyed()

@export var max_health: float = 100.0
@export var rotation_speed: float = 180.0  # Degrees per second
@export var thrust_power: float = 15.0
@export var max_speed: float = 12.0
@export var drag: float = 0.98  # Velocity multiplier per frame
@export var tractor_range: float = 2.5  # Range to start pulling scrap
@export var tractor_power: float = 8.0  # Pull speed
@export var collect_distance: float = 0.5  # Distance to collect scrap
@export var station_radius: float = 6.0  # Keep away from station center
@export var cargo_capacity: int = 50  # Max scrap the collector can hold
@export var unload_range: float = 1.5  # Distance to parking bay to unload
@export var unload_rate: float = 10.0  # Scrap unloaded per second

var velocity: Vector3 = Vector3.ZERO
var is_thrusting: bool = false
var is_tractoring: bool = false
var is_unloading: bool = false
var health: float = 100.0
var current_cargo: int = 0
var unload_accumulator: float = 0.0
var parking_bay_pos: Vector3 = Vector3(-6.5, 1, 0)  # Matches ParkingBay position in station
var intake_pos: Vector3 = Vector3(0, 2.3, 0)  # Station scrap intake position
var beam_lines: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D
var scrap_visual_material: StandardMaterial3D
var flying_scrap: Array[Dictionary] = []  # {node: MeshInstance3D, start: Vector3, target: Vector3, progress: float}

@onready var engine_glow: CSGCylinder3D = $Ship/EngineGlow
@onready var engine_glow_left: CSGCylinder3D = $Ship/EngineGlowLeft
@onready var engine_glow_right: CSGCylinder3D = $Ship/EngineGlowRight
@onready var tractor_turret: Node3D = $Ship/TractorTurret


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	cargo_changed.emit(current_cargo, cargo_capacity)

	# Create glowing blue beam material
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.3, 0.6, 1.0, 0.8)
	beam_material.emission_enabled = true
	beam_material.emission = Color(0.4, 0.7, 1.0, 1.0)
	beam_material.emission_energy_multiplier = 3.0
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Create glowing scrap visual material
	scrap_visual_material = StandardMaterial3D.new()
	scrap_visual_material.albedo_color = Color(1, 0.7, 0.3, 1)
	scrap_visual_material.emission_enabled = true
	scrap_visual_material.emission = Color(1, 0.5, 0.2, 1)
	scrap_visual_material.emission_energy_multiplier = 2.0


func take_damage(amount: float) -> void:
	health -= amount
	health = max(health, 0)
	health_changed.emit(health, max_health)

	if health <= 0:
		destroyed.emit()


func _process(delta: float) -> void:
	_handle_input(delta)
	_apply_physics(delta)
	_update_engine_glow()
	_process_tractor_beam(delta)
	_process_unloading(delta)
	_process_flying_scrap(delta)


func _handle_input(delta: float) -> void:
	# Rotation (left/right arrows)
	if Input.is_action_pressed("ui_left"):
		rotation.y += deg_to_rad(rotation_speed) * delta
	if Input.is_action_pressed("ui_right"):
		rotation.y -= deg_to_rad(rotation_speed) * delta

	# Thrust (up arrow)
	is_thrusting = Input.is_action_pressed("ui_up")
	if is_thrusting:
		var forward := -global_transform.basis.z
		velocity += forward * thrust_power * delta


func _apply_physics(delta: float) -> void:
	# Apply drag
	velocity *= drag

	# Clamp speed
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	# Keep on horizontal plane
	velocity.y = 0

	# Apply movement
	position += velocity * delta

	# Keep away from station (at origin)
	var station_pos := Vector3.ZERO
	var to_ship := Vector3(position.x, 0, position.z) - station_pos
	var dist := to_ship.length()
	if dist < station_radius:
		# Push ship out to the edge
		var push_dir := to_ship.normalized()
		position.x = push_dir.x * station_radius
		position.z = push_dir.z * station_radius
		# Kill velocity towards station
		var vel_toward_station := velocity.dot(-push_dir)
		if vel_toward_station > 0:
			velocity += push_dir * vel_toward_station


func _update_engine_glow() -> void:
	if engine_glow:
		engine_glow.visible = is_thrusting
	if engine_glow_left:
		engine_glow_left.visible = is_thrusting
	if engine_glow_right:
		engine_glow_right.visible = is_thrusting


func _process_tractor_beam(delta: float) -> void:
	var scrap_pieces := get_tree().get_nodes_in_group("scrap")
	var active_targets: Array[Node3D] = []

	# Don't pull scrap if cargo is full
	if is_cargo_full():
		is_tractoring = false
		_update_beam_lines(active_targets)
		return

	for scrap in scrap_pieces:
		var scrap_node := scrap as Node3D
		if not scrap_node:
			continue

		var distance := global_position.distance_to(scrap_node.global_position)

		if distance < tractor_range:
			active_targets.append(scrap_node)
			# Pull scrap towards ship
			var direction := (global_position - scrap_node.global_position).normalized()
			scrap_node.global_position += direction * tractor_power * delta

			# Check if close enough to collect
			if distance < collect_distance:
				_collect_scrap(scrap_node)

	is_tractoring = active_targets.size() > 0
	_update_beam_lines(active_targets)


func _update_beam_lines(targets: Array[Node3D]) -> void:
	# Create more beam lines if needed
	while beam_lines.size() < targets.size():
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.02
		cylinder.bottom_radius = 0.02
		cylinder.height = 1.0
		cylinder.material = beam_material
		beam.mesh = cylinder
		add_child(beam)
		beam_lines.append(beam)

	# Update each beam line
	for i in range(beam_lines.size()):
		var beam := beam_lines[i]
		if i < targets.size():
			beam.visible = true
			var target := targets[i]
			var turret_pos := tractor_turret.global_position
			var target_pos := target.global_position
			var midpoint := (turret_pos + target_pos) / 2.0
			var distance := turret_pos.distance_to(target_pos)

			# Position at midpoint
			beam.global_position = midpoint

			# Scale to match distance
			beam.scale = Vector3(1, distance, 1)

			# Orient to point at target
			beam.look_at(target_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		else:
			beam.visible = false


func _process_unloading(delta: float) -> void:
	# Check distance to parking bay
	var dist_to_parking := global_position.distance_to(parking_bay_pos)

	if dist_to_parking <= unload_range and current_cargo > 0:
		is_unloading = true
		unload_accumulator += unload_rate * delta

		# Unload whole units
		while unload_accumulator >= 1.0 and current_cargo > 0:
			unload_accumulator -= 1.0
			current_cargo -= 1
			_spawn_flying_scrap()
			cargo_unloaded.emit(1)
			cargo_changed.emit(current_cargo, cargo_capacity)
	else:
		is_unloading = false
		unload_accumulator = 0.0


func _spawn_flying_scrap() -> void:
	var scrap_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	box.material = scrap_visual_material
	scrap_mesh.mesh = box

	# Start position with slight random offset from collector
	var start_pos := global_position + Vector3(
		randf_range(-0.3, 0.3),
		randf_range(0, 0.3),
		randf_range(-0.3, 0.3)
	)
	scrap_mesh.global_position = start_pos

	get_tree().root.add_child(scrap_mesh)

	flying_scrap.append({
		"node": scrap_mesh,
		"start": start_pos,
		"target": intake_pos,
		"progress": 0.0
	})


func _process_flying_scrap(delta: float) -> void:
	var scrap_speed := 8.0
	var to_remove: Array[int] = []

	for i in range(flying_scrap.size()):
		var scrap_data: Dictionary = flying_scrap[i]
		var node: MeshInstance3D = scrap_data["node"]
		var start: Vector3 = scrap_data["start"]
		var target: Vector3 = scrap_data["target"]

		# Move progress based on distance and speed
		var total_dist := start.distance_to(target)
		scrap_data["progress"] += (scrap_speed / total_dist) * delta

		if scrap_data["progress"] >= 1.0:
			# Reached destination
			node.queue_free()
			to_remove.append(i)
		else:
			# Interpolate position with slight arc
			var t: float = scrap_data["progress"]
			var arc_height := 1.0 * sin(t * PI)  # Arc upward
			var pos := start.lerp(target, t)
			pos.y += arc_height
			node.global_position = pos

			# Spin the scrap
			node.rotation += Vector3(delta * 5, delta * 7, delta * 3)

	# Remove completed scrap (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		flying_scrap.remove_at(to_remove[i])


func _collect_scrap(scrap: Node) -> void:
	if current_cargo >= cargo_capacity:
		return  # Cargo full, can't collect

	current_cargo += 1
	cargo_changed.emit(current_cargo, cargo_capacity)
	scrap_collected.emit(1)
	scrap.queue_free()


func is_cargo_full() -> bool:
	return current_cargo >= cargo_capacity


func empty_cargo() -> int:
	var amount := current_cargo
	current_cargo = 0
	cargo_changed.emit(current_cargo, cargo_capacity)
	return amount
