class_name CollectorShip
extends Node3D

signal scrap_collected(amount: int)
signal health_changed(current: float, maximum: float)
signal cargo_changed(current: int, capacity: int)
signal cargo_unloaded(amount: int)
signal destroyed()
signal asteroid_mined(position: Vector3)

# Flying scrap animation constants
const SCRAP_SPAWN_OFFSET := 0.3
const FLYING_SCRAP_SPEED := 8.0
const FLYING_SCRAP_ARC_HEIGHT := 1.0
const FLYING_SCRAP_SIZE := Vector3(0.1, 0.1, 0.1)
const SCRAP_SPIN_SPEED := Vector3(5.0, 7.0, 3.0)

# Beam constants
const BEAM_RADIUS := 0.02
const COLLECTOR_RADIUS := 0.65

# Mining constants
const SCRAP_SCENE := preload("res://scrap_piece.tscn")
const MINING_RANGE := 8.0
const MINING_SCRAP_RATE := 0.4  # Scrap per second
const LASER_RADIUS := 0.03
const SCRAP_EJECT_SPEED := 1.2

# Default positions (fallback if not assigned)
const DEFAULT_PARKING_POS := Vector3(-4.76, 1, 1.55)
const DEFAULT_INTAKE_POS := Vector3(0, 2.3, 0)

# Inner class for flying scrap data - replaces Dictionary for type safety
class FlyingScrapData:
	var node: MeshInstance3D
	var start: Vector3
	var target: Vector3
	var progress: float

	func _init(n: MeshInstance3D, s: Vector3, t: Vector3) -> void:
		node = n
		start = s
		target = t
		progress = 0.0

@export var max_health: float = 100.0
@export var rotation_speed: float = 180.0  # Degrees per second
@export var thrust_power: float = 15.0
@export var max_speed: float = 12.0
@export var drag: float = 0.992  # Velocity multiplier per frame
@export var tractor_range: float = 2.5  # Range to start pulling scrap
@export var tractor_power: float = 8.0  # Pull speed
@export var collect_distance: float = 0.5  # Distance to collect scrap
@export var shield_radius: float = 3.0  # Keep away from station shield
@export var cargo_capacity: int = 50  # Max scrap the collector can hold
@export var unload_range: float = 1.5  # Distance to parking bay to unload
@export var unload_rate: float = 10.0  # Scrap unloaded per second

# Optional node references - assign in editor for more flexibility
@export var parking_bay_node: Node3D
@export var intake_node: Node3D

var _attached_bugs: Array = []
var velocity: Vector3 = Vector3.ZERO
var _mining_target: StaticBody3D = null
var _laser_beam: MeshInstance3D = null
var _laser_material: StandardMaterial3D = null
var _impact_glow: MeshInstance3D = null
var _mining_accumulator: float = 0.0
var is_thrusting: bool = false
var is_tractoring: bool = false
var is_unloading: bool = false
var health: float = 100.0
var current_cargo: int = 0
var unload_accumulator: float = 0.0
var parking_bay_pos: Vector3 = DEFAULT_PARKING_POS
var intake_pos: Vector3 = DEFAULT_INTAKE_POS
var beam_lines: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D
var scrap_visual_material: StandardMaterial3D
var flying_scrap: Array = []  # Array of FlyingScrapData

@onready var engine_glow: CSGCylinder3D = $Ship/EngineGlow
@onready var engine_glow_left: CSGCylinder3D = $Ship/EngineGlowLeft
@onready var engine_glow_right: CSGCylinder3D = $Ship/EngineGlowRight
@onready var tractor_turret: Node3D = $Ship/TractorTurret
@onready var weapon_mount: Node3D = $Ship/WeaponMount


