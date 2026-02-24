class_name MiningLaserTurret
extends Turret
## Collector hardpoint turret: auto-aims at the nearest asteroid and fires a
## continuous mining laser. Emits asteroid_mined when a scrap cycle completes.

signal asteroid_mined(hit_point: Vector3)

const SCRAP_SCENE := preload("res://scrap_piece.tscn")
const MINING_RANGE := 8.0
const MINING_SCRAP_RATE := 0.4   # Scrap pieces per second
const LASER_RADIUS := 0.03
const SCRAP_EJECT_SPEED := 1.2

var _mining_target: StaticBody3D = null
var _laser_beam: MeshInstance3D = null
var _laser_material: StandardMaterial3D = null
var _impact_glow: MeshInstance3D = null
var _mining_accumulator: float = 0.0


func get_turret_name() -> String:
	return "Mining Laser"


func _ready() -> void:
	_build_visuals()


func _build_visuals() -> void:
	_laser_material = StandardMaterial3D.new()
	_laser_material.albedo_color = Color(1.0, 0.25, 0.05, 0.9)
	_laser_material.emission_enabled = true
	_laser_material.emission = Color(1.0, 0.35, 0.1, 1.0)
	_laser_material.emission_energy_multiplier = 6.0
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var laser_cylinder := CylinderMesh.new()
	laser_cylinder.top_radius = LASER_RADIUS
	laser_cylinder.bottom_radius = LASER_RADIUS
	laser_cylinder.height = 1.0
	laser_cylinder.material = _laser_material
	_laser_beam = MeshInstance3D.new()
	_laser_beam.mesh = laser_cylinder
	_laser_beam.visible = false
	add_child(_laser_beam)

	var impact_mat := StandardMaterial3D.new()
	impact_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.85)
	impact_mat.emission_enabled = true
	impact_mat.emission = Color(1.0, 0.5, 0.1, 1.0)
	impact_mat.emission_energy_multiplier = 8.0
	impact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var impact_sphere := SphereMesh.new()
	impact_sphere.radius = 0.22
	impact_sphere.height = 0.44
	impact_sphere.radial_segments = 8
	impact_sphere.rings = 4
	impact_sphere.material = impact_mat
	_impact_glow = MeshInstance3D.new()
	_impact_glow.mesh = impact_sphere
	_impact_glow.visible = false
	add_child(_impact_glow)


func _update(delta: float) -> void:
	# Find closest asteroid in range
	var closest: StaticBody3D = null
	var closest_dist := MINING_RANGE
	for node in get_tree().get_nodes_in_group("asteroids"):
		var asteroid := node as StaticBody3D
		if not asteroid:
			continue
		var dist := global_position.distance_to(asteroid.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = asteroid

	_mining_target = closest

	if not _mining_target:
		_laser_beam.visible = false
		_impact_glow.visible = false
		_mining_accumulator = 0.0
		return

	# Rotate turret to track asteroid (Y axis locked)
	var look_target := Vector3(
		_mining_target.global_position.x,
		global_position.y,
		_mining_target.global_position.z
	)
	look_at(look_target, Vector3.UP)

	# Beam starts slightly ahead of barrel tip
	var barrel_forward := -global_transform.basis.z
	var beam_start := global_position + barrel_forward * 0.14 + Vector3(0.0, 0.08, 0.0)

	var asteroid_radius: float = _mining_target.get_meta("radius", 1.0)
	var to_asteroid := (_mining_target.global_position - beam_start).normalized()
	var hit_point := _mining_target.global_position - to_asteroid * asteroid_radius

	var beam_length := beam_start.distance_to(hit_point)
	_laser_beam.visible = true
	_laser_beam.global_position = (beam_start + hit_point) / 2.0
	_laser_beam.look_at(hit_point, Vector3.UP)
	_laser_beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_laser_beam.scale = Vector3(1.0, beam_length, 1.0)

	var pulse := 0.85 + sin(Time.get_ticks_msec() * 0.008) * 0.15
	_impact_glow.visible = true
	_impact_glow.global_position = hit_point
	_impact_glow.scale = Vector3(pulse, pulse, pulse)

	_mining_accumulator += MINING_SCRAP_RATE * delta
	if _mining_accumulator >= 1.0:
		_mining_accumulator -= 1.0
		_spawn_mined_scrap(hit_point)


func _spawn_mined_scrap(hit_point: Vector3) -> void:
	var count := randi_range(1, 5)
	var surface_normal := (hit_point - _mining_target.global_position).normalized()
	for i in count:
		var scrap := SCRAP_SCENE.instantiate()
		get_tree().root.add_child(scrap)
		scrap.global_position = hit_point + Vector3(
			randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)
		)
		var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		var eject_dir := Vector3(
			(surface_normal + scatter).x, 0.0, (surface_normal + scatter).z
		).normalized()
		scrap.drift_direction = eject_dir * randf_range(
			SCRAP_EJECT_SPEED * 0.6, SCRAP_EJECT_SPEED * 1.4
		)

	asteroid_mined.emit(hit_point)
