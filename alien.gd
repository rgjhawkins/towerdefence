class_name Alien
extends Node3D

signal died(alien: Alien)
signal killed(alien: Alien, scrap_value: int)
signal reached_station(alien: Alien, damage: float)

@export var speed: float = 5.0
@export var health: float = 50.0
@export var station_damage: float = 1.0
@export var scrap_value: int = 1
@export var explosion_scene: PackedScene

var target_position: Vector3 = Vector3.ZERO
var is_alive: bool = true
var velocity: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	if not is_alive:
		return

	var direction := (target_position - global_position).normalized()
	velocity = direction * speed
	global_position += velocity * delta

	# Face towards target
	if direction.length() > 0.01:
		look_at(target_position, Vector3.UP)

	# Check if reached target
	if global_position.distance_to(target_position) < 0.5:
		_on_reached_target()


func _on_reached_target() -> void:
	reached_station.emit(self, station_damage)
	die()


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0 and is_alive:
		killed.emit(self, scrap_value)
		die()


func die() -> void:
	is_alive = false
	_spawn_explosion()
	died.emit(self)
	queue_free()


func _spawn_explosion() -> void:
	if explosion_scene:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().root.add_child(explosion)
