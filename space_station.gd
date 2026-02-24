class_name SpaceStation
extends Node3D

signal scrap_collected(amount: int)

# Tractor beam constants
const BEAM_RADIUS := 0.015
const MIN_SCRAP_HEIGHT := 0.5
const SHIELD_CENTER_OFFSET := Vector3(0, 1, 0)
const DEFAULT_INTAKE_POS := Vector3(0, 2.3, 0)

# Tractor beam settings
@export var tractor_range: float = 5.0
@export var tractor_power: float = 6.0
@export var collect_distance: float = 0.8

# Shield settings
@export var shield_radius: float = 3.0
@export var shield_flash_duration: float = 0.3
@export var shield_pulse_duration: float = 0.5

# Shield colors (configurable)
@export var shield_base_color := Color(0.4, 0.8, 1, 0)
@export var shield_emission_color := Color(0.2, 0.5, 1, 1)
@export var shield_hit_color := Color(0.4, 0.8, 1)
@export var shield_regen_color := Color(0.3, 1, 0.6)
@export var shield_hit_max_alpha := 0.15
@export var shield_regen_max_alpha := 0.05

# Beam material colors
@export var beam_color := Color(1, 0.5, 0.2, 0.6)
@export var beam_emission_color := Color(1, 0.4, 0.1, 1)
@export var beam_emission_energy := 2.0

var beam_lines: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D
var shield_mesh: MeshInstance3D
var shield_material: StandardMaterial3D
var shield_flash_timer: float = 0.0
var shield_pulse_timer: float = 0.0

@onready var intake: Node3D = $ScrapIntake


func _ready() -> void:
	# Add to group for easy lookup
	add_to_group("space_station")

	# Create glowing orange beam material for station tractor
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = beam_color
	beam_material.emission_enabled = true
	beam_material.emission = beam_emission_color
	beam_material.emission_energy_multiplier = beam_emission_energy
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Create shield bubble
	_create_shield_bubble()

	# Connect to HUD shield signals using group
	await get_tree().process_frame
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		# Fallback to path-based lookup
		hud = get_tree().root.get_node_or_null("Main/HUD")
	if hud:
		if hud.has_signal("shield_hit"):
			hud.shield_hit.connect(_on_shield_hit)
		if hud.has_signal("shield_regen"):
			hud.shield_regen.connect(_on_shield_regen)


func _create_shield_bubble() -> void:
	shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = shield_radius
	sphere.height = shield_radius * 2
	sphere.radial_segments = 48
	sphere.rings = 24
	shield_mesh.mesh = sphere

	shield_material = StandardMaterial3D.new()
	shield_material.albedo_color = shield_base_color
	shield_material.emission_enabled = true
	shield_material.emission = shield_emission_color
	shield_material.emission_energy_multiplier = 0.5
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mesh.material_override = shield_material

	shield_mesh.position = SHIELD_CENTER_OFFSET
	add_child(shield_mesh)


func _on_shield_hit() -> void:
	shield_flash_timer = shield_flash_duration


func _on_shield_regen() -> void:
	shield_pulse_timer = shield_pulse_duration


func _process(delta: float) -> void:
	_process_tractor_beam(delta)
	_process_shield_effects(delta)


func _process_shield_effects(delta: float) -> void:
	# Hit flash takes priority over regen pulse
	if shield_flash_timer > 0:
		shield_flash_timer -= delta
		var t := shield_flash_timer / shield_flash_duration
		# Subtle shimmer effect - low alpha, gentle glow
		var alpha := t * shield_hit_max_alpha
		shield_material.albedo_color = Color(shield_hit_color.r, shield_hit_color.g, shield_hit_color.b, alpha)
		shield_material.emission_energy_multiplier = 0.3 + t * 0.7
	elif shield_pulse_timer > 0:
		shield_pulse_timer -= delta
		var t := shield_pulse_timer / shield_pulse_duration
		# Very dim pulse for regen - green tint
		var alpha := t * shield_regen_max_alpha
		shield_material.albedo_color = Color(shield_regen_color.r, shield_regen_color.g, shield_regen_color.b, alpha)
		shield_material.emission_energy_multiplier = 0.1 + t * 0.2
	else:
		shield_material.albedo_color = Color(shield_base_color.r, shield_base_color.g, shield_base_color.b, 0)
		shield_material.emission_energy_multiplier = 0.0


func _process_tractor_beam(delta: float) -> void:
	var scrap_pieces := get_tree().get_nodes_in_group("scrap")
	var active_targets: Array[Node3D] = []
	var intake_pos := intake.global_position if intake else DEFAULT_INTAKE_POS

	for scrap in scrap_pieces:
		var scrap_node := scrap as Node3D
		if not scrap_node:
			continue

		# Check horizontal distance (within station radius)
		var horizontal_dist := Vector2(scrap_node.global_position.x, scrap_node.global_position.z).length()

		# Only pull scrap that's above station and within radius
		if horizontal_dist < tractor_range and scrap_node.global_position.y > MIN_SCRAP_HEIGHT:
			active_targets.append(scrap_node)

			# Pull scrap towards intake
			var direction := (intake_pos - scrap_node.global_position).normalized()
			scrap_node.global_position += direction * tractor_power * delta

			# Check if close enough to collect
			var dist_to_intake := scrap_node.global_position.distance_to(intake_pos)
			if dist_to_intake < collect_distance:
				scrap_collected.emit(1)
				scrap_node.queue_free()

	_update_beam_lines(active_targets, intake_pos)


func _update_beam_lines(targets: Array[Node3D], intake_pos: Vector3) -> void:
	TurretUtils.sync_beam_lines(beam_lines, targets, intake_pos, beam_material, BEAM_RADIUS, self)
