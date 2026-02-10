class_name Bomber
extends Alien
## Bomber - Small ship that spirals toward station, fires plasma, then escapes

@export var plasma_scene: PackedScene
@export var spiral_tightness: float = 0.8
@export var rotation_speed: float = 1.2
@export var attack_distance: float = 12.0  # Distance to fire and escape
@export var escape_speed: float = 12.0
@export var direction_change_interval: float = 1.0  # Seconds between direction changes
@export var turn_speed: float = 3.0  # How fast to turn toward new direction

var is_escaping: bool = false
var has_fired: bool = false
var spiral_angle: float = 0.0
var spiral_radius: float = 30.0
var formation_angle: float = 0.0  # Set by spawner to keep formation
var escape_direction: Vector3 = Vector3.ZERO
var target_direction: Vector3 = Vector3.ZERO
var time_since_direction_change: float = 0.0


func _on_ready() -> void:
	# Use formation angle set by spawner, or calculate from position
	if formation_angle == 0.0:
		var to_center := target_position - global_position
		formation_angle = atan2(to_center.x, to_center.z)
	spiral_angle = formation_angle
	# Calculate radius in 2D (XZ plane) to match movement calculation
	var dx := global_position.x - target_position.x
	var dz := global_position.z - target_position.z
	spiral_radius = sqrt(dx * dx + dz * dz)


func _on_process(delta: float) -> void:
	if is_escaping:
		_do_escape(delta)
	else:
		_do_spiral(delta)


func _do_spiral(delta: float) -> void:
	# Rotate around while spiraling in
	spiral_angle += rotation_speed * delta
	spiral_radius -= spiral_tightness * speed * delta

	# Calculate position on spiral
	var new_x := target_position.x + cos(spiral_angle) * spiral_radius
	var new_z := target_position.z + sin(spiral_angle) * spiral_radius
	var new_pos := Vector3(new_x, global_position.y, new_z)

	velocity = (new_pos - global_position) / delta if delta > 0 else Vector3.ZERO
	global_position = new_pos

	# Face direction of travel
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)

	# Fire and escape when close enough
	if spiral_radius <= attack_distance and not has_fired:
		_fire_plasma()
		has_fired = true
		is_escaping = true
		# Pick initial escape direction (use current velocity direction as starting point)
		escape_direction = velocity.normalized() if velocity.length() > 0.1 else Vector3.FORWARD
		_pick_new_target_direction()


func _do_escape(delta: float) -> void:
	# Pick new target direction periodically
	time_since_direction_change += delta
	if time_since_direction_change >= direction_change_interval:
		_pick_new_target_direction()
		time_since_direction_change = 0.0

	# Smoothly turn toward target direction
	escape_direction = escape_direction.lerp(target_direction, turn_speed * delta).normalized()

	# Move in current escape direction
	velocity = escape_direction * escape_speed
	global_position += velocity * delta

	# Smoothly face direction of travel
	if velocity.length() > 0.1:
		var look_target := global_position + velocity.normalized()
		var current_forward := -global_transform.basis.z
		var new_forward := current_forward.lerp(velocity.normalized(), turn_speed * delta).normalized()
		look_at(global_position + new_forward, Vector3.UP)

	# Despawn when far away
	if global_position.length() > 50.0:
		queue_free()


func _pick_new_target_direction() -> void:
	# Random direction away from center, with some randomness
	var away_from_center := (global_position - target_position).normalized()
	var random_angle := randf_range(-PI / 2, PI / 2)  # +/- 90 degrees
	target_direction = away_from_center.rotated(Vector3.UP, random_angle)
	target_direction.y = 0  # Keep on same plane
	target_direction = target_direction.normalized()


func _fire_plasma() -> void:
	if plasma_scene:
		var plasma := plasma_scene.instantiate()
		plasma.global_position = global_position
		plasma.target_position = target_position
		get_tree().root.add_child(plasma)
