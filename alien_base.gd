class_name Alien
extends Node3D
## Base class for all alien enemy types.
## Subclasses override _on_ready() and _on_process() for their specific behaviour.

signal died(alien: Alien)

var is_alive: bool = true


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


## Called by bullets/weapons. Combat wiring added later.
func take_damage(_amount: float) -> void:
	pass


func die() -> void:
	is_alive = false
	died.emit(self)
	queue_free()
