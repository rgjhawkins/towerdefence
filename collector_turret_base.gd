class_name Turret
extends Node3D
## Base class for all turret types.
## Collector hardpoint turrets extend this directly.
## Scene-based station turrets extend StationTurret which extends this.

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
