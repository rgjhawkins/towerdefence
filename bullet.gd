class_name Bullet
extends Node3D

var speed: float = 100.0
var damage: float = 10.0
var direction: Vector3 = Vector3.FORWARD
var max_distance: float = 100.0
var distance_traveled: float = 0.0
var hit_radius: float = 0.5


func _process(delta: float) -> void:
	var movement := direction * speed * delta
	position += movement
	distance_traveled += movement.length()

	_check_hits()

	if distance_traveled >= max_distance:
		queue_free()


func _check_hits() -> void:
	var aliens := get_tree().get_nodes_in_group("aliens")

	for alien in aliens:
		if "is_alive" in alien and alien.is_alive:
			var dist := global_position.distance_to(alien.global_position)
			if dist < hit_radius:
				alien.take_damage(damage)
				queue_free()
				return
