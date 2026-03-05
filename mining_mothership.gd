class_name MiningMothership
extends Ship
## Mining capital ship that serves as the player's mobile base.
## Extends Ship — movement logic will be added in a future pass.
## Has 5 dorsal turret hardpoints and a rear landing pad / cargo bay.

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal ore_collected(amount: int)

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
	energy = max_energy  # max_energy inherited from Ship

	# Load the Blender-generated model and attach it
	var model_res := load("res://assets/mothership/mothership.glb") as PackedScene
	if model_res:
		var model := model_res.instantiate()
		model.name = "Model"
		add_child(model)
	else:
		push_warning("MiningMothership: could not load mothership.glb — model missing.")

	_build_docking_ring()


func _build_docking_ring() -> void:
	var ring_node := get_node_or_null("DockingRing") as Node3D
	if not ring_node:
		return

	const RING_RADIUS    := 1.2   # metres from centre to ring mid-line
	const LIGHT_COUNT    := 8
	const AMBER          := Color(1.0, 0.65, 0.08, 1.0)
	const AMBER_EMIT     := Color(1.0, 0.55, 0.05, 1.0)

	# Torus mesh — Godot's TorusMesh lies in the XZ plane (horizontal),
	# so it reads as a circle from the top-down camera.
	var torus_mat := StandardMaterial3D.new()
	torus_mat.albedo_color                = AMBER
	torus_mat.emission_enabled            = true
	torus_mat.emission                    = AMBER_EMIT
	torus_mat.emission_energy_multiplier  = 4.0

	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.12   # tube inner edge
	torus.outer_radius = RING_RADIUS + 0.12   # tube outer edge
	torus.material     = torus_mat

	var torus_inst := MeshInstance3D.new()
	torus_inst.mesh = torus
	ring_node.add_child(torus_inst)

	# Eight glowing marker spheres + OmniLight3D, evenly spaced around the ring
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color               = AMBER
	sphere_mat.emission_enabled           = true
	sphere_mat.emission                   = AMBER_EMIT
	sphere_mat.emission_energy_multiplier = 6.0

	for i in LIGHT_COUNT:
		var angle := (float(i) / LIGHT_COUNT) * TAU
		var pos   := Vector3(cos(angle) * RING_RADIUS, 0.0, sin(angle) * RING_RADIUS)

		# Small glowing orb at each lamp position
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius   = 0.10
		sphere.height   = 0.20
		sphere.material = sphere_mat
		orb.mesh        = sphere
		orb.position    = pos
		ring_node.add_child(orb)

		# Actual dynamic light
		var light := OmniLight3D.new()
		light.position     = pos
		light.light_color  = Color(1.0, 0.72, 0.35)
		light.light_energy = 2.0
		light.omni_range   = 4.0
		ring_node.add_child(light)


func _process(delta: float) -> void:
	if shield < max_shield:
		shield = minf(shield + shield_regen_rate * delta, max_shield)
		shield_changed.emit(shield, max_shield)
	_regen_energy(delta)


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


func collect_ore(amount: int) -> void:
	ore_collected.emit(amount)


func _on_destroyed() -> void:
	print("MiningMothership destroyed — game over!")
