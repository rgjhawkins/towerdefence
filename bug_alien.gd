class_name BugAlien
extends OrganicAlien
## Hive-defender bug. Patrols around its home asteroid, attacks collectors that
## come too close, and returns home when the threat moves away.

const SQUID_SCENE := preload("res://assets/squid_aliens/squid_alien.glb")
const MESH_SCALE  := 0.15

enum State { ATTACKING, RETURNING, ATTACHED, BURSTING, ORBITING }

const SPEED := 3.0
const BURST_SPEED := 9.0   # Fast outward scatter on spawn
const ORBIT_SPEED := 3.5   # Tangential speed while orbiting the asteroid
const RETURN_SPEED := 5.0
const ATTACH_DISTANCE := 0.6
const ABANDON_RANGE := 12.0   # Collector beyond this distance of HOME → bugs retreat
const HOLE_IDLE_DIST := 1.5   # How close to hole before considered "at rest"
const RETURN_TIMEOUT := 5.0   # Safety despawn if the bug can't find its hole in time
const ERRATIC_WEIGHT := 0.5
const WANDER_SHIFT_SPEED := 1.8
const CLOSE_DISTANCE := 5.0   # Within this range bugs fly straight at collector
const BUG_RADIUS := 0.15      # Used for asteroid collision push-out
const TURN_SPEED := 6.0       # Radians per second for rotation smoothing

var hole_marker: Node3D = null

var _state: State = State.BURSTING
var _home_pos: Vector3 = Vector3.ZERO
var _home_initialized: bool = false
var _burst_dir: Vector3 = Vector3.ZERO
var _burst_timer: float = 0.0
var _orbit_timer: float = 0.0
var _orbit_normal: Vector3 = Vector3.UP
var _return_timer: float = 0.0
var _age: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _mesh: Node3D = null  # Loaded squid GLB — scaled for idle pulse
var _body_mat: StandardMaterial3D = null
var _force_immediate_death: bool = false
var _on_surface: bool = false  # Set by _get_move_dir_to; suppresses erratic wander near asteroids


func _on_ready() -> void:
	_build_mesh()
	_wander_dir = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()


func _on_process(delta: float) -> void:
	# Home position resolved on first frame so global_position is already set
	if not _home_initialized:
		_home_pos = _find_home_asteroid()
		_home_initialized = true

	_age += delta

	# Burst direction needs global_position, so initialise here on first frame
	if _home_initialized and _burst_dir == Vector3.ZERO:
		var outward := (global_position - _home_pos).normalized()
		var scatter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_burst_dir = (outward + scatter * 1.2).normalized()
		_burst_timer = randf_range(0.4, 1.2)

	match _state:
		State.BURSTING:
			_do_burst(delta)
		State.ATTACKING:
			_do_attack(delta)
			_check_retreat()
		State.ORBITING:
			_do_orbit(delta)
		State.RETURNING:
			_do_return(delta)
		State.ATTACHED:
			_do_attached_idle()
			return  # Attached bugs are parented to the collector — skip collision

	_resolve_asteroid_collision()


# --- Burst ---

func _do_burst(delta: float) -> void:
	if _burst_dir == Vector3.ZERO:
		return  # Wait until direction is initialised
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_state = State.ATTACKING
		return
	# Gradually nudge the scatter direction with more random drift for a chaotic swarm feel
	var nudge := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_burst_dir = _burst_dir.lerp(nudge, 2.0 * delta).normalized()
	global_position += _burst_dir * BURST_SPEED * delta
	_smooth_look_at(_burst_dir, delta)


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

	var home_dir := _get_move_dir_to(collector.global_position)
	# Suppress erratic wander on asteroid surfaces — random nudges fight the tangent direction
	var erratic := 0.0 if _on_surface else ERRATIC_WEIGHT * clampf(dist / CLOSE_DISTANCE, 0.0, 1.0)
	var move_dir := home_dir.lerp(_wander_dir, erratic).normalized()

	global_position += move_dir * SPEED * delta
	_smooth_look_at(move_dir, delta)


func _check_retreat() -> void:
	var collector := _find_nearest_collector()
	if not collector or _home_pos.distance_to(collector.global_position) > ABANDON_RANGE:
		_start_orbit()


# --- Orbit ---

func _start_orbit() -> void:
	_state = State.ORBITING
	_orbit_timer = randf_range(5.0, 10.0)
	# Random orbit plane — ensure it's not parallel to the outward normal
	var outward := (global_position - _home_pos).normalized()
	var rand_vec := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_orbit_normal = outward.cross(rand_vec).normalized()
	if _orbit_normal.length_squared() < 0.01:
		_orbit_normal = outward.cross(Vector3.RIGHT).normalized()


func _do_orbit(delta: float) -> void:
	_orbit_timer -= delta
	if _orbit_timer <= 0.0:
		_state = State.RETURNING
		return
	# Re-engage if a ship enters threat range while patrolling
	var collector := _find_nearest_collector()
	if collector and _home_pos.distance_to(collector.global_position) <= ABANDON_RANGE:
		_state = State.ATTACKING
		return
	var outward := (global_position - _home_pos).normalized()
	var tangent := _orbit_normal.cross(outward).normalized()
	# Pull toward the asteroid when the bug has drifted far out (e.g. after a long chase)
	var dist := global_position.distance_to(_home_pos)
	var pull_weight := clampf((dist - 3.0) / 4.0, 0.0, 0.6)
	var move_dir := tangent.lerp(-outward, pull_weight).normalized()
	global_position += move_dir * ORBIT_SPEED * delta
	_smooth_look_at(move_dir, delta)


