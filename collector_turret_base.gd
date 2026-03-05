class_name Turret
extends Node3D
## Base class for all turret types.
## Collector hardpoint turrets extend this directly.
## Mothership turrets will also extend this when implemented.

## Shared registry: alien node → Turret that claimed it.
static var _claimed: Dictionary = {}


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


func _exit_tree() -> void:
	_release_target()


## Returns true if alien is already claimed by a different turret.
static func is_claimed(alien: Node3D) -> bool:
	return _claimed.has(alien)


## Claim alien as this turret's exclusive target. Releases previous claim.
func _claim_target(alien: Node3D) -> void:
	_release_target()
	_claimed[alien] = self


## Release this turret's current claim, if any.
func _release_target() -> void:
	for alien in _claimed.keys():
		if _claimed[alien] == self:
			_claimed.erase(alien)
			return
