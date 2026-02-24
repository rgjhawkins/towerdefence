class_name BugAlien
extends Alien
## Hive-defender bug. Patrols around its home asteroid, attacks collectors that
## come too close, and returns home when the threat moves away.

enum State { PATROLLING, ATTACKING, RETURNING, ATTACHED }

const SPEED := 3.0
const RETURN_SPEED := 5.0
const ATTACH_DISTANCE := 0.6
const ATTACK_RANGE := 8.0     # Collector within this distance of HOME triggers attack
const ABANDON_RANGE := 12.0   # Collector beyond this distance of HOME → bugs retreat
const PATROL_LIFETIME := 10.0 # Seconds before an unengaged bug returns and despawns
const HOLE_IDLE_DIST := 0.5   # How close to hole before considered "at rest"
const ERRATIC_WEIGHT := 0.5
const WANDER_SHIFT_SPEED := 1.8
const CLOSE_DISTANCE := 5.0   # Within this range bugs fly straight at collector
const BUG_RADIUS := 0.15      # Used for asteroid collision push-out

var hole_marker: Node3D = null

var _state: State = State.PATROLLING
var _home_pos: Vector3 = Vector3.ZERO
var _home_initialized: bool = false
var _patrol_timer: float = 0.0
var _age: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _mesh: MeshInstance3D = null


func _on_ready() -> void:
	_build_mesh()
	_wander_dir = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()


func _on_process(delta: float) -> void:
	# Home position resolved on first frame so global_position is already set
	if not _home_initialized:
		_home_pos = _find_home_asteroid()
		_home_initialized = true

	_age += delta

	match _state:
		State.PATROLLING:
			_do_patrol(delta)
			_check_for_threat()
		State.ATTACKING:
			_do_attack(delta)
			_check_retreat()
		State.RETURNING:
			_do_return(delta)
		State.ATTACHED:
			_do_attached_idle()
			return  # Attached bugs are parented to the collector — skip collision

	_resolve_asteroid_collision()


# --- Patrol ---

func _do_patrol(delta: float) -> void:
	_patrol_timer += delta
	if _patrol_timer >= PATROL_LIFETIME:
		_state = State.RETURNING
		return

	# Move toward hole; idle (bob gently) once close
	var hole_pos := _get_hole_pos()
	var to_hole := hole_pos - global_position
	if to_hole.length() > HOLE_IDLE_DIST:
		var move_dir := to_hole.normalized()
		global_position += move_dir * SPEED * delta
		look_at(global_position + move_dir, Vector3.UP)
	else:
		# Gentle idle hover in place
		global_position.y += sin(_age * 2.5) * 0.002


func _check_for_threat() -> void:
	var collector := _find_nearest_collector()
	if not collector:
		return
	if _home_pos.distance_to(collector.global_position) < ATTACK_RANGE:
		_state = State.ATTACKING


# --- Attack ---

func _do_attack(delta: float) -> void:
	var collector := _find_nearest_collector()
	if not collector:
		_state = State.RETURNING
		return

	var to_collector := collector.global_position - global_position
	var dist := to_collector.length()

	if dist < ATTACH_DISTANCE:
		_attach(collector)
		return

	# Erratic wander blended with homing; fades to direct when close
	var random_nudge := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	_wander_dir = _wander_dir.lerp(random_nudge, WANDER_SHIFT_SPEED * delta).normalized()

	var home_dir := to_collector.normalized()
	var erratic := ERRATIC_WEIGHT * clampf(dist / CLOSE_DISTANCE, 0.0, 1.0)
	var move_dir := home_dir.lerp(_wander_dir, erratic).normalized()

	global_position += move_dir * SPEED * delta
	if move_dir.length() > 0.01:
		look_at(global_position + move_dir, Vector3.UP)


func _check_retreat() -> void:
	var collector := _find_nearest_collector()
	if not collector or _home_pos.distance_to(collector.global_position) > ABANDON_RANGE:
		_state = State.RETURNING


# --- Return ---

func _do_return(delta: float) -> void:
	var hole_pos := _get_hole_pos()
	var to_hole := hole_pos - global_position
	if to_hole.length() < HOLE_IDLE_DIST:
		die()
		return
	var move_dir := to_hole.normalized()
	global_position += move_dir * RETURN_SPEED * delta
	look_at(global_position + move_dir, Vector3.UP)


# --- Collision ---

func _resolve_asteroid_collision() -> void:
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as Node3D
		if not asteroid:
			continue
		var asteroid_radius: float = asteroid.get_meta("radius", 1.0)
		var min_dist := asteroid_radius + BUG_RADIUS
		var offset := global_position - asteroid.global_position
		var dist := offset.length()
		if dist < min_dist and dist > 0.001:
			global_position = asteroid.global_position + offset.normalized() * min_dist


# --- Helpers ---

## Returns the live world position of this bug's assigned hole, falling back to home asteroid.
func _get_hole_pos() -> Vector3:
	if hole_marker and is_instance_valid(hole_marker):
		return hole_marker.global_position
	return _home_pos


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


func _find_home_asteroid() -> Vector3:
	var nearest_dist := INF
	var result := global_position
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as Node3D
		if not asteroid:
			continue
		var d := global_position.distance_to(asteroid.global_position)
		if d < nearest_dist:
			nearest_dist = d
			result = asteroid.global_position
	return result


# --- Attachment ---

func _attach(collector: CollectorShip) -> void:
	_state = State.ATTACHED
	collector.attach_bug(self)
	reparent(collector, true)
	position = Vector3(
		randf_range(-0.4, 0.4),
		randf_range(-0.15, 0.15),
		randf_range(-0.4, 0.4)
	)
	rotation = Vector3.ZERO


func _do_attached_idle() -> void:
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
	sphere.height = 0.17
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = mat

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	add_child(_mesh)
