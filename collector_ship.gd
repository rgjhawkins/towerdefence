extends Node3D

signal scrap_collected(amount: int)

@export var rotation_speed: float = 180.0  # Degrees per second
@export var thrust_power: float = 15.0
@export var max_speed: float = 12.0
@export var drag: float = 0.98  # Velocity multiplier per frame
@export var tractor_range: float = 2.5  # Range to start pulling scrap
@export var tractor_power: float = 8.0  # Pull speed
@export var collect_distance: float = 0.5  # Distance to collect scrap

var velocity: Vector3 = Vector3.ZERO
var is_thrusting: bool = false
var is_tractoring: bool = false
var beam_lines: Array[MeshInstance3D] = []
var beam_material: StandardMaterial3D

@onready var engine_glow: CSGCylinder3D = $Ship/EngineGlow
@onready var engine_glow_left: CSGCylinder3D = $Ship/EngineGlowLeft
@onready var engine_glow_right: CSGCylinder3D = $Ship/EngineGlowRight
@onready var tractor_turret: Node3D = $Ship/TractorTurret


func _ready() -> void:
	# Create glowing blue beam material
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.3, 0.6, 1.0, 0.8)
	beam_material.emission_enabled = true
	beam_material.emission = Color(0.4, 0.7, 1.0, 1.0)
	beam_material.emission_energy_multiplier = 3.0
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process(delta: float) -> void:
	_handle_input(delta)
	_apply_physics(delta)
	_update_engine_glow()
	_process_tractor_beam(delta)


func _handle_input(delta: float) -> void:
	# Rotation (left/right arrows)
	if Input.is_action_pressed("ui_left"):
		rotation.y += deg_to_rad(rotation_speed) * delta
	if Input.is_action_pressed("ui_right"):
		rotation.y -= deg_to_rad(rotation_speed) * delta

	# Thrust (up arrow)
	is_thrusting = Input.is_action_pressed("ui_up")
	if is_thrusting:
		var forward := -global_transform.basis.z
		velocity += forward * thrust_power * delta


func _apply_physics(delta: float) -> void:
	# Apply drag
	velocity *= drag

	# Clamp speed
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

	# Keep on horizontal plane
	velocity.y = 0

	# Apply movement
	position += velocity * delta


func _update_engine_glow() -> void:
	if engine_glow:
		engine_glow.visible = is_thrusting
	if engine_glow_left:
		engine_glow_left.visible = is_thrusting
	if engine_glow_right:
		engine_glow_right.visible = is_thrusting


func _process_tractor_beam(delta: float) -> void:
	var scrap_pieces := get_tree().get_nodes_in_group("scrap")
	var active_targets: Array[Node3D] = []

	for scrap in scrap_pieces:
		var scrap_node := scrap as Node3D
		if not scrap_node:
			continue

		var distance := global_position.distance_to(scrap_node.global_position)

		if distance < tractor_range:
			active_targets.append(scrap_node)
			# Pull scrap towards ship
			var direction := (global_position - scrap_node.global_position).normalized()
			scrap_node.global_position += direction * tractor_power * delta

			# Check if close enough to collect
			if distance < collect_distance:
				_collect_scrap(scrap_node)

	is_tractoring = active_targets.size() > 0
	_update_beam_lines(active_targets)


func _update_beam_lines(targets: Array[Node3D]) -> void:
	# Create more beam lines if needed
	while beam_lines.size() < targets.size():
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.02
		cylinder.bottom_radius = 0.02
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
			var turret_pos := tractor_turret.global_position
			var target_pos := target.global_position
			var midpoint := (turret_pos + target_pos) / 2.0
			var distance := turret_pos.distance_to(target_pos)

			# Position at midpoint
			beam.global_position = midpoint

			# Scale to match distance
			beam.scale = Vector3(1, distance, 1)

			# Orient to point at target
			beam.look_at(target_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		else:
			beam.visible = false


func _collect_scrap(scrap: Node) -> void:
	scrap_collected.emit(1)
	scrap.queue_free()
