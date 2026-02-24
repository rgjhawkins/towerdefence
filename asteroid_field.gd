class_name AsteroidField
extends Node3D

var _mesh: MeshInstance3D
var _body: StaticBody3D


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.position = Vector3(0, 1.5, -18)
	_body.add_to_group("asteroids")
	_body.set_meta("radius", 2.0)
	add_child(_body)

	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
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
	shape.radius = 2.0
	col.shape = shape
	_body.add_child(col)


func _process(delta: float) -> void:
	_mesh.rotate(Vector3(0.3, 1.0, 0.2).normalized(), 0.5 * delta)
