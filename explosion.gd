extends Node3D

@export var lifetime: float = 0.3

func _ready() -> void:
	# Start particles
	$Particles.emitting = true
	$Flash.visible = true

	# Fade out flash quickly
	var tween := create_tween()
	tween.tween_property($Flash, "transparency", 1.0, 0.1)

	# Remove after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()
