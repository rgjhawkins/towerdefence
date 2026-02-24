class_name CollectorTurretBase
extends Node3D
## Base class for all turrets mountable on the collector ship hardpoints.
## Add a subclass as a child of a hardpoint Node3D to install it.
## Remove and replace the child to swap turrets at runtime.

## Override to return the display name shown in the upgrade/swap UI.
func get_turret_name() -> String:
	return ""


## Override to construct the turret's procedural mesh during _ready.
func _build_mesh() -> void:
	pass


## Override for per-frame turret logic.
func _update(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	_update(delta)
