class_name MiningMothership
extends Ship
## Mining capital ship that serves as the player's mobile base.
## Extends Ship — movement logic will be added in a future pass.
## Has 5 dorsal turret hardpoints and a rear landing pad / cargo bay.

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal scrap_collected(amount: int)

@export var max_health: float = 300.0
@export var max_shield: float = 150.0

## Placeholders for future movement — not implemented yet.
@export var max_speed:  float = 8.0
@export var thrust:     float = 5.0

var health: float
var shield: float
var shield_regen_rate: float = 1.0   # HP per second


func _ready() -> void:
	add_to_group("mothership")

	health = max_health
	shield = max_shield

	# Load the Blender-generated model and attach it
	var model_res := load("res://assets/mothership/mothership.glb") as PackedScene
	if model_res:
		var model := model_res.instantiate()
		model.name = "Model"
		add_child(model)
	else:
		push_warning("MiningMothership: could not load mothership.glb — model missing.")


func _process(delta: float) -> void:
	if shield < max_shield:
		shield = minf(shield + shield_regen_rate * delta, max_shield)
		shield_changed.emit(shield, max_shield)


func take_damage(amount: float) -> void:
	if shield > 0.0:
		var absorbed := minf(amount, shield)
		shield -= absorbed
		amount -= absorbed
		shield_changed.emit(shield, max_shield)

	if amount > 0.0:
		health -= amount
		health = maxf(health, 0.0)
		health_changed.emit(health, max_health)

		if health <= 0.0:
			_on_destroyed()


func collect_scrap(amount: int) -> void:
	scrap_collected.emit(amount)


func _on_destroyed() -> void:
	print("MiningMothership destroyed — game over!")
