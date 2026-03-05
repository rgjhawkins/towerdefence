class_name AsteroidField
extends "res://space_anomaly.gd"

const NUM_ASTEROIDS  := 50
const NUM_HOLES      := 3
const CLUSTER_SPREAD := 40.0
const CLUSTER_CENTRE := Vector3(0.0, 1.5, -18.0)
const EXPLOSION_SCENE := preload("res://explosion.tscn")

const ORE_CAPACITY := {"large": 50, "medium": 25, "small": 12}

# Full pool of [path, radius, tier] — 30 large + 30 medium + 30 small = 90 variants
var _pool:        Array = []
var _pool_large:  Array = []
var _pool_medium: Array = []
var _pool_small:  Array = []

# Per-asteroid state
var _bodies:        Array[StaticBody3D] = []
var _rot_axes:      Array[Vector3]      = []
var _rot_speeds:    Array[float]        = []
var _hole_markers:  Array[Node3D]       = []
var _holes_by_body: Dictionary          = {}  # StaticBody3D → Array[Node3D]


func _ready() -> void:
	add_to_group("space_anomalies")
	_build_pool()
	_spawn_cluster()


func _build_pool() -> void:
	for i in 30:
		var e := ["res://assets/asteroids/asteroid_%02d.glb" % i,     2.0, "large"]
		_pool.append(e);  _pool_large.append(e)
	for i in 30:
		var e := ["res://assets/asteroids/asteroid_med_%02d.glb" % i, 1.2, "medium"]
		_pool.append(e);  _pool_medium.append(e)
	for i in 30:
		var e := ["res://assets/asteroids/asteroid_sml_%02d.glb" % i, 0.6, "small"]
		_pool.append(e);  _pool_small.append(e)


# ── Cluster spawning ──────────────────────────────────────────────────────────

func _spawn_cluster() -> void:
	var placed: Array = []  # Array of {pos: Vector3, radius: float}
	for _i in NUM_ASTEROIDS:
		var entry:  Array  = _pool[randi() % _pool.size()]
		var path:   String = entry[0]
		var radius: float  = entry[1]
		var tier:   String = entry[2]
		var pos     := _pick_position(placed, radius)
		placed.append({"pos": pos, "radius": radius})
		_spawn_asteroid(pos, path, radius, tier)


func _pick_position(placed: Array, new_radius: float) -> Vector3:
	for _attempt in 300:
		# Polar coords with squared radius — high density at centre, tapering to edge
		var angle := randf() * TAU
		var t     := randf()
		var r     := t * t * CLUSTER_SPREAD          # squaring biases toward centre
		var offset := Vector3(
			cos(angle) * r,
			randf_range(-1.0, 1.0) * (1.0 - t),     # less vertical spread at the edges
			sin(angle) * r
		)
		var pos   := CLUSTER_CENTRE + offset
		var valid := true
		for p in placed:
			var min_dist: float = p["radius"] + new_radius + 0.8
			if pos.distance_to(p["pos"]) < min_dist:
				valid = false
				break
		if valid:
			return pos
	# Fallback: nudge outward so it never stacks exactly on another
	return CLUSTER_CENTRE + Vector3(placed.size() * (new_radius * 2.0 + 1.0), 0.0, 0.0)


