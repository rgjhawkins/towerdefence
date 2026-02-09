extends Node3D

@export var drift_speed: float = 0.5
@export var rotation_speed: float = 2.0

var drift_direction: Vector3


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


func _process(delta: float) -> void:
	# Slow drift
	position += drift_direction * delta

	# Tumble rotation
	rotation.x += rotation_speed * delta * 0.7
	rotation.y += rotation_speed * delta
	rotation.z += rotation_speed * delta * 0.5
