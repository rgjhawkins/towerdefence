class_name BugAlien
extends Alien
## Small green bug that emerges from mined asteroids, swarms toward the nearest
## collector ship, attaches to its hull, and slows thrust and rotation by 3% per bug.

enum State { SWARMING, ATTACHED }

const SPEED := 3.0
const ATTACH_DISTANCE := 0.6
const ERRATIC_WEIGHT := 0.5       # 0 = pure homing, 1 = pure wander
const WANDER_SHIFT_SPEED := 1.8   # How fast the random wander direction drifts
const CLOSE_DISTANCE := 5.0       # Within this range bugs fly straight at the collector

var _state: State = State.SWARMING
var _age: float = 0.0
var _mesh: MeshInstance3D = null
var _wander_dir: Vector3 = Vector3.ZERO


func _on_ready() -> void:
	_build_mesh()
	# Seed a random initial wander direction so each bug diverges immediately
	_wander_dir = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()


func _on_process(delta: float) -> void:
	_age += delta
	match _state:
		State.SWARMING:
			_do_swarm(delta)
		State.ATTACHED:
			_do_attached_idle()


# --- Movement ---

func _do_swarm(delta: float) -> void:
	var collector := _find_nearest_collector()
	if not collector:
		return

	var to_target := collector.global_position - global_position
	var dist := to_target.length()

	if dist < ATTACH_DISTANCE:
		_attach(collector)
		return

	# Smoothly drift the wander direction toward a new random target each frame
	var random_nudge := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	_wander_dir = _wander_dir.lerp(random_nudge, WANDER_SHIFT_SPEED * delta).normalized()

	# Blend homing direction with the erratic wander.
	# Erratic weight fades to zero as the bug closes in on the collector.
	var home_dir := to_target.normalized()
	var erratic := ERRATIC_WEIGHT * clampf(dist / CLOSE_DISTANCE, 0.0, 1.0)
	var move_dir := home_dir.lerp(_wander_dir, erratic).normalized()

	global_position += move_dir * SPEED * delta

	if move_dir.length() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)


func _find_nearest_collector() -> CollectorShip:
	var nearest: CollectorShip = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("collectors"):
		var collector := node as CollectorShip
		if not collector:
			continue
		var d := global_position.distance_to(collector.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = collector
	return nearest


# --- Attachment ---

func _attach(collector: CollectorShip) -> void:
	_state = State.ATTACHED
	collector.attach_bug(self)

	# Reparent so the bug moves with the ship
	reparent(collector, true)

	# Snap to a random point on the hull surface
	position = Vector3(
		randf_range(-0.4, 0.4),
		randf_range(-0.15, 0.15),
		randf_range(-0.4, 0.4)
	)
	rotation = Vector3.ZERO


func _do_attached_idle() -> void:
	# Gentle pulse to show the bug is alive
	if _mesh:
		var pulse := 1.0 + sin(_age * 6.0) * 0.05
		_mesh.scale = Vector3.ONE * pulse


# --- Visual ---

func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.8, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 1.5

	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.17  # Slightly squished for a bug silhouette
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = mat

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	add_child(_mesh)
