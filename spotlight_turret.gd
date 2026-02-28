class_name SpotlightTurret
extends "res://collector_turret_base.gd"
## Underside-mounted industrial searchlight that tracks and illuminates
## the nearest asteroid within range. No weapons — just light.

@export var target_range: float = 30.0
@export var tracking_speed: float = 80.0  # Degrees per second

const HOUSING_LENGTH := 0.20  # Metres along -Z from pivot centre

var _pivot: Node3D = null
var _light: SpotLight3D = null
var _target: Node3D = null


func get_turret_name() -> String:
	return "Spotlight"


func _ready() -> void:
	_build_mesh()


func _update(delta: float) -> void:
	_acquire_target()
	if _target and is_instance_valid(_target):
		_track_target(delta)
		_light.visible = true
	else:
		_light.visible = false


func _acquire_target() -> void:
	var nearest: Node3D = null
	var nearest_dist := target_range
	for node in get_tree().get_nodes_in_group("asteroids"):
		var body := node as Node3D
		if not body:
			continue
		var d := global_position.distance_to(body.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = body
	_target = nearest


func _track_target(delta: float) -> void:
	if _pivot.global_position.is_equal_approx(_target.global_position):
		return
	var cq := _pivot.global_transform.basis.get_rotation_quaternion()
	var tq := _pivot.global_transform.looking_at(
		_target.global_position, Vector3.UP
	).basis.get_rotation_quaternion()
	var angle_diff := cq.angle_to(tq)
	if angle_diff < 0.001:
		return
	var max_rot := deg_to_rad(tracking_speed) * delta
	var w := minf(max_rot / angle_diff, 1.0)
	_pivot.global_transform.basis = Basis(cq.slerp(tq, w))


func _build_mesh() -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.18, 0.18, 0.22)
	hull_mat.metallic    = 0.75
	hull_mat.roughness   = 0.40

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color              = Color(0.9, 0.75, 0.2, 1.0)
	accent_mat.metallic                  = 0.6
	accent_mat.roughness                 = 0.4
	accent_mat.emission_enabled          = true
	accent_mat.emission                  = Color(1.0, 0.85, 0.3, 1.0)
	accent_mat.emission_energy_multiplier = 1.5

	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color              = Color(0.85, 0.92, 1.0, 1.0)
	lens_mat.metallic                  = 0.1
	lens_mat.roughness                 = 0.05
	lens_mat.emission_enabled          = true
	lens_mat.emission                  = Color(0.8, 0.9, 1.0)
	lens_mat.emission_energy_multiplier = 5.0

	# ── Static base (mounts flush to hull underside) ──────────────────────────

	# Outer flange ring
	var flange_m := CylinderMesh.new()
	flange_m.top_radius    = 0.11
	flange_m.bottom_radius = 0.13
	flange_m.height        = 0.03
	flange_m.material      = hull_mat
	var flange_i := MeshInstance3D.new()
	flange_i.mesh       = flange_m
	flange_i.position.y = -0.015
	add_child(flange_i)

	# Yellow accent ring
	var accent_m := CylinderMesh.new()
	accent_m.top_radius    = 0.095
	accent_m.bottom_radius = 0.110
	accent_m.height        = 0.015
	accent_m.material      = accent_mat
	var accent_i := MeshInstance3D.new()
	accent_i.mesh       = accent_m
	accent_i.position.y = -0.038
	add_child(accent_i)

	# Stub column connecting flange to pivot
	var stub_m := CylinderMesh.new()
	stub_m.top_radius    = 0.048
	stub_m.bottom_radius = 0.048
	stub_m.height        = 0.07
	stub_m.material      = hull_mat
	var stub_i := MeshInstance3D.new()
	stub_i.mesh       = stub_m
	stub_i.position.y = -0.08
	add_child(stub_i)

	# ── Pivot (rotates to track target) ──────────────────────────────────────

	_pivot = Node3D.new()
	_pivot.position.y = -0.115
	add_child(_pivot)

	# Swivel ball joint at pivot origin
	var ball_m := SphereMesh.new()
	ball_m.radius   = 0.052
	ball_m.height   = 0.104
	ball_m.material = hull_mat
	var ball_i := MeshInstance3D.new()
	ball_i.mesh = ball_m
	_pivot.add_child(ball_i)

	# Housing body — cylinder along -Z
	var housing_m := CylinderMesh.new()
	housing_m.top_radius    = 0.052
	housing_m.bottom_radius = 0.060
	housing_m.height        = HOUSING_LENGTH
	housing_m.material      = hull_mat
	var housing_i := MeshInstance3D.new()
	housing_i.mesh       = housing_m
	housing_i.rotation.x = PI / 2.0
	housing_i.position.z = -HOUSING_LENGTH * 0.5
	_pivot.add_child(housing_i)

	# Wide lens shroud at the front tip
	var shroud_m := CylinderMesh.new()
	shroud_m.top_radius    = 0.075
	shroud_m.bottom_radius = 0.065
	shroud_m.height        = 0.028
	shroud_m.material      = hull_mat
	var shroud_i := MeshInstance3D.new()
	shroud_i.mesh       = shroud_m
	shroud_i.rotation.x = PI / 2.0
	shroud_i.position.z = -HOUSING_LENGTH - 0.014
	_pivot.add_child(shroud_i)

	# Glowing lens disc
	var lens_m := CylinderMesh.new()
	lens_m.top_radius    = 0.058
	lens_m.bottom_radius = 0.058
	lens_m.height        = 0.008
	lens_m.material      = lens_mat
	var lens_i := MeshInstance3D.new()
	lens_i.mesh       = lens_m
	lens_i.rotation.x = PI / 2.0
	lens_i.position.z = -HOUSING_LENGTH - 0.004
	_pivot.add_child(lens_i)

	# ── SpotLight3D ───────────────────────────────────────────────────────────

	_light = SpotLight3D.new()
	_light.position.z               = -HOUSING_LENGTH - 0.03
	_light.spot_range               = 28.0
	_light.spot_angle               = 10.0
	_light.spot_angle_attenuation   = 0.5
	_light.light_color              = Color(0.90, 0.95, 1.0)
	_light.light_energy             = 5.0
	_light.shadow_enabled           = true
	_pivot.add_child(_light)
