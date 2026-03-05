extends Camera3D

@export var height: float = 45.0
@export var smooth_speed: float = 4.0  # Lower = more lag, higher = snappier

var _target: Node3D = null


func _ready() -> void:
	# Find collector ship - it joins the "collectors" group in _ready
	await get_tree().process_frame
	var collectors := get_tree().get_nodes_in_group("collectors")
	if collectors.size() > 0:
		_target = collectors[0] as Node3D


func _process(delta: float) -> void:
	if not _target:
		var collectors := get_tree().get_nodes_in_group("collectors")
		if collectors.size() > 0:
			_target = collectors[0] as Node3D
		return

	var goal := Vector3(_target.global_position.x, height, _target.global_position.z)
	global_position = global_position.lerp(goal, smooth_speed * delta)
