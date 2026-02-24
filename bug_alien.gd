class_name BugAlien
extends OrganicAlien
## Hive-defender bug. Patrols around its home asteroid, attacks collectors that
## come too close, and returns home when the threat moves away.

enum State { PATROLLING, ATTACKING, RETURNING, ATTACHED, BURSTING, ORBITING }

const SPEED := 3.0
const BURST_SPEED := 9.0   # Fast outward scatter on spawn
const ORBIT_SPEED := 3.5   # Tangential speed while orbiting the asteroid
const RETURN_SPEED := 5.0
const ATTACH_DISTANCE := 0.6
const ATTACK_RANGE := 8.0     # Collector within this distance of HOME triggers attack
const ABANDON_RANGE := 12.0   # Collector beyond this distance of HOME → bugs retreat
const PATROL_LIFETIME := 10.0 # Seconds before an unengaged bug returns and despawns
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
var _patrol_timer: float = 0.0
var _burst_dir: Vector3 = Vector3.ZERO
var _burst_timer: float = 0.0
var _orbit_timer: float = 0.0
var _orbit_normal: Vector3 = Vector3.UP
var _return_timer: float = 0.0
var _age: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _mesh: Node3D = null  # Root container — scaled for idle pulse
var _body_mat: StandardMaterial3D = null
var _tent_mat: StandardMaterial3D = null
var _force_immediate_death: bool = false
var _on_surface: bool = false  # Set by _get_move_dir_to; suppresses erratic wander near asteroids
var _tent_root_pivots: Array[Node3D] = []
var _tent_mid_pivots: Array[Node3D] = []
var _tent_rest_transforms: Array[Transform3D] = []
var _tent_phases: Array[float] = []


func _on_ready() -> void:
	_build_mesh()
	_wander_dir = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()


func _on_process(delta: float) -> void:
	# Home position resolved on first frame so global_position is already set
	if not _home_initialized:
		_home_pos = _find_home_asteroid()
		_home_initialized = true

	_age += delta
	_animate_tentacles()

	# Burst direction needs global_position, so initialise here on first frame
	if _home_initialized and _burst_dir == Vector3.ZERO:
		var outward := (global_position - _home_pos).normalized()
		var scatter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_burst_dir = (outward + scatter * 1.2).normalized()
		_burst_timer = randf_range(0.4, 1.2)

	match _state:
		State.BURSTING:
			_do_burst(delta)
		State.PATROLLING:
			_do_patrol(delta)
			_check_for_threat()
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
		var move_dir := _get_move_dir_to(hole_pos)
		global_position += move_dir * SPEED * delta
		_smooth_look_at(move_dir, delta)
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
		_mesh.scale = Vector3.ONE * pulse


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
		_body_mat.emission_energy_multiplier = 0.15
		_body_mat.albedo_color = Color(0.06, 0.02, 0.10)
	if _tent_mat:
		_tent_mat.emission_energy_multiplier = 0.08
		_tent_mat.albedo_color = Color(0.08, 0.03, 0.14)


# --- Visual ---

