class_name AsteroidField
extends Node3D

const ASTEROID_RADIUS  := 2.0
const NUM_ASTEROIDS    := 5
const NUM_HOLES        := 3
const NUM_VARIANTS     := 30
const CLUSTER_SPREAD   := 10.0   # Search radius around the cluster centre
const MIN_SEPARATION   := ASTEROID_RADIUS * 2.8   # ~5.6 units — prevents visual overlap

# Per-asteroid state
var _bodies:     Array[StaticBody3D] = []
var _rot_axes:   Array[Vector3]      = []
var _rot_speeds: Array[float]        = []
var _hole_markers: Array[Node3D]     = []

const CLUSTER_CENTRE := Vector3(0.0, 1.5, -18.0)


func _ready() -> void:
	add_to_group("asteroid_fields")
	_spawn_cluster()


# ── Cluster spawning ──────────────────────────────────────────────────────────

func _spawn_cluster() -> void:
	var placed: Array[Vector3] = []
	for _i in NUM_ASTEROIDS:
		var pos := _pick_position(placed)
		placed.append(pos)
		_spawn_asteroid(pos)


func _pick_position(placed: Array[Vector3]) -> Vector3:
	for _attempt in 200:
		var offset := Vector3(
			randf_range(-CLUSTER_SPREAD, CLUSTER_SPREAD),
			randf_range(-CLUSTER_SPREAD * 0.25, CLUSTER_SPREAD * 0.25),
			randf_range(-CLUSTER_SPREAD, CLUSTER_SPREAD)
		)
		var pos := CLUSTER_CENTRE + offset
		var valid := true
		for p in placed:
			if pos.distance_to(p) < MIN_SEPARATION:
				valid = false
				break
		if valid:
			return pos
	# Fallback: line them up if rejection sampling exhausts attempts
	return CLUSTER_CENTRE + Vector3(placed.size() * MIN_SEPARATION, 0.0, 0.0)


func _spawn_asteroid(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.add_to_group("asteroids")
	body.set_meta("radius", ASTEROID_RADIUS)
	add_child(body)
	_bodies.append(body)

	# Random mesh variant
	var variant := randi() % NUM_VARIANTS
	var scene: PackedScene = load("res://assets/asteroids/asteroid_%02d.glb" % variant)
	var mesh_inst := scene.instantiate() as Node3D
	mesh_inst.scale = Vector3.ONE * ASTEROID_RADIUS
	body.add_child(mesh_inst)

	# Trimesh collision derived from the actual mesh
	var col := CollisionShape3D.new()
	var mi: MeshInstance3D = null
	for child in mesh_inst.get_children():
		if child is MeshInstance3D:
			mi = child
			break
	if mi:
		var trimesh := mi.mesh.create_trimesh_shape() as ConcavePolygonShape3D
		var faces := trimesh.get_faces()
		for i in faces.size():
			faces[i] *= ASTEROID_RADIUS
		trimesh.set_faces(faces)
		col.shape = trimesh
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = ASTEROID_RADIUS
		col.shape = sphere
	body.add_child(col)

	# Each asteroid spins on a slightly different axis and speed
	_rot_axes.append(Vector3(randf_range(-1.0, 1.0),
	                         randf_range(-1.0, 1.0),
	                         randf_range(-1.0, 1.0)).normalized())
	_rot_speeds.append(randf_range(0.25, 0.65))

	_create_holes(mesh_inst)


# ── Holes / spawn markers ─────────────────────────────────────────────────────

func _create_holes(mesh_root: Node3D) -> void:
	for i in NUM_HOLES:
		var angle     := (float(i) / NUM_HOLES) * TAU + randf_range(-0.2, 0.2)
		var elevation := randf_range(-0.3, 0.3)
		var dir := Vector3(
			cos(angle) * cos(elevation),
			sin(elevation),
			sin(angle) * cos(elevation)
		).normalized()
		_hole_markers.append(_add_hole(mesh_root, dir))


func _add_hole(mesh_root: Node3D, surface_dir: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.position = surface_dir * ASTEROID_RADIUS
	var up        := surface_dir
	var arbitrary := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right     := up.cross(arbitrary).normalized()
	var fwd       := right.cross(up).normalized()
	marker.transform.basis = Basis(right, up, fwd)
	mesh_root.add_child(marker)
	return marker


## Returns the world position of a random hole across all asteroids in the cluster.
func get_random_hole_position() -> Vector3:
	if _hole_markers.is_empty():
		return CLUSTER_CENTRE
	return _hole_markers[randi() % _hole_markers.size()].global_position


## Returns a random hole marker node (position updates live as its asteroid rotates).
func get_random_hole_marker() -> Node3D:
	if _hole_markers.is_empty():
		return null
	return _hole_markers[randi() % _hole_markers.size()]


# ── Update ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	for i in _bodies.size():
		_bodies[i].rotate(_rot_axes[i], _rot_speeds[i] * delta)
