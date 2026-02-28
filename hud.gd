class_name HUD
extends CanvasLayer

@onready var collector_health_label: Label = $CollectorContainer/VBox/CollectorHealthLabel
@onready var cargo_label: Label = $CollectorContainer/VBox/CargoLabel

var collector_health: float = 100.0
var max_collector_health: float = 100.0
var cargo_current: int = 0
var cargo_capacity: int = 50

# Set by GameManager after collector ship is spawned
var collector_ship: CollectorShip = null


func _ready() -> void:
	add_to_group("hud")
	update_collector_health(collector_health)
	update_cargo(cargo_current, cargo_capacity)


func update_collector_health(health: float) -> void:
	collector_health = health
	collector_health_label.text = "Collector: %d / %d" % [int(collector_health), int(max_collector_health)]


func update_cargo(current: int, capacity: int) -> void:
	cargo_current = current
	cargo_capacity = capacity
	cargo_label.text = "Cargo Hold: %d / %d" % [cargo_current, cargo_capacity]
