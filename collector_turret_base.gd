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


## Override to return the button colour shown in the HUD.
func get_icon_color() -> Color:
	return Color(0.5, 0.5, 0.5)


## Called when the turret is deactivated — override to hide effects/stop audio.
func _on_deactivated() -> void:
	pass


## Called when the turret is reactivated.
func _on_activated() -> void:
	pass


var active: bool = true:
	set(value):
		active = value
		if not active:
			_release_target()
			_on_deactivated()
		else:
			_on_activated()


func _process(delta: float) -> void:
	if active:
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


## Returns the Ship that owns this turret, or null.
func _get_owner_ship() -> Ship:
	var node: Node = self
	while node:
		if node is Ship:
			return node as Ship
		node = node.get_parent()
	return null


## Returns true if the owning ship has at least `amount` energy.
func _has_energy(amount: float) -> bool:
	var ship := _get_owner_ship()
	return ship != null and ship.energy >= amount


## Drain energy from the ship this turret belongs to.
func _drain_energy(amount: float) -> void:
	var ship := _get_owner_ship()
	if ship:
		ship.energy = maxf(0.0, ship.energy - amount)
		ship.energy_changed.emit(ship.energy, ship.max_energy)



## Release this turret's current claim, if any.
func _release_target() -> void:
	for alien in _claimed.keys():
		if _claimed[alien] == self:
			_claimed.erase(alien)
			return
