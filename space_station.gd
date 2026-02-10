extends Node3D

signal scrap_collected(amount: int)

@export var tractor_range: float = 5.0  # Station radius
@export var tractor_power: float = 6.0  # Pull speed
@export var collect_distance: float = 0.8  # Distance to collect
@export var shield_radius: float = 3.0  # Shield bubble size (covers central station only)
@export var shield_flash_duration: float = 0.3  # How long flash lasts

var beam_lines: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D
var shield_mesh: MeshInstance3D
var shield_material: StandardMaterial3D
var shield_flash_timer: float = 0.0

@onready var intake: Node3D = $ScrapIntake


func _ready() -> void:
	# Create glowing orange beam material for station tractor
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(1, 0.5, 0.2, 0.6)
	beam_material.emission_enabled = true
	beam_material.emission = Color(1, 0.4, 0.1, 1)
	beam_material.emission_energy_multiplier = 2.0
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Create shield bubble
	_create_shield_bubble()

	# Connect to HUD shield_hit signal
	await get_tree().process_frame
	var hud = get_tree().root.get_node_or_null("Main/HUD")
	if hud and hud.has_signal("shield_hit"):
		hud.shield_hit.connect(_on_shield_hit)


func _create_shield_bubble() -> void:
	shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = shield_radius
	sphere.height = shield_radius * 2
	sphere.radial_segments = 48
	sphere.rings = 24
	shield_mesh.mesh = sphere

	shield_material = StandardMaterial3D.new()
	shield_material.albedo_color = Color(0.4, 0.8, 1, 0)
	shield_material.emission_enabled = true
	shield_material.emission = Color(0.2, 0.5, 1, 1)
	shield_material.emission_energy_multiplier = 0.5
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mesh.material_override = shield_material

	shield_mesh.position = Vector3(0, 1, 0)  # Center on station
	add_child(shield_mesh)


func _on_shield_hit() -> void:
	shield_flash_timer = shield_flash_duration


func _process(delta: float) -> void:
	_process_tractor_beam(delta)
	_process_shield_flash(delta)


func _process_shield_flash(delta: float) -> void:
	if shield_flash_timer > 0:
		shield_flash_timer -= delta
		var t := shield_flash_timer / shield_flash_duration
		# Subtle shimmer effect - low alpha, gentle glow
		var alpha := t * 0.15
		shield_material.albedo_color = Color(0.4, 0.8, 1, alpha)
		shield_material.emission_energy_multiplier = 0.3 + t * 0.7
	else:
		shield_material.albedo_color = Color(0.4, 0.8, 1, 0)
		shield_material.emission_energy_multiplier = 0.0


func _process_tractor_beam(delta: float) -> void:
	var scrap_pieces := get_tree().get_nodes_in_group("scrap")
	var active_targets: Array[Node3D] = []
	var intake_pos := intake.global_position if intake else Vector3(0, 2.3, 0)

	for scrap in scrap_pieces:
		var scrap_node := scrap as Node3D
		if not scrap_node:
			continue

		# Check horizontal distance (within station radius)
		var horizontal_dist := Vector2(scrap_node.global_position.x, scrap_node.global_position.z).length()

		# Only pull scrap that's above station and within radius
		if horizontal_dist < tractor_range and scrap_node.global_position.y > 0.5:
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
	# Create more beam lines if needed
	while beam_lines.size() < targets.size():
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.015
		cylinder.bottom_radius = 0.015
		cylinder.height = 1.0
		cylinder.material = beam_material
		beam.mesh = cylinder
		add_child(beam)
		beam_lines.append(beam)

	# Update each beam line
	for i in range(beam_lines.size()):
		var beam := beam_lines[i]
		if i < targets.size():
			beam.visible = true
			var target := targets[i]
			var target_pos := target.global_position
			var midpoint := (intake_pos + target_pos) / 2.0
			var distance := intake_pos.distance_to(target_pos)

			# Position at midpoint
			beam.global_position = midpoint

			# Scale to match distance
			beam.scale = Vector3(1, distance, 1)

			# Orient to point at target
			beam.look_at(target_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		else:
			beam.visible = false
