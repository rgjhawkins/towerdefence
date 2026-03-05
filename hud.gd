class_name HUD
extends CanvasLayer

@onready var collector_health_label: Label = $CollectorContainer/VBox/CollectorHealthLabel
@onready var cargo_label: Label = $CollectorContainer/VBox/CargoLabel
@onready var turret_buttons: HBoxContainer = $TurretBar/TurretButtons

var collector_health: float = 100.0
var max_collector_health: float = 100.0
var cargo_current: int = 0
var cargo_capacity: int = 50

# Set by GameManager after collector ship is spawned
var collector_ship: CollectorShip = null:
	set(value):
		collector_ship = value
		if collector_ship:
			_build_turret_bar()

# Maps Turret → Button so we can update style on toggle
var _turret_buttons: Dictionary = {}


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


# ── Turret bar ────────────────────────────────────────────────────────────────

func _build_turret_bar() -> void:
	# Clear any existing buttons
	for child in turret_buttons.get_children():
		child.queue_free()
	_turret_buttons.clear()

	for turret in collector_ship.get_turrets():
		var slot := _make_turret_slot(turret)
		turret_buttons.add_child(slot)


func _make_turret_slot(turret: Turret) -> Control:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(64, 64)
	btn.focus_mode = Control.FOCUS_NONE
	_apply_button_style(btn, turret, true)
	btn.pressed.connect(_on_turret_toggled.bind(turret, btn))

	var label := Label.new()
	label.text = turret.get_turret_name()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	label.add_theme_font_size_override("font_size", 14)

	vbox.add_child(btn)
	vbox.add_child(label)
	_turret_buttons[turret] = btn
	return vbox


func _apply_button_style(btn: Button, turret: Turret, is_active: bool) -> void:
	var color: Color = turret.get_icon_color() if is_active else Color(0.25, 0.25, 0.28)

	var style_normal := StyleBoxFlat.new()
	style_normal.corner_radius_top_left     = 32
	style_normal.corner_radius_top_right    = 32
	style_normal.corner_radius_bottom_left  = 32
	style_normal.corner_radius_bottom_right = 32
	style_normal.bg_color = color
	if is_active:
		style_normal.border_width_top    = 2
		style_normal.border_width_bottom = 2
		style_normal.border_width_left   = 2
		style_normal.border_width_right  = 2
		style_normal.border_color = color.lightened(0.4)

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = color.lightened(0.15) if is_active else Color(0.35, 0.35, 0.38)

	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = color.darkened(0.2)

	btn.add_theme_stylebox_override("normal",   style_normal)
	btn.add_theme_stylebox_override("hover",    style_hover)
	btn.add_theme_stylebox_override("pressed",  style_pressed)
	btn.add_theme_stylebox_override("focus",    style_normal)

	# Icon letter centred on the button
	btn.text = turret.get_turret_name().left(1)
	btn.add_theme_color_override("font_color", Color.WHITE if is_active else Color(0.5, 0.5, 0.5))
	btn.add_theme_font_size_override("font_size", 22)


func _on_turret_toggled(turret: Turret, btn: Button) -> void:
	turret.active = not turret.active
	_apply_button_style(btn, turret, turret.active)
