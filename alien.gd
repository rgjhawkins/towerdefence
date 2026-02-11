class_name MissileFrigate
extends Alien
## Missile Frigate - Approaches station, stops at range, and fires guided missiles

@export var missile_scene: PackedScene
@export var station_damage: float = 1.0
@export var stop_distance_min: float = 18.0
@export var stop_distance_max: float = 28.0
@export var fire_rate: float = 1.0
@export var deceleration: float = 3.0

var current_speed: float = 0.0
var is_stopped: bool = false
var time_since_fire: float = 0.0
var stop_distance: float = 15.0


func _on_ready() -> void:
	current_speed = speed
	stop_distance = randf_range(stop_distance_min, stop_distance_max)


func _on_process(delta: float) -> void:
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
		missile.target_position = target_position

		# Generate random launch direction within forward 180 degrees
		var forward := (target_position - global_position).normalized()
		var random_yaw := randf_range(-PI / 2, PI / 2)
		var random_pitch := randf_range(-PI / 4, PI / 2)

		var right := forward.cross(Vector3.UP).normalized()

		var launch_dir := forward
		launch_dir = launch_dir.rotated(Vector3.UP, random_yaw)
		launch_dir = launch_dir.rotated(right, random_pitch)
		launch_dir = launch_dir.normalized()

		missile.launch_direction = launch_dir
		get_tree().root.add_child(missile)
		# Set position after adding to tree
		var launch_offset := Vector3(0, 0.5, 0)
		missile.global_position = global_position + launch_offset
