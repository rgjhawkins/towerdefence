class_name MachinegunTurret
extends "res://collector_turret_base.gd"
## Collector hardpoint turret: auto-aims and fires tracer rounds at the nearest
## alien within range. Skips aliens that are already attached to this ship.

const BULLET_SCENE := preload("res://bullet.tscn")
const BULLET_SPEED := 60.0
const BULLET_MAX_DIST := 20.0

@export var target_range: float = 8.0
const DAMAGE := 1.0
const BARREL_LENGTH := 0.50
const AIM_THRESHOLD := 5.0      # Degrees — must be this close to fire

@export var rpm: float = 200.0          # Rounds per minute
@export var tracking_speed: float = 240.0  # Degrees per second barrel rotation
@export var aim_deviation: float = 5.0  # Max spread cone half-angle in degrees

var _barrel: Node3D = null
var _muzzle: Node3D = null
var _time_since_shot: float = 0.0
var _target: Node3D = null
var _shot_player: AudioStreamPlayer = null


func get_turret_name() -> String:
	return "Machinegun"

func get_icon_color() -> Color:
	return Color(0.95, 0.65, 0.1)

func _on_deactivated() -> void:
	_target = null


func _ready() -> void:
	_build_mesh()
	_setup_audio()


func _setup_audio() -> void:
	_shot_player = AudioStreamPlayer.new()
	_shot_player.stream = _build_shot_sound()
	_shot_player.volume_db = 0.0
	add_child(_shot_player)


## Builds a short synthetic gunshot: white-noise crack + low bass thump, ~100 ms.
func _build_shot_sound() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 0.10
	var num_samples := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit mono PCM
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Fixed seed so every turret sounds identical
	for i in num_samples:
		var t := float(i) / SAMPLE_RATE
		# Crack: white noise with sharp exponential decay
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0)
		# Thump: low sine wave that decays a bit slower
		var thump := sin(t * TAU * 90.0) * exp(-t * 30.0) * 0.5
		var sample := clampi(int((crack + thump) * 28000.0), -32768, 32767)
		data[i * 2]     = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	return wav


func _update(delta: float) -> void:
	_time_since_shot += delta
	if _target and not is_instance_valid(_target):
		_release_target()
		_target = null
	_acquire_target()
	if _target and is_instance_valid(_target):
		_track_target(delta)
		_try_fire()


