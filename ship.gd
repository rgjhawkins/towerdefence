class_name Ship
extends Node3D
## Base class for all pilotable ships.

signal energy_changed(current: float, maximum: float)

@export var max_energy: float = 100.0
@export var energy_regen: float = 1.0

var energy: float


## Call from _process in subclasses to regenerate energy each frame.
func _regen_energy(delta: float) -> void:
	if energy < max_energy:
		energy = minf(energy + energy_regen * delta, max_energy)
		energy_changed.emit(energy, max_energy)