func _spawn_asteroid(pos: Vector3, path: String, radius: float, tier: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.add_to_group("asteroids")
	body.set_meta("radius", radius)
	body.set_meta("tier", tier)
	body.set_meta("ore_remaining", ORE_CAPACITY[tier])
	add_child(body)
	_bodies.append(body)

	var scene: PackedScene = load(path)
	var mesh_inst := scene.instantiate() as Node3D
	mesh_inst.scale = Vector3.ONE * radius
	body.add_child(mesh_inst)

	# Trimesh collision derived from the actual mesh, scaled to match
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
			faces[i] *= radius
		trimesh.set_faces(faces)
		col.shape = trimesh
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		col.shape = sphere
	body.add_child(col)

	_rot_axes.append(Vector3(randf_range(-1.0, 1.0),
							 randf_range(-1.0, 1.0),
							 randf_range(-1.0, 1.0)).normalized())
	_rot_speeds.append(randf_range(0.25, 0.65))

	_holes_by_body[body] = []
	_create_holes(mesh_inst, body, radius)


# ── Holes / spawn markers ─────────────────────────────────────────────────────

func _create_holes(mesh_root: Node3D, body: StaticBody3D, radius: float) -> void:
	for i in NUM_HOLES:
		var angle     := (float(i) / NUM_HOLES) * TAU + randf_range(-0.2, 0.2)
		var elevation := randf_range(-0.3, 0.3)
		var dir := Vector3(
			cos(angle) * cos(elevation),
			sin(elevation),
			sin(angle) * cos(elevation)
		).normalized()
		var marker := _add_hole(mesh_root, dir, radius)
		_hole_markers.append(marker)
		_holes_by_body[body].append(marker)


func _add_hole(mesh_root: Node3D, surface_dir: Vector3, radius: float) -> Node3D:
	var marker    := Node3D.new()
	marker.position = surface_dir * radius
	var up        := surface_dir
	var arbitrary := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right     := up.cross(arbitrary).normalized()
	var fwd       := right.cross(up).normalized()
	marker.transform.basis = Basis(right, up, fwd)
	mesh_root.add_child(marker)
	return marker


## Returns a random spawn marker node (position updates live as its asteroid rotates).
func get_random_spawn_marker() -> Node3D:
	if _hole_markers.is_empty():
		return null
	return _hole_markers[randi() % _hole_markers.size()]


## Returns a spawn marker belonging to a specific asteroid body.
## Falls back to any random marker if the body is not found.
func get_spawn_marker_for_body(body: StaticBody3D) -> Node3D:
	if body in _holes_by_body and not _holes_by_body[body].is_empty():
		var holes: Array = _holes_by_body[body]
		return holes[randi() % holes.size()]
	return get_random_spawn_marker()


# ── Depletion & splitting ─────────────────────────────────────────────────────

## Override: split or crumble the depleted asteroid body.
func deplete_body(body: StaticBody3D) -> void:
	var pos  := body.global_position
	var tier: String = body.get_meta("tier", "small")

	# Dust/explosion at the break point
	var exp := EXPLOSION_SCENE.instantiate() as Node3D
	get_tree().root.add_child(exp)
	exp.global_position = pos

	_remove_body(body)
	body.queue_free()

	# Split into two of the next size down
	match tier:
		"large":
			# Place the two medium fragments on opposite sides so they never overlap
			# medium radius = 1.2, so offset each by 1.2 + 0.8 = 2.0 from centre
			var split_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			_spawn_asteroid_by_tier(pos + split_dir * 2.0, "medium")
			_spawn_asteroid_by_tier(pos - split_dir * 2.0, "medium")
		"medium":
			# small radius = 0.6, so offset each by 0.6 + 0.8 = 1.4 from centre
			var split_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			_spawn_asteroid_by_tier(pos + split_dir * 1.4, "small")
			_spawn_asteroid_by_tier(pos - split_dir * 1.4, "small")
		# small → crumbles to dust, nothing spawns


func _spawn_asteroid_by_tier(pos: Vector3, tier: String) -> void:
	var pool: Array = _pool_large if tier == "large" else (_pool_medium if tier == "medium" else _pool_small)
	var entry: Array = pool[randi() % pool.size()]
	_spawn_asteroid(pos, entry[0], entry[1], tier)


func _remove_body(body: StaticBody3D) -> void:
	var idx := _bodies.find(body)
	if idx == -1:
		return
	_bodies.remove_at(idx)
	_rot_axes.remove_at(idx)
	_rot_speeds.remove_at(idx)
	if body in _holes_by_body:
		for marker in _holes_by_body[body]:
			_hole_markers.erase(marker)
		_holes_by_body.erase(body)


# ── Update ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	for i in _bodies.size():
		_bodies[i].rotate(_rot_axes[i], _rot_speeds[i] * delta)
