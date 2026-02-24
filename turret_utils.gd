class_name TurretUtils
## Shared algorithms used by multiple turret types.


## Returns the predicted world position where a bullet fired at bullet_speed
## from muzzle_pos will intercept a target moving at target_vel.
## Solves the quadratic |rel + vel·t| = speed·t for the smallest positive t,
## clamped to [0, 3] seconds.
static func lead_position(
		muzzle_pos: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		bullet_speed: float
) -> Vector3:
	var rel := target_pos - muzzle_pos
	var a := target_vel.length_squared() - bullet_speed * bullet_speed
	var b := 2.0 * rel.dot(target_vel)
	var c := rel.length_squared()
	var t := 0.0
	if abs(a) < 0.001:
		if abs(b) > 0.001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = min(t1, t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2
	return target_pos + target_vel * clamp(t, 0.0, 3.0)


## Grows the beams array as needed and repositions/orients each beam cylinder
## to stretch from source_pos to the corresponding target in targets.
## New beam nodes are added as children of parent.
static func sync_beam_lines(
		beams: Array,
		targets: Array,
		source_pos: Vector3,
		material: Material,
		radius: float,
		parent: Node3D
) -> void:
	while beams.size() < targets.size():
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = 1.0
		cylinder.material = material
		beam.mesh = cylinder
		parent.add_child(beam)
		beams.append(beam)

	for i in range(beams.size()):
		var beam := beams[i] as MeshInstance3D
		if i < targets.size():
			var target := targets[i] as Node3D
			var target_pos := target.global_position
			var dist := source_pos.distance_to(target_pos)
			beam.visible = true
			beam.global_position = (source_pos + target_pos) / 2.0
			# look_at resets scale, so apply scale after
			beam.look_at(target_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
			beam.scale = Vector3(1.0, dist, 1.0)
		else:
			beam.visible = false
