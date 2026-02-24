class_name AsteroidField
extends Node3D

const ASTEROID_RADIUS := 2.0
const NUM_HOLES := 3

var _mesh: MeshInstance3D
var _body: StaticBody3D
var _hole_markers: Array[Node3D] = []


func _ready() -> void:
	add_to_group("asteroid_fields")

	_body = StaticBody3D.new()
	_body.position = Vector3(0, 1.5, -18)
	_body.add_to_group("asteroids")
	_body.set_meta("radius", ASTEROID_RADIUS)
	add_child(_body)

	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ASTEROID_RADIUS
	sphere.height = ASTEROID_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.25, 0.2, 1)
	mat.roughness = 1.0
	sphere.material = mat
	mesh_inst.mesh = sphere
	mesh_inst.scale = Vector3(1.2, 0.8, 0.9)
	_body.add_child(mesh_inst)
	_mesh = mesh_inst

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = ASTEROID_RADIUS
	col.shape = shape
	_body.add_child(col)

	_create_holes()


func _create_holes() -> void:
	for i in NUM_HOLES:
		# Spread holes evenly around the equator with slight random tilt
		var angle := (float(i) / NUM_HOLES) * TAU + randf_range(-0.2, 0.2)
		var elevation := randf_range(-0.3, 0.3)
		var dir := Vector3(
			cos(angle) * cos(elevation),
			sin(elevation),
			sin(angle) * cos(elevation)
		).normalized()
		_hole_markers.append(_add_hole(dir))


func _add_hole(surface_dir: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.position = surface_dir * ASTEROID_RADIUS

	# Orient the marker so its local Y axis points outward along the surface normal,
	# which makes the flattened hole sphere sit flush against the surface.
	var up := surface_dir
	var arbitrary := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := up.cross(arbitrary).normalized()
	var fwd := right.cross(up).normalized()
	marker.transform.basis = Basis(right, up, fwd)

	_mesh.add_child(marker)

	# Dark cavity — very dark, slightly warm to suggest depth
	var cavity_mat := StandardMaterial3D.new()
	cavity_mat.albedo_color = Color(0.02, 0.01, 0.01)
	cavity_mat.emission_enabled = true
	cavity_mat.emission = Color(0.08, 0.03, 0.0)
	cavity_mat.emission_energy_multiplier = 0.8

	var cavity_mesh := SphereMesh.new()
	cavity_mesh.radius = 0.28
	cavity_mesh.height = 0.12
	cavity_mesh.radial_segments = 10
	cavity_mesh.rings = 4
	cavity_mesh.material = cavity_mat

	var cavity_inst := MeshInstance3D.new()
	cavity_inst.mesh = cavity_mesh
	marker.add_child(cavity_inst)

	# Warm glow rim — orange/red to suggest heat or bioluminescence inside
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.5, 0.2, 0.05, 0.7)
	rim_mat.emission_enabled = true
	rim_mat.emission = Color(0.7, 0.25, 0.02)
	rim_mat.emission_energy_multiplier = 2.0
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var rim_mesh := SphereMesh.new()
	rim_mesh.radius = 0.36
	rim_mesh.height = 0.07
	rim_mesh.radial_segments = 10
	rim_mesh.rings = 3
	rim_mesh.material = rim_mat

	var rim_inst := MeshInstance3D.new()
	rim_inst.mesh = rim_mesh
	marker.add_child(rim_inst)

	return marker


## Returns the current world position of a random hole (rotates with the asteroid).
func get_random_hole_position() -> Vector3:
	if _hole_markers.is_empty():
		return _body.global_position
	return _hole_markers[randi() % _hole_markers.size()].global_position


## Returns a random hole marker node (position updates live as asteroid rotates).
func get_random_hole_marker() -> Node3D:
	if _hole_markers.is_empty():
		return null
	return _hole_markers[randi() % _hole_markers.size()]


func _process(delta: float) -> void:
	_mesh.rotate(Vector3(0.3, 1.0, 0.2).normalized(), 0.5 * delta)
