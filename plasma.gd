extends Node3D
## Slow plasma ball fired by Bombers

@export var speed: float = 4.0
@export var damage: float = 2.0
@export var lifetime: float = 8.0

var target_position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD
var age: float = 0.0


func _ready() -> void:
	direction = (target_position - global_position).normalized()


func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return

	# Move toward target
	global_position += direction * speed * delta

	# Pulse effect - scale oscillation
	var pulse := 1.0 + sin(age * 8.0) * 0.1
	scale = Vector3.ONE * pulse

	# Check if reached target
	var distance := global_position.distance_to(target_position)
	if distance < 1.5:
		_hit_target()


func _hit_target() -> void:
	var hud = get_tree().root.get_node_or_null("Main/HUD")
	if hud and hud.has_method("take_damage"):
		hud.take_damage(damage)
	queue_free()