func _build_mesh() -> void:
	# Root container — whole squid scales together during the idle pulse
	_mesh = Node3D.new()
	add_child(_mesh)

	# Body: deep violet, purple glow
	_body_mat = StandardMaterial3D.new()
	var body_mat := _body_mat
	body_mat.albedo_color = Color(0.12, 0.04, 0.28)
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.45, 0.0, 0.75)
	body_mat.emission_energy_multiplier = 1.0
	body_mat.roughness = 0.3
	body_mat.metallic = 0.3

	# Tentacles: slightly lighter purple
	_tent_mat = StandardMaterial3D.new()
	var tent_mat := _tent_mat
	tent_mat.albedo_color = Color(0.20, 0.06, 0.38)
	tent_mat.emission_enabled = true
	tent_mat.emission = Color(0.28, 0.0, 0.58)
	tent_mat.emission_energy_multiplier = 0.7

	# Eyes: glowing cyan
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.0, 0.75, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.0, 0.85, 1.0)
	eye_mat.emission_energy_multiplier = 5.0

	# Fins: semi-transparent violet
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.30, 0.05, 0.55, 0.38)
	fin_mat.emission_enabled = true
	fin_mat.emission = Color(0.4, 0.0, 0.7)
	fin_mat.emission_energy_multiplier = 0.5
	fin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Mantle — elongated teardrop, tapers at the rear (+Z)
	var mantle_s := SphereMesh.new()
	mantle_s.radius = 0.12
	mantle_s.height = 0.30
	mantle_s.radial_segments = 10
	mantle_s.rings = 6
	mantle_s.material = body_mat
	var mantle := MeshInstance3D.new()
	mantle.mesh = mantle_s
	mantle.position = Vector3(0.0, 0.0, 0.08)
	mantle.scale = Vector3(1.0, 0.85, 1.0)
	_mesh.add_child(mantle)

	# Head — slightly wider bulge at the front, connects to tentacles
	var head_s := SphereMesh.new()
	head_s.radius = 0.10
	head_s.height = 0.17
	head_s.radial_segments = 10
	head_s.rings = 5
	head_s.material = body_mat
	var head := MeshInstance3D.new()
	head.mesh = head_s
	head.position = Vector3(0.0, 0.0, -0.09)
	head.scale = Vector3(1.18, 0.9, 1.0)
	_mesh.add_child(head)

	# Compound eyes — large glowing cyan spheres
	for side: int in [-1, 1]:
		var eye_s := SphereMesh.new()
		eye_s.radius = 0.036
		eye_s.height = 0.055
		eye_s.radial_segments = 7
		eye_s.rings = 4
		eye_s.material = eye_mat
		var eye := MeshInstance3D.new()
		eye.mesh = eye_s
		eye.position = Vector3(side * 0.082, 0.022, -0.12)
		_mesh.add_child(eye)

	# Side fins — flat translucent ovals swept back along the mantle
	for side: int in [-1, 1]:
		var fin_s := SphereMesh.new()
		fin_s.radius = 0.09
		fin_s.height = 0.022
		fin_s.radial_segments = 8
		fin_s.rings = 3
		fin_s.material = fin_mat
		var fin := MeshInstance3D.new()
		fin.mesh = fin_s
		fin.position = Vector3(side * 0.14, 0.0, 0.05)
		fin.scale = Vector3(1.0, 1.0, 1.9)
		_mesh.add_child(fin)

	# Tentacles — 8 pivot-based segments so they can be animated each frame
	const SEG1_LEN := 0.26
	const SEG2_LEN := 0.22
	for i: int in 8:
		var ring_angle := (float(i) / 8.0) * TAU
		_tent_phases.append(randf() * TAU)

		var out := Vector3(cos(ring_angle), sin(ring_angle), 0.0)
		var base_pos := Vector3(out.x * 0.058, out.y * 0.058, -0.16)

		# Initial tentacle direction: outward + forward
		var tent_dir := (out * 0.18 + Vector3(0.0, 0.0, -0.18)).normalized()

		# Orient pivot so its local -Y points along tent_dir
		var local_y := -tent_dir
		var ref := Vector3.FORWARD if abs(local_y.dot(Vector3.UP)) > 0.9 else Vector3.UP
		var local_x := ref.cross(local_y).normalized()
		var local_z := local_x.cross(local_y).normalized()

		var root_pivot := Node3D.new()
		root_pivot.transform = Transform3D(Basis(local_x, local_y, local_z), base_pos)
		_mesh.add_child(root_pivot)
		_tent_root_pivots.append(root_pivot)
		_tent_rest_transforms.append(root_pivot.transform)

		# Root segment — hangs along pivot's local -Y
		var root_cyl := CylinderMesh.new()
		root_cyl.top_radius = 0.011
		root_cyl.bottom_radius = 0.020
		root_cyl.height = SEG1_LEN
		root_cyl.material = tent_mat
		var root_inst := MeshInstance3D.new()
		root_inst.mesh = root_cyl
		root_inst.position = Vector3(0.0, -SEG1_LEN * 0.5, 0.0)
		root_pivot.add_child(root_inst)

		# Mid pivot at the tip of the root segment
		var mid_pivot := Node3D.new()
		mid_pivot.position = Vector3(0.0, -SEG1_LEN, 0.0)
		root_pivot.add_child(mid_pivot)
		_tent_mid_pivots.append(mid_pivot)

		# Tip segment — hangs along mid_pivot's local -Y
		var tip_cyl := CylinderMesh.new()
		tip_cyl.top_radius = 0.004
		tip_cyl.bottom_radius = 0.011
		tip_cyl.height = SEG2_LEN
		tip_cyl.material = tent_mat
		var tip_inst := MeshInstance3D.new()
		tip_inst.mesh = tip_cyl
		tip_inst.position = Vector3(0.0, -SEG2_LEN * 0.5, 0.0)
		mid_pivot.add_child(tip_inst)


func _animate_tentacles() -> void:
	for i in _tent_root_pivots.size():
		var phase := _tent_phases[i]
		# Sway the whole tentacle with two independent sine waves
		var sway_x := sin(_age * 2.1 + phase) * deg_to_rad(22.0)
		var sway_z := sin(_age * 1.6 + phase + 1.3) * deg_to_rad(16.0)
		var sway := Basis.from_euler(Vector3(sway_x, 0.0, sway_z))
		_tent_root_pivots[i].transform = Transform3D(
			_tent_rest_transforms[i].basis * sway,
			_tent_rest_transforms[i].origin
		)
		# Curl the tip with a slight phase offset for a wave-like feel
		var curl_x := sin(_age * 2.6 + phase + 0.9) * deg_to_rad(28.0)
		var curl_z := sin(_age * 1.9 + phase + 2.2) * deg_to_rad(18.0)
		_tent_mid_pivots[i].transform.basis = Basis.from_euler(Vector3(curl_x, 0.0, curl_z))
