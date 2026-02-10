class_name HUD
extends CanvasLayer

signal turret_upgraded(turret: Turret, stat: String, value: float)
signal shield_hit()
signal shield_regen()
signal next_level_requested()

# Turret upgrade constants
const INITIAL_ROF_COST := 5
const INITIAL_ROF_VALUE := 1.0  # Shots per second (60 RPM)
const ROF_COST_INCREMENT := 5
const ROF_VALUE_INCREMENT := 10.0 / 60.0  # 10 RPM per upgrade
const INITIAL_TRACK_COST := 5
const INITIAL_TRACK_VALUE := 45.0  # Degrees per second
const TRACK_COST_INCREMENT := 5
const TRACK_VALUE_INCREMENT := 5.0  # Degrees per upgrade

# Station upgrade constants
const STATION_HEALTH_COST := 10
const STATION_HEALTH_INCREMENT := 20.0
const STATION_SHIELD_COST := 10
const STATION_SHIELD_INCREMENT := 20.0
const STATION_REGEN_COST := 15
const STATION_REGEN_INCREMENT := 0.25

# Collector upgrade constants
const COLLECTOR_HEALTH_COST := 10
const COLLECTOR_HEALTH_INCREMENT := 20.0
const COLLECTOR_CARGO_COST := 20
const COLLECTOR_CARGO_INCREMENT := 10
const COLLECTOR_SPEED_COST := 15
const COLLECTOR_SPEED_INCREMENT := 2.0

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

# Level complete screen references
@onready var level_complete_screen: ColorRect = $LevelCompleteScreen
@onready var lc_title: Label = $LevelCompleteScreen/ScrollContainer/MainVBox/Header/TitleLabel
@onready var lc_scrap_label: Label = $LevelCompleteScreen/ScrollContainer/MainVBox/Header/ScrapLabel
@onready var lc_turrets_container: HBoxContainer = $LevelCompleteScreen/ScrollContainer/MainVBox/TurretsSection/TurretsContainer
@onready var lc_station_panel: PanelContainer = $LevelCompleteScreen/ScrollContainer/MainVBox/BottomSection/StationPanel
@onready var lc_collector_panel: PanelContainer = $LevelCompleteScreen/ScrollContainer/MainVBox/BottomSection/CollectorPanel
@onready var lc_next_button: Button = $LevelCompleteScreen/ScrollContainer/MainVBox/ButtonContainer/NextLevelButton

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
var collector_max_speed: float = 12.0

# Selected turret tracking
var selected_turret: Turret = null
var turret_upgrade_data: Dictionary = {}  # turret -> {rof_cost, track_cost}

# References set by game manager
var turrets: Array[Turret] = []
var collector_ship: Node3D = null

# Station/Collector upgrade costs (increase with each purchase)
var station_health_cost: int = STATION_HEALTH_COST
var station_shield_cost: int = STATION_SHIELD_COST
var station_regen_cost: int = STATION_REGEN_COST
var collector_health_cost: int = COLLECTOR_HEALTH_COST
var collector_cargo_cost: int = COLLECTOR_CARGO_COST
var collector_speed_cost: int = COLLECTOR_SPEED_COST


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

	# Connect level complete screen buttons
	lc_next_button.pressed.connect(_on_next_level_pressed)
	_connect_level_complete_buttons()


func _connect_level_complete_buttons() -> void:
	# Connect station upgrade buttons
	var station_vbox = lc_station_panel.get_node("Margin/VBox")
	station_vbox.get_node("HealthRow/Upgrade").pressed.connect(_on_lc_station_health_upgrade)
	station_vbox.get_node("ShieldRow/Upgrade").pressed.connect(_on_lc_station_shield_upgrade)
	station_vbox.get_node("RegenRow/Upgrade").pressed.connect(_on_lc_station_regen_upgrade)

	# Connect collector upgrade buttons
	var collector_vbox = lc_collector_panel.get_node("Margin/VBox")
	collector_vbox.get_node("HealthRow/Upgrade").pressed.connect(_on_lc_collector_health_upgrade)
	collector_vbox.get_node("CargoRow/Upgrade").pressed.connect(_on_lc_collector_cargo_upgrade)
	collector_vbox.get_node("SpeedRow/Upgrade").pressed.connect(_on_lc_collector_speed_upgrade)

	# Connect turret upgrade buttons
	for i in range(5):
		var panel_name = "Turret%dPanel" % (i + 1)
		var panel = lc_turrets_container.get_node_or_null(panel_name)
		if panel:
			var vbox = panel.get_node("Margin/VBox")
			vbox.get_node("RofRow/Upgrade").pressed.connect(_on_lc_turret_rof_upgrade.bind(i))
			vbox.get_node("TrackRow/Upgrade").pressed.connect(_on_lc_turret_track_upgrade.bind(i))


