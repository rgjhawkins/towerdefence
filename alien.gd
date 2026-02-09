class_name Alien
extends Node3D

signal died(alien: Alien)
signal killed(alien: Alien, scrap_value: int)
signal reached_station(alien: Alien, damage: float)

@export var speed: float = 5.0
@export var health: float = 5.0
@export var station_damage: float = 1.0
@export var scrap_value: int = 1
@export var explosion_scene: PackedScene
@export var scrap_scene: PackedScene
@export var missile_scene: PackedScene
@export var scrap_count: int = 5
@export var stop_distance_min: float = 12.0  # Minimum distance from station to stop
@export var stop_distance_max: float = 20.0  # Maximum distance from station to stop
@export var fire_rate: float = 1.0  # Missiles per second
@export var deceleration: float = 3.0  # How fast to slow down

var target_position: Vector3 = Vector3.ZERO
var is_alive: bool = true
var velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_stopped: bool = false
var time_since_fire: float = 0.0
var stop_distance: float = 15.0


func _ready() -> void:
	current_speed = speed
	stop_distance = randf_range(stop_distance_min, stop_distance_max)


func _process(delta: float) -> void:
	if not is_alive:
		return

	var distance_to_target := global_position.distance_to(target_position)
	var direction := (target_position - global_position).normalized()

	# Slow down as we approach stop distance
	if distance_to_target <= stop_distance:
		if not is_stopped:
			current_speed -= deceleration * delta
			if current_speed <= 0:
				current_speed = 0
				is_stopped = true

	# Move if not stopped
	if current_speed > 0:
		velocity = direction * current_speed
		global_position += velocity * delta

	# Face towards target
	if direction.length() > 0.01:
		look_at(target_position, Vector3.UP)

	# Fire missiles when stopped
	if is_stopped:
		time_since_fire += delta
		if time_since_fire >= 1.0 / fire_rate:
			_fire_missile()
			time_since_fire = 0.0


func _fire_missile() -> void:
	if missile_scene:
		var missile := missile_scene.instantiate()
		# Launch from top of the ship (above the bridge)
		var launch_offset := Vector3(0, 0.5, 0)
		missile.global_position = global_position + launch_offset
		missile.target_position = target_position
		get_tree().root.add_child(missile)


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0 and is_alive:
		killed.emit(self, scrap_value)
		die()


func die() -> void:
	is_alive = false
	_spawn_explosion()
	_spawn_scrap()
	died.emit(self)
	queue_free()


func _spawn_explosion() -> void:
	if explosion_scene:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().root.add_child(explosion)


func _spawn_scrap() -> void:
	if scrap_scene:
		for i in scrap_count:
			var scrap := scrap_scene.instantiate()
			scrap.global_position = global_position + Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-0.2, 0.2),
				randf_range(-0.5, 0.5)
			)
			get_tree().root.add_child(scrap)