# --- Return ---

func _do_return(delta: float) -> void:
	# Hole gone (asteroid mined out) — no point navigating, just vanish
	if not hole_marker or not is_instance_valid(hole_marker):
		_force_immediate_death = true
		die()
		return
	_return_timer += delta
	var hole_pos := _get_hole_pos()
	var to_hole := hole_pos - global_position
	if to_hole.length() < HOLE_IDLE_DIST or _return_timer > RETURN_TIMEOUT:
		_force_immediate_death = true
		die()
		return
	var move_dir := _get_move_dir_to(hole_pos)
	global_position += move_dir * RETURN_SPEED * delta
	_smooth_look_at(move_dir, delta)


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

## Smoothly rotates the bug to face dir over time, avoiding snap-jitter.
func _smooth_look_at(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target_basis := Transform3D().looking_at(dir, Vector3.UP).basis
	var current_q := transform.basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	transform.basis = Basis(current_q.slerp(target_q, clampf(TURN_SPEED * delta, 0.0, 1.0)))


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


## Returns a movement direction toward target, steering over asteroid surfaces
## when the direct path is blocked. Sets _on_surface for callers.
func _get_move_dir_to(target: Vector3) -> Vector3:
	var direct := (target - global_position).normalized()
	var clearance := BUG_RADIUS + 0.05
	_on_surface = false
	# Within 3 units just fly direct — surface sliding degrades near the target
	# because axis ≈ surface_normal collapses the tangent, which prevents the bug
	# from closing in on a hole that sits on the asteroid surface.
	if global_position.distance_to(target) < 3.0:
		return direct
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as Node3D
		if not asteroid:
			continue
		var radius: float = asteroid.get_meta("radius", 1.0)
		var min_dist := radius + clearance
		var offset := global_position - asteroid.global_position
		var asteroid_dist := offset.length()
		var surface_normal := offset.normalized()
		# Only apply avoidance when the asteroid is actually in the way.
		if not _path_intersects_sphere(global_position, direct, asteroid.global_position, min_dist + 0.3):
			continue
		_on_surface = true
		if asteroid_dist < min_dist + 1.5:
			# On/near the surface with a blocked path — slide along the great-circle arc.
			# Axis from asteroid centre → target stays stable on the far side where
			# direct ≈ -surface_normal and the old bug→target projection zeroed out.
			var axis := (target - asteroid.global_position).normalized()
			var tangent := axis - axis.dot(surface_normal) * surface_normal
			if tangent.length_squared() > 0.0001:
				return tangent.normalized()
			# Near-antipodal fallback: any perpendicular direction will escape
			var perp := surface_normal.cross(Vector3.UP)
			if perp.length_squared() < 0.01:
				perp = surface_normal.cross(Vector3.FORWARD)
			return perp.normalized()
		else:
			# Blocked from a distance: head toward the near surface point to arc over
			var entry := asteroid.global_position + surface_normal * min_dist
			return (entry - global_position).normalized()
	return direct


## Returns true if the ray (origin, dir) intersects the sphere.
func _path_intersects_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> bool:
	var oc := origin - center
	var b := 2.0 * oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - 4.0 * c
	if disc < 0.0:
		return false
	var t2 := (-b + sqrt(disc)) * 0.5
	return t2 > 0.001


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
		_mesh.scale = Vector3.ONE * MESH_SCALE * pulse


func die() -> void:
	# Bugs returning to their hole or being cleared off the ship vanish immediately.
	# Bugs killed by weapon fire leave a drifting corpse (handled by OrganicAlien).
	if _force_immediate_death or _state == State.ATTACHED:
		is_alive = false
		died.emit(self)
		queue_free()
	else:
		start_corpse()


func _on_corpse_start() -> void:
	if _body_mat:
		_body_mat.emission_energy_multiplier = 0.08
		_body_mat.albedo_color = Color(0.02, 0.08, 0.02)  # dark dead green


# --- Visual ---

func _build_mesh() -> void:
	_mesh = SQUID_SCENE.instantiate() as Node3D
	# Rotate so mantle faces forward (-Z) and tentacles trail behind
	_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_mesh.scale = Vector3.ONE * MESH_SCALE
	add_child(_mesh)

	# Start idle animation from the GLB armature
	var anim := _mesh.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		if anim.has_animation("idle"):
			anim.play("idle")
		elif anim.get_animation_list().size() > 0:
			anim.play(anim.get_animation_list()[0])

	# Grab a per-instance duplicate of the body material for corpse tinting
	var mi := _find_mesh_instance(_mesh)
	if mi and mi.mesh and mi.mesh.get_surface_count() > 0:
		var mat := mi.get_active_material(0)
		if mat:
			_body_mat = mat.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(0, _body_mat)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_instance(child)
		if result:
			return result
	return null
