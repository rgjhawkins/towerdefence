extends Node3D

@export var drift_speed: float = 0.5
@export var rotation_speed: float = 2.0
@export var lifespan: float = 30.0
@export var fade_duration: float = 3.0

var drift_direction: Vector3
var age: float = 0.0
var mesh_node: Node = null
var original_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("scrap")

	# Random drift direction
	drift_direction = Vector3(
		randf_range(-1, 1),
		0,
		randf_range(-1, 1)
	).normalized() * drift_speed

	# Random initial rotation
	rotation = Vector3(
		randf() * TAU,
		randf() * TAU,
		randf() * TAU
	)

	# Get mesh for fading
	mesh_node = get_node_or_null("Mesh")
	if mesh_node and mesh_node.material:
		# Duplicate material so each scrap can fade independently
		original_material = mesh_node.material.duplicate()
		original_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_node.material = original_material


func _process(delta: float) -> void:
	# Track age
	age += delta

	# Check if expired
	if age >= lifespan:
		queue_free()
		return

	# Fade out near end of life
	var fade_start := lifespan - fade_duration
	if age > fade_start and original_material:
		var fade_progress := (age - fade_start) / fade_duration
		var alpha := 1.0 - fade_progress
		original_material.albedo_color.a = alpha
		# Also fade emission
		var emission_strength := alpha * 2.5
		original_material.emission_energy_multiplier = emission_strength

	# Slow drift
	position += drift_direction * delta

	# Tumble rotation
	rotation.x += rotation_speed * delta * 0.7
	rotation.y += rotation_speed * delta
	rotation.z += rotation_speed * delta * 0.5
