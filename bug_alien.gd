class_name BugAlien
extends Alien
## Small green bug that emerges from mined asteroids, swarms toward the nearest
## collector ship, attaches to its hull, and slows thrust and rotation by 3% per bug.

enum State { SWARMING, ATTACHED }

const SPEED := 8.0
const ATTACH_DISTANCE := 0.6
const WOBBLE_STRENGTH := 0.5
const WOBBLE_FREQ := 3.0

var _state: State = State.SWARMING
var _age: float = 0.0
var _mesh: MeshInstance3D = null


func _on_ready() -> void:
	_build_mesh()


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

	# Fly toward collector with a sine-wave wobble for organic feel
	var dir := to_target.normalized()
	var wobble_axis := dir.cross(Vector3.UP)
	if wobble_axis.length() < 0.01:
		wobble_axis = Vector3.RIGHT
	wobble_axis = wobble_axis.normalized()
	var wobble := wobble_axis * sin(_age * WOBBLE_FREQ) * WOBBLE_STRENGTH
	var move_dir := (dir + wobble * delta).normalized()

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
