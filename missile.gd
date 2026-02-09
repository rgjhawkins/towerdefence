extends Node3D

@export var initial_speed: float = 1.0
@export var max_speed: float = 15.0
@export var acceleration: float = 8.0
@export var damage: float = 1.0
@export var lifetime: float = 10.0
@export var wobble_strength: float = 3.0
@export var wobble_frequency: float = 4.0
@export var curve_strength: float = 2.0

var target_position: Vector3 = Vector3.ZERO
var age: float = 0.0
var wobble_offset: float = 0.0
var curve_direction: Vector3 = Vector3.ZERO
var actual_velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0


func _ready() -> void:
	# Start at initial slow speed
	current_speed = initial_speed
	# Random phase offset for wobble
	wobble_offset = randf() * TAU
	# Random perpendicular curve direction
	curve_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()


func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return

	# Accelerate over time
	current_speed = minf(current_speed + acceleration * delta, max_speed)

	# Base direction towards target
	var to_target := target_position - global_position
	var distance := to_target.length()
	var base_direction := to_target.normalized()

	# Calculate perpendicular vectors for wobble
	var right := base_direction.cross(Vector3.UP).normalized()
	var up := Vector3.UP

	# Wobble effect - sinusoidal side-to-side and up-down motion
	var wobble_h := sin(age * wobble_frequency + wobble_offset) * wobble_strength
	var wobble_v := cos(age * wobble_frequency * 1.3 + wobble_offset) * wobble_strength * 0.5

	# Reduce wobble as we get closer to target
	var wobble_falloff: float = clampf(distance / 8.0, 0.0, 1.0)
	wobble_h *= wobble_falloff
	wobble_v *= wobble_falloff

	# Initial curve/arc - stronger at start, fades out
	var curve_falloff: float = clampf(1.0 - age / 2.0, 0.0, 1.0)
	var curve: Vector3 = curve_direction * curve_strength * curve_falloff

	# Combine all movement
	var final_direction := base_direction + (right * wobble_h + up * wobble_v + curve) * delta
	final_direction = final_direction.normalized()

	actual_velocity = final_direction * current_speed
	global_position += actual_velocity * delta

	# Face direction of travel (smooth)
	if actual_velocity.length() > 0.01:
		var look_target := global_position + actual_velocity
		look_at(look_target, Vector3.UP)

	# Check if reached target (station)
	if distance < 1.5:
		_hit_target()


func _hit_target() -> void:
	# Find HUD and deal damage to station
	var hud = get_tree().root.get_node_or_null("Main/HUD")
	if hud and hud.has_method("take_damage"):
		hud.take_damage(damage)
	queue_free()
