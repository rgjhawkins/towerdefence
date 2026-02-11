class_name Alien
extends Node3D
## Base class for all alien ships

signal died(alien: Alien)
signal killed(alien: Alien, scrap_value: int)

@export var speed: float = 5.0
@export var health: float = 5.0
@export var scrap_value: int = 1
@export var explosion_scene: PackedScene
@export var scrap_scene: PackedScene
@export var scrap_count: int = 3

var target_position: Vector3 = Vector3.ZERO
var is_alive: bool = true
var velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_on_ready()


func _process(delta: float) -> void:
	if not is_alive:
		return
	_on_process(delta)


# Virtual methods for subclasses to override
func _on_ready() -> void:
	pass


func _on_process(_delta: float) -> void:
	pass


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0 and is_alive:
		killed.emit(self, scrap_value)
		die()


func die() -> void:
	is_alive = false
	var death_pos := global_position
	_spawn_explosion(death_pos)
	_spawn_scrap(death_pos)
	died.emit(self)
	queue_free()


func _spawn_explosion(pos: Vector3) -> void:
	if explosion_scene:
		var explosion := explosion_scene.instantiate()
		get_tree().root.add_child(explosion)
		explosion.global_position = pos


func _spawn_scrap(base_pos: Vector3) -> void:
	if scrap_scene:
		for i in scrap_count:
			var scrap := scrap_scene.instantiate()
			var spawn_pos := base_pos + Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-0.2, 0.2),
				randf_range(-0.5, 0.5)
			)
			get_tree().root.add_child(scrap)
			scrap.global_position = spawn_pos
