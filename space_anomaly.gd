class_name SpaceAnomaly
extends Node3D
## Abstract base class for interactive space regions (asteroid fields, etc.).
## Subclasses register themselves in the "space_anomalies" group and override
## the virtual methods below.


## Returns a random spawn-marker node whose global_position updates live
## as the anomaly animates. Returns null if none exist.
func get_random_spawn_marker() -> Node3D:
	return null


## Returns a spawn marker associated with a specific physics body,
## or a random marker if no body-specific one exists.
func get_spawn_marker_for_body(body: StaticBody3D) -> Node3D:
	return get_random_spawn_marker()


## Called when a physics body within this anomaly has been fully depleted.
## Subclasses implement the appropriate response (split, crumble, etc.).
func deplete_body(body: StaticBody3D) -> void:
	pass
