extends CanvasLayer

signal turret_selected(index: int)
signal turret_deselected()
signal turret_upgraded(index: int, stat: String, value: float)
signal shield_hit()

@onready var health_label: Label = $StationContainer/VBox/HealthLabel
@onready var shield_label: Label = $StationContainer/VBox/ShieldLabel
@onready var station_scrap_label: Label = $StationContainer/VBox/StationScrapLabel
@onready var collector_health_label: Label = $CollectorContainer/VBox/CollectorHealthLabel
@onready var cargo_label: Label = $CollectorContainer/VBox/CargoLabel
@onready var turret_icons: VBoxContainer = $TurretContainer

var station_health: float = 100.0
var max_station_health: float = 100.0
var shield_health: float = 100.0
var max_shield_health: float = 100.0
var shield_regen_rate: float = 0.5  # HP per second
var collector_health: float = 100.0
var max_collector_health: float = 100.0
var station_scrap: int = 0
var cargo_current: int = 0
var cargo_capacity: int = 50
var selected_turret_index: int = -1
var turret_icon_nodes: Array[PanelContainer] = []
var turret_rof_costs: Array[int] = [5, 5, 5, 5, 5]
var turret_rof_values: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var turret_track_costs: Array[int] = [5, 5, 5, 5, 5]
var turret_track_values: Array[float] = [45.0, 45.0, 45.0, 45.0, 45.0]


func _ready() -> void:
	update_health(station_health)
	update_shield(shield_health)
	update_collector_health(collector_health)
	update_station_scrap(station_scrap)
	update_cargo(cargo_current, cargo_capacity)
	_setup_turret_icons()


func _process(delta: float) -> void:
	# Regenerate shield
	if shield_health < max_shield_health:
		shield_health += shield_regen_rate * delta
		shield_health = minf(shield_health, max_shield_health)
		update_shield(shield_health)


func _setup_turret_icons() -> void:
	for i in range(1, 6):
		var icon: PanelContainer = turret_icons.get_node("TurretIcon%d" % i)
		turret_icon_nodes.append(icon)
		icon.gui_input.connect(_on_turret_icon_input.bind(i - 1))
		icon.mouse_filter = Control.MOUSE_FILTER_STOP

		# Connect ROF upgrade button
		var rof_button: Button = icon.get_node("VBox/RofContainer/RofUpgrade")
		rof_button.pressed.connect(_on_rof_upgrade_pressed.bind(i - 1))

		# Connect Track upgrade button
		var track_button: Button = icon.get_node("VBox/TrackContainer/TrackUpgrade")
		track_button.pressed.connect(_on_track_upgrade_pressed.bind(i - 1))


func _on_rof_upgrade_pressed(index: int) -> void:
	var cost := turret_rof_costs[index]

	if station_scrap >= cost:
		# Deduct scrap
		station_scrap -= cost
		update_station_scrap(station_scrap)

		# Increase ROF by 10 RPM (10/60 shots per second)
		turret_rof_values[index] += 10.0 / 60.0

		# Update display
		_update_turret_rof_display(index)

		# Increase next cost by 5
		turret_rof_costs[index] += 5
		_update_turret_rof_cost_display(index)

		# Emit signal to update actual turret
		turret_upgraded.emit(index, "rate_of_fire", turret_rof_values[index])


func _update_turret_rof_display(index: int) -> void:
	var icon := turret_icon_nodes[index]
	var rof_value: Label = icon.get_node("VBox/RofContainer/RofValue")
	# Display as rounds per minute
	var rpm := turret_rof_values[index] * 60.0
	rof_value.text = "%d" % int(rpm)


func _update_turret_rof_cost_display(index: int) -> void:
	var icon := turret_icon_nodes[index]
	var rof_cost: Label = icon.get_node("VBox/RofContainer/RofCost")
	rof_cost.text = "(%d)" % turret_rof_costs[index]


func _on_track_upgrade_pressed(index: int) -> void:
	var cost := turret_track_costs[index]

	if station_scrap >= cost:
		# Deduct scrap
		station_scrap -= cost
		update_station_scrap(station_scrap)

		# Increase tracking speed by 5 degrees/sec
		turret_track_values[index] += 5.0

		# Update display
		_update_turret_track_display(index)

		# Increase next cost by 5
		turret_track_costs[index] += 5
		_update_turret_track_cost_display(index)

		# Emit signal to update actual turret
		turret_upgraded.emit(index, "tracking_speed", turret_track_values[index])


func _update_turret_track_display(index: int) -> void:
	var icon := turret_icon_nodes[index]
	var track_value: Label = icon.get_node("VBox/TrackContainer/TrackValue")
	track_value.text = "%d" % int(turret_track_values[index])


func _update_turret_track_cost_display(index: int) -> void:
	var icon := turret_icon_nodes[index]
	var track_cost: Label = icon.get_node("VBox/TrackContainer/TrackCost")
	track_cost.text = "(%d)" % turret_track_costs[index]


func _on_turret_icon_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_turret(index)


func select_turret(index: int) -> void:
	# Deselect previous
	if selected_turret_index >= 0 and selected_turret_index < turret_icon_nodes.size():
		var prev_icon := turret_icon_nodes[selected_turret_index]
		prev_icon.custom_minimum_size = Vector2(120, 80)
		prev_icon.size_flags_vertical = Control.SIZE_FILL

	# Select new (or deselect if same)
	if selected_turret_index == index:
		selected_turret_index = -1
		turret_deselected.emit()
	else:
		selected_turret_index = index
		var icon := turret_icon_nodes[index]
		icon.custom_minimum_size = Vector2(300, 400)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		turret_selected.emit(index)


func update_health(health: float) -> void:
	station_health = health
	health_label.text = "Station: %d / %d" % [int(station_health), int(max_station_health)]


func update_collector_health(health: float) -> void:
	collector_health = health
	collector_health_label.text = "Collector: %d / %d" % [int(collector_health), int(max_collector_health)]


func take_collector_damage(amount: float) -> void:
	collector_health -= amount
	collector_health = max(collector_health, 0)
	update_collector_health(collector_health)

	if collector_health <= 0:
		_on_collector_destroyed()


func _on_collector_destroyed() -> void:
	print("Collector Destroyed!")


func take_damage(amount: float) -> void:
	# Shield absorbs damage first
	if shield_health > 0:
		var shield_damage := minf(amount, shield_health)
		shield_health -= shield_damage
		amount -= shield_damage
		update_shield(shield_health)
		shield_hit.emit()  # Trigger visual effect

	# Remaining damage goes to station
	if amount > 0:
		station_health -= amount
		station_health = max(station_health, 0)
		update_health(station_health)

		if station_health <= 0:
			_on_station_destroyed()


func update_shield(health: float) -> void:
	shield_health = health
	shield_label.text = "Shield: %d / %d" % [int(shield_health), int(max_shield_health)]


func _on_station_destroyed() -> void:
	print("Station Destroyed! Game Over!")


func add_station_scrap(amount: int) -> void:
	station_scrap += amount
	update_station_scrap(station_scrap)


func update_station_scrap(value: int) -> void:
	station_scrap = value
	station_scrap_label.text = "Station Scrap: %d" % station_scrap


func update_cargo(current: int, capacity: int) -> void:
	cargo_current = current
	cargo_capacity = capacity
	cargo_label.text = "Cargo Hold: %d / %d" % [cargo_current, cargo_capacity]
