class_name Bomb
extends Projectile
## Bomb dropped by Bomber - falls and explodes on impact

@export var fall_speed: float = 8.0
@export var explosion_scene: PackedScene

var target_position: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	# Fall toward target
	global_position.y -= fall_speed * delta

	# Rotate while falling
	rotation.x += delta * 3.0
	rotation.z += delta * 2.0

	# Check if hit station level
	if global_position.y <= target_position.y:
		_explode()


func _explode() -> void:
	var hud := _get_hud()
	if hud:
		hud.take_damage(damage)

	# Spawn explosion effect
	if explosion_scene:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().root.add_child(explosion)

	queue_free()
