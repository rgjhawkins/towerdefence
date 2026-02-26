class_name AsteroidField
extends Node3D

const ASTEROID_RADIUS := 2.0
const NUM_HOLES := 3

var _mesh: Node3D
var _body: StaticBody3D
var _hole_markers: Array[Node3D] = []


func _ready() -> void:
	add_to_group("asteroid_fields")

	_body = StaticBody3D.new()
	_body.position = Vector3(0, 1.5, -18)
	_body.add_to_group("asteroids")
	_body.set_meta("radius", ASTEROID_RADIUS)
	add_child(_body)

	var variant := randi() % 30
	var asteroid_scene: PackedScene = load("res://assets/asteroids/asteroid_%02d.glb" % variant)
	var mesh_inst := asteroid_scene.instantiate() as Node3D
	mesh_inst.scale = Vector3.ONE * ASTEROID_RADIUS
	_body.add_child(mesh_inst)
	_mesh = mesh_inst

	var col := CollisionShape3D.new()
	var mi: MeshInstance3D = null
	for child in mesh_inst.get_children():
		if child is MeshInstance3D:
			mi = child
			break
	if mi:
		var trimesh := mi.mesh.create_trimesh_shape() as ConcavePolygonShape3D
		var faces := trimesh.get_faces()
		for i in faces.size():
			faces[i] *= ASTEROID_RADIUS
		trimesh.set_faces(faces)
		col.shape = trimesh
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = ASTEROID_RADIUS
		col.shape = sphere
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
	_body.rotate(Vector3(0.3, 1.0, 0.2).normalized(), 0.5 * delta)