func _ready() -> void:
	add_to_group("collectors")
	health = max_health
	health_changed.emit(health, max_health)
	cargo_changed.emit(current_cargo, cargo_capacity)

	# Get positions from nodes if assigned, otherwise use defaults
	if parking_bay_node:
		parking_bay_pos = parking_bay_node.global_position
	if intake_node:
		intake_pos = intake_node.global_position

	# Create glowing blue beam material
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.3, 0.6, 1.0, 0.8)
	beam_material.emission_enabled = true
	beam_material.emission = Color(0.4, 0.7, 1.0, 1.0)
	beam_material.emission_energy_multiplier = 3.0
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Create mining laser beam
	_laser_material = StandardMaterial3D.new()
	_laser_material.albedo_color = Color(1.0, 0.25, 0.05, 0.9)
	_laser_material.emission_enabled = true
	_laser_material.emission = Color(1.0, 0.35, 0.1, 1.0)
	_laser_material.emission_energy_multiplier = 6.0
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var laser_cylinder := CylinderMesh.new()
	laser_cylinder.top_radius = LASER_RADIUS
	laser_cylinder.bottom_radius = LASER_RADIUS
	laser_cylinder.height = 1.0
	laser_cylinder.material = _laser_material
	_laser_beam = MeshInstance3D.new()
	_laser_beam.mesh = laser_cylinder
	_laser_beam.visible = false
	add_child(_laser_beam)

	# Create impact glow at asteroid surface
	var impact_mat := StandardMaterial3D.new()
	impact_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.85)
	impact_mat.emission_enabled = true
	impact_mat.emission = Color(1.0, 0.5, 0.1, 1.0)
	impact_mat.emission_energy_multiplier = 8.0
	impact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var impact_sphere := SphereMesh.new()
	impact_sphere.radius = 0.22
	impact_sphere.height = 0.44
	impact_sphere.radial_segments = 8
	impact_sphere.rings = 4
	impact_sphere.material = impact_mat
	_impact_glow = MeshInstance3D.new()
	_impact_glow.mesh = impact_sphere
	_impact_glow.visible = false
	add_child(_impact_glow)

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
	_process_mining_laser(delta)
	_process_unloading(delta)
	_process_flying_scrap(delta)


func _handle_input(delta: float) -> void:
	var slow := _get_bug_slow_multiplier()

	# Rotation (A/D keys)
	if Input.is_physical_key_pressed(KEY_A):
		rotation.y += deg_to_rad(rotation_speed * slow) * delta
	if Input.is_physical_key_pressed(KEY_D):
		rotation.y -= deg_to_rad(rotation_speed * slow) * delta

	# Thrust (W key)
	is_thrusting = Input.is_physical_key_pressed(KEY_W)
	if is_thrusting:
		var forward := -global_transform.basis.z
		velocity += forward * (thrust_power * slow) * delta


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

	# Asteroid collision
	for asteroid in get_tree().get_nodes_in_group("asteroids"):
		var asteroid_node := asteroid as Node3D
		if not asteroid_node:
			continue
		var asteroid_radius: float = asteroid_node.get_meta("radius", 1.0)
		var min_dist := COLLECTOR_RADIUS + asteroid_radius
		var offset := Vector3(
			position.x - asteroid_node.global_position.x,
			0,
			position.z - asteroid_node.global_position.z
		)
		var dist := offset.length()
		if dist < min_dist and dist > 0.001:
			var push_dir := offset.normalized()
			position += push_dir * (min_dist - dist)
			var vel_into := velocity.dot(-push_dir)
			if vel_into > 0:
				velocity += push_dir * vel_into

	# Keep away from station shield (at origin)
	var to_ship := Vector3(position.x, 0, position.z)
	var shield_dist := to_ship.length()
	if shield_dist < shield_radius:
		var push_dir := to_ship.normalized()
		position.x = push_dir.x * shield_radius
		position.z = push_dir.z * shield_radius
		# Kill velocity towards shield
		var vel_toward_shield := velocity.dot(-push_dir)
		if vel_toward_shield > 0:
			velocity += push_dir * vel_toward_shield


func _update_engine_glow() -> void:
	if engine_glow:
		engine_glow.visible = is_thrusting
	if engine_glow_left:
		engine_glow_left.visible = is_thrusting
	if engine_glow_right:
		engine_glow_right.visible = is_thrusting


