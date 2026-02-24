class_name MachinegunTurret
extends CollectorTurretBase
## Collector hardpoint turret: auto-aims and fires tracer rounds at the nearest
## alien within range. Skips aliens that are already attached to this ship.

const BULLET_SCENE := preload("res://bullet.tscn")
const BULLET_SPEED := 60.0
const BULLET_MAX_DIST := 20.0

@export var range: float = 8.0
const DAMAGE := 1.0
const BARREL_LENGTH := 0.25
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


func _process(delta: float) -> void:
	_time_since_shot += delta
	_acquire_target()
	if _target and is_instance_valid(_target):
		_track_target(delta)
		_try_fire()


func _acquire_target() -> void:
	var nearest: Node3D = null
	var nearest_dist := range
	for node in get_tree().get_nodes_in_group("aliens"):
		var alien := node as Node3D
		if not alien:
			continue
		if not ("is_alive" in alien and alien.is_alive):
			continue
		# Don't shoot bugs already attached to this ship
		if alien.get_parent() is CollectorShip:
			continue
		var d := global_position.distance_to(alien.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = alien
	_target = nearest


func _lead_position() -> Vector3:
	var target_pos := _target.global_position
	var muzzle_pos := _muzzle.global_position
	var target_vel := Vector3.ZERO
	if "velocity" in _target:
		target_vel = _target.velocity

	var rel := target_pos - muzzle_pos
	var a := target_vel.length_squared() - BULLET_SPEED * BULLET_SPEED
	var b := 2.0 * rel.dot(target_vel)
	var c := rel.length_squared()

	var t := 0.0
	if abs(a) < 0.001:
		if abs(b) > 0.001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = min(t1, t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2

	return target_pos + target_vel * clamp(t, 0.0, 3.0)


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
	# Squat base ring
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.22, 0.28)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.10
	base_mesh.bottom_radius = 0.13
	base_mesh.height = 0.07
	base_mesh.material = base_mat
	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	add_child(base_inst)

	# Barrel pivot (rotates to aim)
	_barrel = Node3D.new()
	add_child(_barrel)

	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.18, 0.18, 0.22)
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.03
	barrel_mesh.bottom_radius = 0.03
	barrel_mesh.height = BARREL_LENGTH
	barrel_mesh.material = barrel_mat
	var barrel_inst := MeshInstance3D.new()
	barrel_inst.mesh = barrel_mesh
	# Rotate so the cylinder points along -Z (forward)
	barrel_inst.rotation.x = PI / 2.0
	barrel_inst.position.z = -BARREL_LENGTH / 2.0
	_barrel.add_child(barrel_inst)

	# Muzzle marker at the barrel tip
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, 0.0, -BARREL_LENGTH)
	_barrel.add_child(_muzzle)