func _process(delta: float) -> void:
	# Don't process during level complete screen
	if level_complete_screen.visible:
		return

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
	# Don't allow selection during level complete
	if level_complete_screen.visible:
		return

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
		station_scrap -= cost
		update_station_scrap(station_scrap)
		selected_turret.rate_of_fire += ROF_VALUE_INCREMENT
		data.rof_cost += ROF_COST_INCREMENT
		_update_turret_panel()
		turret_upgraded.emit(selected_turret, "rate_of_fire", selected_turret.rate_of_fire)


func _on_track_upgrade_pressed() -> void:
	if not selected_turret:
		return

	var data := _get_turret_data(selected_turret)
	var cost: int = data.track_cost

	if station_scrap >= cost:
		station_scrap -= cost
		update_station_scrap(station_scrap)
		selected_turret.tracking_speed += TRACK_VALUE_INCREMENT
		data.track_cost += TRACK_COST_INCREMENT
		_update_turret_panel()
		turret_upgraded.emit(selected_turret, "tracking_speed", selected_turret.tracking_speed)


# Level Complete Screen Functions
func show_level_complete(level_number: int) -> void:
	deselect_turret()
	lc_title.text = "Level %d Complete!" % level_number
	_update_level_complete_screen()
	level_complete_screen.visible = true


func hide_level_complete() -> void:
	level_complete_screen.visible = false


func _update_level_complete_screen() -> void:
	lc_scrap_label.text = "Available Scrap: %d" % station_scrap

	# Update turret panels
	for i in range(min(turrets.size(), 5)):
		var turret = turrets[i]
		var data = _get_turret_data(turret)
		var panel_name = "Turret%dPanel" % (i + 1)
		var panel = lc_turrets_container.get_node_or_null(panel_name)
		if panel:
			var vbox = panel.get_node("Margin/VBox")
			var rpm = turret.rate_of_fire * 60.0
			vbox.get_node("RofRow/Value").text = "%d" % int(rpm)
			vbox.get_node("RofRow/Upgrade").text = "+ (%d)" % data.rof_cost
			vbox.get_node("TrackRow/Value").text = "%d" % int(turret.tracking_speed)
			vbox.get_node("TrackRow/Upgrade").text = "+ (%d)" % data.track_cost

	# Update station panel
	var station_vbox = lc_station_panel.get_node("Margin/VBox")
	station_vbox.get_node("HealthRow/Value").text = "%d" % int(max_station_health)
	station_vbox.get_node("HealthRow/Upgrade").text = "+ (%d)" % station_health_cost
	station_vbox.get_node("ShieldRow/Value").text = "%d" % int(max_shield_health)
	station_vbox.get_node("ShieldRow/Upgrade").text = "+ (%d)" % station_shield_cost
	station_vbox.get_node("RegenRow/Value").text = "%.1f" % shield_regen_rate
	station_vbox.get_node("RegenRow/Upgrade").text = "+ (%d)" % station_regen_cost

	# Update collector panel
	var collector_vbox = lc_collector_panel.get_node("Margin/VBox")
	collector_vbox.get_node("HealthRow/Value").text = "%d" % int(max_collector_health)
	collector_vbox.get_node("HealthRow/Upgrade").text = "+ (%d)" % collector_health_cost
	collector_vbox.get_node("CargoRow/Value").text = "%d" % int(cargo_capacity)
	collector_vbox.get_node("CargoRow/Upgrade").text = "+ (%d)" % collector_cargo_cost
	collector_vbox.get_node("SpeedRow/Value").text = "%d" % int(collector_max_speed)
	collector_vbox.get_node("SpeedRow/Upgrade").text = "+ (%d)" % collector_speed_cost


