class_name HUD
extends CanvasLayer

signal turret_upgraded(turret: Turret, stat: String, value: float)
signal shield_hit()
signal shield_regen()

# Turret upgrade constants
const INITIAL_ROF_COST := 5
const INITIAL_ROF_VALUE := 1.0  # Shots per second (60 RPM)
const ROF_COST_INCREMENT := 5
const ROF_VALUE_INCREMENT := 10.0 / 60.0  # 10 RPM per upgrade
const INITIAL_TRACK_COST := 5
const INITIAL_TRACK_VALUE := 45.0  # Degrees per second
const TRACK_COST_INCREMENT := 5
const TRACK_VALUE_INCREMENT := 5.0  # Degrees per upgrade

# Shield constants
const SHIELD_REGEN_PULSE_THRESHOLD := 1.0  # Pulse every 1 HP

@onready var health_label: Label = $StationContainer/VBox/HealthLabel
@onready var shield_label: Label = $StationContainer/VBox/ShieldLabel
@onready var station_scrap_label: Label = $StationContainer/VBox/StationScrapLabel
@onready var collector_health_label: Label = $CollectorContainer/VBox/CollectorHealthLabel
@onready var cargo_label: Label = $CollectorContainer/VBox/CargoLabel
@onready var level_label: Label = $LevelContainer/VBox/LevelLabel
@onready var wave_label: Label = $LevelContainer/VBox/WaveLabel

# Turret panel references
@onready var turret_panel: PanelContainer = $TurretPanel
@onready var turret_title: Label = $TurretPanel/VBox/Header/TitleLabel
@onready var close_button: Button = $TurretPanel/VBox/Header/CloseButton
@onready var rof_value_label: Label = $TurretPanel/VBox/RofContainer/RofValue
@onready var rof_upgrade_button: Button = $TurretPanel/VBox/RofContainer/RofUpgrade
@onready var track_value_label: Label = $TurretPanel/VBox/TrackContainer/TrackValue
@onready var track_upgrade_button: Button = $TurretPanel/VBox/TrackContainer/TrackUpgrade
@onready var panel_scrap_label: Label = $TurretPanel/VBox/ScrapLabel

# Health values
var station_health: float = 100.0
var max_station_health: float = 100.0
var shield_health: float = 100.0
var max_shield_health: float = 100.0
var shield_regen_rate: float = 0.5  # HP per second
var shield_regen_accumulator: float = 0.0
var collector_health: float = 100.0
var max_collector_health: float = 100.0
var station_scrap: int = 0
var cargo_current: int = 0
var cargo_capacity: int = 50

# Selected turret tracking
var selected_turret: Turret = null
var turret_upgrade_data: Dictionary = {}  # turret -> {rof_cost, track_cost}


func _ready() -> void:
	add_to_group("hud")

	update_health(station_health)
	update_shield(shield_health)
	update_collector_health(collector_health)
	update_station_scrap(station_scrap)
	update_cargo(cargo_current, cargo_capacity)

	# Connect panel buttons
	close_button.pressed.connect(_on_close_pressed)
	rof_upgrade_button.pressed.connect(_on_rof_upgrade_pressed)
	track_upgrade_button.pressed.connect(_on_track_upgrade_pressed)


func _process(delta: float) -> void:
	# Regenerate shield
	if shield_health < max_shield_health:
		var regen_amount := shield_regen_rate * delta
		shield_health += regen_amount
		shield_health = minf(shield_health, max_shield_health)
		update_shield(shield_health)

		# Pulse every 1 HP recovered
		shield_regen_accumulator += regen_amount
		if shield_regen_accumulator >= SHIELD_REGEN_PULSE_THRESHOLD:
			shield_regen_accumulator -= SHIELD_REGEN_PULSE_THRESHOLD
			shield_regen.emit()


func _get_turret_data(turret: Turret) -> Dictionary:
	if turret not in turret_upgrade_data:
		turret_upgrade_data[turret] = {
			"rof_cost": INITIAL_ROF_COST,
			"track_cost": INITIAL_TRACK_COST
		}
	return turret_upgrade_data[turret]


func select_turret(turret: Turret) -> void:
	# Deselect previous
	if selected_turret and is_instance_valid(selected_turret):
		selected_turret.hide_selection()

	# Toggle if same turret
	if selected_turret == turret:
		selected_turret = null
		turret_panel.visible = false
		return

	# Select new turret
	selected_turret = turret
	turret.show_selection()
	_update_turret_panel()
	turret_panel.visible = true


func deselect_turret() -> void:
	if selected_turret and is_instance_valid(selected_turret):
		selected_turret.hide_selection()
	selected_turret = null
	turret_panel.visible = false


func _update_turret_panel() -> void:
	if not selected_turret:
		return

	var data := _get_turret_data(selected_turret)

	# Update ROF display (as RPM)
	var rpm := selected_turret.rate_of_fire * 60.0
	rof_value_label.text = "%d" % int(rpm)
	rof_upgrade_button.text = "+ (%d)" % data.rof_cost

	# Update tracking display
	track_value_label.text = "%d" % int(selected_turret.tracking_speed)
	track_upgrade_button.text = "+ (%d)" % data.track_cost

	# Update scrap display
	panel_scrap_label.text = "Available Scrap: %d" % station_scrap


func _on_close_pressed() -> void:
	deselect_turret()


func _on_rof_upgrade_pressed() -> void:
	if not selected_turret:
		return

	var data := _get_turret_data(selected_turret)
	var cost: int = data.rof_cost

	if station_scrap >= cost:
		# Deduct scrap
		station_scrap -= cost
		update_station_scrap(station_scrap)

		# Increase ROF
		selected_turret.rate_of_fire += ROF_VALUE_INCREMENT

		# Increase next cost
		data.rof_cost += ROF_COST_INCREMENT

		# Update display
		_update_turret_panel()

		# Emit signal
		turret_upgraded.emit(selected_turret, "rate_of_fire", selected_turret.rate_of_fire)


func _on_track_upgrade_pressed() -> void:
	if not selected_turret:
		return

	var data := _get_turret_data(selected_turret)
	var cost: int = data.track_cost

	if station_scrap >= cost:
		# Deduct scrap
		station_scrap -= cost
		update_station_scrap(station_scrap)

		# Increase tracking speed
		selected_turret.tracking_speed += TRACK_VALUE_INCREMENT

		# Increase next cost
		data.track_cost += TRACK_COST_INCREMENT

		# Update display
		_update_turret_panel()

		# Emit signal
		turret_upgraded.emit(selected_turret, "tracking_speed", selected_turret.tracking_speed)


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
	# Update panel if visible
	if turret_panel.visible:
		panel_scrap_label.text = "Available Scrap: %d" % station_scrap


func update_cargo(current: int, capacity: int) -> void:
	cargo_current = current
	cargo_capacity = capacity
	cargo_label.text = "Cargo Hold: %d / %d" % [cargo_current, cargo_capacity]


func update_level(level: int) -> void:
	level_label.text = "Level %d" % level


func update_wave(current_wave: int, total_waves: int) -> void:
	wave_label.text = "Wave %d / %d" % [current_wave, total_waves]
