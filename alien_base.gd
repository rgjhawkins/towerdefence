class_name Alien
extends Node3D
## Base class for all alien enemy types.
## Subclasses override _on_ready() and _on_process() for their specific behaviour.

signal died(alien: Node3D)

var is_alive: bool = true
var max_health: float = 1.0
var health: float = 1.0


func _ready() -> void:
	add_to_group("aliens")
	_on_ready()


func _process(delta: float) -> void:
	if is_alive:
		_on_process(delta)


## Virtual — override in subclass for initialisation
func _on_ready() -> void:
	pass


## Virtual — override in subclass for per-frame behaviour
func _on_process(_delta: float) -> void:
	pass


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()


func die() -> void:
	is_alive = false
	died.emit(self)
	queue_free()