func _process_mining_laser(delta: float) -> void:
	# Find closest asteroid within mining range
	var closest: StaticBody3D = null
	var closest_dist := MINING_RANGE
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as StaticBody3D
		if not asteroid:
			continue
		var dist := global_position.distance_to(asteroid.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = asteroid

	_mining_target = closest

	if not _mining_target:
		_laser_beam.visible = false
		_impact_glow.visible = false
		_mining_accumulator = 0.0
		return

	# Rotate weapon mount to track asteroid, locked to Y axis
	var look_target := Vector3(_mining_target.global_position.x, weapon_mount.global_position.y, _mining_target.global_position.z)
	weapon_mount.look_at(look_target, Vector3.UP)

	# Barrel tip: step forward along weapon_mount's -Z axis and slightly up to clear the mount plate
	var barrel_forward := -weapon_mount.global_transform.basis.z
	var beam_start := weapon_mount.global_position + barrel_forward * 0.14 + Vector3(0.0, 0.08, 0.0)

	# Hit point = point on asteroid surface closest to the barrel
	var asteroid_radius: float = _mining_target.get_meta("radius", 1.0)
	var to_asteroid := (_mining_target.global_position - beam_start).normalized()
	var hit_point := _mining_target.global_position - to_asteroid * asteroid_radius

	# Position and orient the laser beam
	var beam_length := beam_start.distance_to(hit_point)
	_laser_beam.visible = true
	_laser_beam.global_position = (beam_start + hit_point) / 2.0
	_laser_beam.look_at(hit_point, Vector3.UP)
	_laser_beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_laser_beam.scale = Vector3(1.0, beam_length, 1.0)

	# Impact glow — pulse scale slightly for liveliness
	var pulse := 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
	_impact_glow.visible = true
	_impact_glow.global_position = hit_point
	_impact_glow.scale = Vector3(pulse, pulse, pulse)

	# Accumulate mining and spawn scrap at hit point
	_mining_accumulator += MINING_SCRAP_RATE * delta
	if _mining_accumulator >= 1.0:
		_mining_accumulator -= 1.0
		_spawn_mined_scrap(hit_point)


func _spawn_mined_scrap(hit_point: Vector3) -> void:
	var count := randi_range(1, 5)
	# Base outward direction from asteroid centre to hit point
	var surface_normal := (hit_point - _mining_target.global_position).normalized()
	for i in count:
		var scrap := SCRAP_SCENE.instantiate()
		get_tree().root.add_child(scrap)
		# Slight random offset so pieces don't all start at exactly the same spot
		scrap.global_position = hit_point + Vector3(
			randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)
		)
		# Random direction in a hemisphere around the surface normal
		var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		var eject_dir := Vector3((surface_normal + scatter).x, 0.0, (surface_normal + scatter).z).normalized()
		scrap.drift_direction = eject_dir * randf_range(SCRAP_EJECT_SPEED * 0.6, SCRAP_EJECT_SPEED * 1.4)

	asteroid_mined.emit(hit_point)


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
		cylinder.top_radius = BEAM_RADIUS
		cylinder.bottom_radius = BEAM_RADIUS
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

			# Orient to point at target, then scale — order matters: look_at resets scale
			beam.look_at(target_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
			beam.scale = Vector3(1, distance, 1)
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
	box.size = FLYING_SCRAP_SIZE
	box.material = scrap_visual_material
	scrap_mesh.mesh = box

	# Start position with slight random offset from collector
	var start_pos := global_position + Vector3(
		randf_range(-SCRAP_SPAWN_OFFSET, SCRAP_SPAWN_OFFSET),
		randf_range(0, SCRAP_SPAWN_OFFSET),
		randf_range(-SCRAP_SPAWN_OFFSET, SCRAP_SPAWN_OFFSET)
	)

	get_tree().root.add_child(scrap_mesh)
	scrap_mesh.global_position = start_pos

	var scrap_data := FlyingScrapData.new(scrap_mesh, start_pos, intake_pos)
	flying_scrap.append(scrap_data)


func _process_flying_scrap(delta: float) -> void:
	var to_remove: Array[int] = []

	for i in range(flying_scrap.size()):
		var scrap_data: FlyingScrapData = flying_scrap[i]

		# Move progress based on distance and speed
		var total_dist := scrap_data.start.distance_to(scrap_data.target)
		scrap_data.progress += (FLYING_SCRAP_SPEED / total_dist) * delta

		if scrap_data.progress >= 1.0:
			# Reached destination
			scrap_data.node.queue_free()
			to_remove.append(i)
		else:
			# Interpolate position with slight arc
			var t := scrap_data.progress
			var arc_height := FLYING_SCRAP_ARC_HEIGHT * sin(t * PI)
			var pos := scrap_data.start.lerp(scrap_data.target, t)
			pos.y += arc_height
			scrap_data.node.global_position = pos

			# Spin the scrap
			scrap_data.node.rotation += SCRAP_SPIN_SPEED * delta

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


func attach_bug(bug: Node3D) -> void:
	_attached_bugs.append(bug)


func detach_bug(bug: Node3D) -> void:
	_attached_bugs.erase(bug)


func _get_bug_slow_multiplier() -> float:
	return maxf(0.1, 1.0 - _attached_bugs.size() * 0.03)
