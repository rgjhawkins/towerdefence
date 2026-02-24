class_name OrganicAlien
extends Alien
## Base class for biological alien enemies.
## Adds tumbling corpse drift when killed — all organic alien types inherit this.

const CORPSE_LIFETIME := 10.0
const MAX_DRIFT_SPEED := 0.5    # Units per second
const MAX_TUMBLE_SPEED := 2.5   # Radians per second

var _is_corpse: bool = false
var _corpse_velocity: Vector3 = Vector3.ZERO
var _corpse_angular_velocity: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	if _is_corpse:
		_do_corpse_drift(delta)
	elif is_alive:
		_on_process(delta)


func _do_corpse_drift(delta: float) -> void:
	global_position += _corpse_velocity * delta
	rotation += _corpse_angular_velocity * delta


## Enters corpse state: random drift + tumble, then despawns after CORPSE_LIFETIME.
## Called from subclass die() overrides. Do not call directly.
func start_corpse() -> void:
	_is_corpse = true
	is_alive = false
	died.emit(self)

	_corpse_velocity = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.2, 0.2),
		randf_range(-1.0, 1.0)
	).normalized() * randf_range(0.05, MAX_DRIFT_SPEED)

	_corpse_angular_velocity = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized() * randf_range(0.3, MAX_TUMBLE_SPEED)

	_on_corpse_start()
	get_tree().create_timer(CORPSE_LIFETIME).timeout.connect(queue_free)


## Virtual — override in subclass to apply visual changes on death (dim materials etc.).
func _on_corpse_start() -> void:
	pass
