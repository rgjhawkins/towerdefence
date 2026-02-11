class_name Turret
extends Node3D

signal fired(bullet: Bullet)
signal clicked(turret: Turret)

@export var rate_of_fire: float = 2.0  # Shots per second
@export var tracking_speed: float = 180.0  # Degrees per second
@export var ammo_type: AmmoType
@export var bullet_scene: PackedScene
var target: Node3D = null
var time_since_last_shot: float = 0.0
var aim_position: Vector3 = Vector3.ZERO
var selection_ring: MeshInstance3D = null

@onready var barrel: Node3D = $Barrel
@onready var muzzle: Node3D = $Barrel/Muzzle
@onready var click_area: Area3D = $ClickArea


func _ready() -> void:
	if ammo_type == null:
		ammo_type = AmmoType.new()

	# Connect click area input
	if click_area:
		click_area.input_event.connect(_on_click_area_input_event)


func _on_click_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(self)



func _process(delta: float) -> void:
	time_since_last_shot += delta

	if target and is_instance_valid(target):
		aim_position = _calculate_lead_position()
		_track_target(delta)
		_try_fire()


func _calculate_lead_position() -> Vector3:
	var target_pos := target.global_position
	var muzzle_pos := muzzle.global_position
	var bullet_speed := ammo_type.bullet_speed

	# Get target velocity if available
	var target_velocity := Vector3.ZERO
	if "velocity" in target:
		target_velocity = target.velocity

	# Solve quadratic for intercept time
	# |target_pos + target_velocity * t - muzzle_pos| = bullet_speed * t
	var relative_pos := target_pos - muzzle_pos
	var a := target_velocity.length_squared() - bullet_speed * bullet_speed
	var b := 2.0 * relative_pos.dot(target_velocity)
	var c := relative_pos.length_squared()

	var intercept_time := 0.0

	if abs(a) < 0.001:
		# Linear case
		if abs(b) > 0.001:
			intercept_time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0:
			var sqrt_disc := sqrt(discriminant)
			var t1 := (-b - sqrt_disc) / (2.0 * a)
			var t2 := (-b + sqrt_disc) / (2.0 * a)

			# Pick smallest positive time
			if t1 > 0 and t2 > 0:
				intercept_time = min(t1, t2)
			elif t1 > 0:
				intercept_time = t1
			elif t2 > 0:
				intercept_time = t2

	# Clamp intercept time to reasonable range
	intercept_time = clamp(intercept_time, 0.0, 3.0)

	# Calculate lead position
	return target_pos + target_velocity * intercept_time


func _track_target(delta: float) -> void:
	# Get current and desired rotations
	var current_basis := barrel.global_transform.basis
	var current_quat := current_basis.get_rotation_quaternion()

	# Calculate desired rotation to aim at lead position
	var look_transform := barrel.global_transform.looking_at(aim_position, Vector3.UP)
	var target_quat := look_transform.basis.get_rotation_quaternion()

	# Calculate rotation speed
	var angle_diff := current_quat.angle_to(target_quat)
	var max_rotation := deg_to_rad(tracking_speed) * delta

	# Calculate slerp weight based on max rotation speed
	var weight := 1.0
	if angle_diff > 0.001:
		weight = min(max_rotation / angle_diff, 1.0)

	# Smoothly rotate towards target
	var new_quat := current_quat.slerp(target_quat, weight)
	barrel.global_transform.basis = Basis(new_quat)



func _try_fire() -> void:
	var fire_interval := 1.0 / rate_of_fire

	if time_since_last_shot >= fire_interval and _is_on_target():
		_fire()
		time_since_last_shot = 0.0


func _is_on_target() -> bool:
	var barrel_forward := -barrel.global_transform.basis.z.normalized()
	var to_target := (aim_position - muzzle.global_position).normalized()
	var angle := barrel_forward.angle_to(to_target)
	# Fire if within 5 degrees of target
	return angle < deg_to_rad(5.0)


func _fire() -> void:
	if bullet_scene == null:
		return

	var bullet: Bullet = bullet_scene.instantiate()

	# Set bullet properties from ammo type
	bullet.speed = ammo_type.bullet_speed
	bullet.damage = ammo_type.damage
	bullet.direction = -barrel.global_transform.basis.z

	# Add to scene tree first, then position at muzzle
	get_tree().root.add_child(bullet)
	bullet.global_position = muzzle.global_position

	fired.emit(bullet)


func set_target(new_target: Node3D) -> void:
	if target != new_target:
		target = new_target


func clear_target() -> void:
	target = null


func show_selection() -> void:
	if selection_ring == null:
		selection_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.5
		torus.outer_radius = 0.7
		torus.rings = 16
		torus.ring_segments = 32
		selection_ring.mesh = torus

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0, 1, 0.5, 0.8)
		material.emission_enabled = true
		material.emission = Color(0, 1, 0.5)
		material.emission_energy_multiplier = 2.0
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		selection_ring.material_override = material

		add_child(selection_ring)
		selection_ring.position = Vector3(0, 0.1, 0)

	selection_ring.visible = true


func hide_selection() -> void:
	if selection_ring:
		selection_ring.visible = false