func _acquire_target() -> void:
	var nearest: Node3D = null
	var nearest_dist := target_range
	for node in get_tree().get_nodes_in_group("aliens"):
		var alien := node as Node3D
		if not alien:
			continue
		if not ("is_alive" in alien and alien.is_alive):
			continue
		# Don't shoot bugs already attached to this ship
		if alien.get_parent() is CollectorShip:
			continue
		# Skip targets already claimed by another turret
		if Turret.is_claimed(alien) and _claimed.get(alien) != self:
			continue
		var d := global_position.distance_to(alien.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = alien

	if nearest != _target:
		if nearest:
			_claim_target(nearest)
		else:
			_release_target()
		_target = nearest


func _lead_position() -> Vector3:
	var target_vel := Vector3.ZERO
	if "velocity" in _target:
		target_vel = _target.velocity
	return TurretUtils.lead_position(_muzzle.global_position, _target.global_position, target_vel, BULLET_SPEED)


func _track_target(delta: float) -> void:
	var aim := _lead_position()
	var cq := _barrel.global_transform.basis.get_rotation_quaternion()
	var tq := _barrel.global_transform.looking_at(aim, Vector3.UP).basis.get_rotation_quaternion()
	var angle_diff := cq.angle_to(tq)
	var max_rot := deg_to_rad(tracking_speed) * delta
	var w: float = 1.0 if angle_diff < 0.001 else minf(max_rot / angle_diff, 1.0)
	_barrel.global_transform.basis = Basis(cq.slerp(tq, w))


func _try_fire() -> void:
	if _time_since_shot < 60.0 / rpm:
		return
	var aim := _lead_position()
	var fwd := -_barrel.global_transform.basis.z.normalized()
	var to_aim := (aim - _muzzle.global_position).normalized()
	if fwd.angle_to(to_aim) > deg_to_rad(AIM_THRESHOLD):
		return
	_fire()
	_time_since_shot = 0.0


func _fire() -> void:
	_drain_energy(5.0)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.speed = BULLET_SPEED
	bullet.damage = DAMAGE
	bullet.max_distance = BULLET_MAX_DIST

	# Apply random spread cone of ±aim_deviation degrees
	var fwd := -_barrel.global_transform.basis.z.normalized()
	var perp := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	perp = (perp - perp.dot(fwd) * fwd).normalized()
	bullet.direction = fwd.rotated(perp, deg_to_rad(randf_range(-aim_deviation, aim_deviation)))
	bullet.hit_radius = 0.4
	get_tree().root.add_child(bullet)
	bullet.global_position = _muzzle.global_position
	_spawn_muzzle_flash()
	if _shot_player:
		_shot_player.play()


func _spawn_muzzle_flash() -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 6.0
	sphere.material = mat
	flash.mesh = sphere
	get_tree().root.add_child(flash)
	flash.global_position = _muzzle.global_position
	await get_tree().process_frame
	if is_instance_valid(flash):
		flash.queue_free()


func _build_mesh() -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.18, 0.18, 0.22)
	hull_mat.metallic = 0.75
	hull_mat.roughness = 0.40

	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.32, 0.32, 0.38)
	barrel_mat.metallic = 0.90
	barrel_mat.roughness = 0.20

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.9, 0.5, 0.1, 1.0)
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(1.0, 0.6, 0.1, 1.0)
	accent_mat.emission_energy_multiplier = 2.5

	# ── Static base ───────────────────────────────────────────────────────────

	# Base plate — wide cone frustum
	var base_m := CylinderMesh.new()
	base_m.top_radius    = 0.22
	base_m.bottom_radius = 0.26
	base_m.height        = 0.08
	base_m.material      = hull_mat
	var base_i := MeshInstance3D.new()
	base_i.mesh = base_m
	add_child(base_i)

	# Glowing accent ring on top edge of base
	var ring_m := CylinderMesh.new()
	ring_m.top_radius    = 0.19
	ring_m.bottom_radius = 0.21
	ring_m.height        = 0.03
	ring_m.material      = accent_mat
	var ring_i := MeshInstance3D.new()
	ring_i.mesh       = ring_m
	ring_i.position.y = 0.055
	add_child(ring_i)

	# ── Rotating barrel assembly ───────────────────────────────────────────────

	_barrel = Node3D.new()
	_barrel.position.y = 0.07
	add_child(_barrel)

	# Octagonal gun housing (rotates with barrel so aiming is clearly visible)
	var housing_m := CylinderMesh.new()
	housing_m.top_radius      = 0.14
	housing_m.bottom_radius   = 0.16
	housing_m.height          = 0.11
	housing_m.radial_segments = 8
	housing_m.material        = hull_mat
	var housing_i := MeshInstance3D.new()
	housing_i.mesh = housing_m
	_barrel.add_child(housing_i)

	# Barrel jacket — thick outer sleeve at the breech end
	var jacket_m := CylinderMesh.new()
	jacket_m.top_radius    = 0.07
	jacket_m.bottom_radius = 0.08
	jacket_m.height        = 0.24
	jacket_m.material      = hull_mat
	var jacket_i := MeshInstance3D.new()
	jacket_i.mesh       = jacket_m
	jacket_i.rotation.x = PI / 2.0
	jacket_i.position.z = -0.12       # extends from z=0 to z=-0.24
	_barrel.add_child(jacket_i)

	# Main barrel — thinner, runs full length
	var barrel_m := CylinderMesh.new()
	barrel_m.top_radius    = 0.044
	barrel_m.bottom_radius = 0.044
	barrel_m.height        = BARREL_LENGTH
	barrel_m.material      = barrel_mat
	var barrel_i := MeshInstance3D.new()
	barrel_i.mesh       = barrel_m
	barrel_i.rotation.x = PI / 2.0
	barrel_i.position.z = -BARREL_LENGTH / 2.0
	_barrel.add_child(barrel_i)

	# Muzzle brake — wider ring at the barrel tip
	var brake_m := CylinderMesh.new()
	brake_m.top_radius    = 0.065
	brake_m.bottom_radius = 0.065
	brake_m.height        = 0.05
	brake_m.material      = barrel_mat
	var brake_i := MeshInstance3D.new()
	brake_i.mesh       = brake_m
	brake_i.rotation.x = PI / 2.0
	brake_i.position.z = -BARREL_LENGTH - 0.025
	_barrel.add_child(brake_i)

	# Muzzle marker at the very tip (bullets spawn here)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, 0.0, -BARREL_LENGTH - 0.05)
	_barrel.add_child(_muzzle)