func _on_next_level_pressed() -> void:
	hide_level_complete()
	next_level_requested.emit()


# Level Complete Upgrade Handlers
func _on_lc_turret_rof_upgrade(index: int) -> void:
	if index >= turrets.size():
		return
	var turret = turrets[index]
	var data = _get_turret_data(turret)
	if station_scrap >= data.rof_cost:
		station_scrap -= data.rof_cost
		turret.rate_of_fire += ROF_VALUE_INCREMENT
		data.rof_cost += ROF_COST_INCREMENT
		_update_level_complete_screen()
		update_station_scrap(station_scrap)


func _on_lc_turret_track_upgrade(index: int) -> void:
	if index >= turrets.size():
		return
	var turret = turrets[index]
	var data = _get_turret_data(turret)
	if station_scrap >= data.track_cost:
		station_scrap -= data.track_cost
		turret.tracking_speed += TRACK_VALUE_INCREMENT
		data.track_cost += TRACK_COST_INCREMENT
		_update_level_complete_screen()
		update_station_scrap(station_scrap)


func _on_lc_station_health_upgrade() -> void:
	if station_scrap >= station_health_cost:
		station_scrap -= station_health_cost
		max_station_health += STATION_HEALTH_INCREMENT
		station_health = max_station_health  # Heal to full on upgrade
		station_health_cost += 5
		_update_level_complete_screen()
		update_station_scrap(station_scrap)
		update_health(station_health)


func _on_lc_station_shield_upgrade() -> void:
	if station_scrap >= station_shield_cost:
		station_scrap -= station_shield_cost
		max_shield_health += STATION_SHIELD_INCREMENT
		shield_health = max_shield_health  # Restore to full on upgrade
		station_shield_cost += 5
		_update_level_complete_screen()
		update_station_scrap(station_scrap)
		update_shield(shield_health)


func _on_lc_station_regen_upgrade() -> void:
	if station_scrap >= station_regen_cost:
		station_scrap -= station_regen_cost
		shield_regen_rate += STATION_REGEN_INCREMENT
		station_regen_cost += 10
		_update_level_complete_screen()
		update_station_scrap(station_scrap)


func _on_lc_collector_health_upgrade() -> void:
	if station_scrap >= collector_health_cost:
		station_scrap -= collector_health_cost
		max_collector_health += COLLECTOR_HEALTH_INCREMENT
		collector_health = max_collector_health  # Heal to full
		collector_health_cost += 5
		if collector_ship and "max_health" in collector_ship:
			collector_ship.max_health = max_collector_health
			collector_ship.health = max_collector_health
		_update_level_complete_screen()
		update_station_scrap(station_scrap)
		update_collector_health(collector_health)


func _on_lc_collector_cargo_upgrade() -> void:
	if station_scrap >= collector_cargo_cost:
		station_scrap -= collector_cargo_cost
		cargo_capacity += COLLECTOR_CARGO_INCREMENT
		collector_cargo_cost += 10
		if collector_ship and "cargo_capacity" in collector_ship:
			collector_ship.cargo_capacity = cargo_capacity
		_update_level_complete_screen()
		update_station_scrap(station_scrap)
		update_cargo(cargo_current, cargo_capacity)


func _on_lc_collector_speed_upgrade() -> void:
	if station_scrap >= collector_speed_cost:
		station_scrap -= collector_speed_cost
		collector_max_speed += COLLECTOR_SPEED_INCREMENT
		collector_speed_cost += 10
		if collector_ship and "max_speed" in collector_ship:
			collector_ship.max_speed = collector_max_speed
		_update_level_complete_screen()
		update_station_scrap(station_scrap)


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
		shield_hit.emit()

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
	if turret_panel.visible:
		panel_scrap_label.text = "Available Scrap: %d" % station_scrap
	if level_complete_screen.visible:
		lc_scrap_label.text = "Available Scrap: %d" % station_scrap


func update_cargo(current: int, capacity: int) -> void:
	cargo_current = current
	cargo_capacity = capacity
	cargo_label.text = "Cargo Hold: %d / %d" % [cargo_current, cargo_capacity]


func update_level(level: int) -> void:
	level_label.text = "Level %d" % level


func update_wave(current_wave: int, total_waves: int) -> void:
	wave_label.text = "Wave %d / %d" % [current_wave, total_waves]
