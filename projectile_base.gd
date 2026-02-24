class_name Projectile
extends Node3D
## Base class for all projectiles (Bullet, Missile, Plasma, Bomb).
## Provides shared damage property and a group-based HUD lookup helper,
## replacing the brittle hardcoded "Main/HUD" path used in subclasses.

@export var damage: float = 1.0


## Returns the HUD node via group lookup. Subclasses call this instead of
## hardcoding get_tree().root.get_node_or_null("Main/HUD").
func _get_hud() -> HUD:
	return get_tree().get_first_node_in_group("hud") as HUD
