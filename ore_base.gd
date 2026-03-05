class_name OreBase
extends Node3D
## Base class for all collectible ore pieces.
## Handles drift, tumble, fade-out, and group membership.
## Subclasses override ore_type and value, and can customise appearance.

@export var ore_type: String = "generic"
@export var value:    int    = 1

@export var drift_speed:    float = 0.5
@export var rotation_speed: float = 2.0
@export var lifespan:       float = 30.0
@export var fade_duration:  float = 3.0

var drift_direction: Vector3
var age: float = 0.0
var mesh_node: Node = null
var original_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("ore")

	drift_direction = Vector3(
		randf_range(-1, 1), 0, randf_range(-1, 1)
	).normalized() * drift_speed

	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	mesh_node = get_node_or_null("Mesh")
	if mesh_node and mesh_node.material:
		original_material = mesh_node.material.duplicate()
		original_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_node.material = original_material


func _process(delta: float) -> void:
	age += delta
	if age >= lifespan:
		queue_free()
		return

	var fade_start := lifespan - fade_duration
	if age > fade_start and original_material:
		var t := (age - fade_start) / fade_duration
		original_material.albedo_color.a = 1.0 - t
		original_material.emission_energy_multiplier = (1.0 - t) * 2.5

	position += drift_direction * delta
	rotation.x += rotation_speed * delta * 0.7
	rotation.y += rotation_speed * delta
	rotation.z += rotation_speed * delta * 0.5
