class_name AsteroidBase
extends StaticBody3D
## Base class for all asteroid types (C, S, M).
## Call setup() after adding to the scene tree.
## Subclasses override the virtual methods to define type identity,
## appearance, ore type, and ore capacity.

const ORE_SCENE := preload("res://ore_piece.tscn")

var tier:          String = "large"
var radius:        float  = 2.0
var ore_remaining: int    = 0
var mesh_root:     Node3D = null   # The instantiated GLB node — used by AsteroidField for hole markers


# ── Virtual interface ─────────────────────────────────────────────────────────

## Short identifier string: "C", "S", or "M".
func get_asteroid_type() -> String:
	return ""

## Ore type identifier passed to spawned ore pieces.
func get_ore_type() -> String:
	return "generic"

## Ore capacity for a given physical tier.
func get_ore_capacity(t: String) -> int:
	match t:
		"large":  return 50
		"medium": return 25
		_:        return 12

## Surface material applied to the mesh. Override for type-specific look.
func _get_surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.4)
	mat.roughness    = 0.9
	mat.metallic     = 0.05
	return mat

## Ore scene to instantiate when this asteroid is mined.
## Override to return a type-specific ore scene.
func get_ore_scene() -> PackedScene:
	return ORE_SCENE


# ── Setup ─────────────────────────────────────────────────────────────────────

## Initialise the asteroid. Must be called after add_child().
func setup(model_path: String, r: float, t: String) -> void:
	radius        = r
	tier          = t
	ore_remaining = get_ore_capacity(t)

	add_to_group("asteroids")
	set_meta("radius",        radius)
	set_meta("tier",          tier)
	set_meta("ore_remaining", ore_remaining)
	set_meta("asteroid_type", get_asteroid_type())
	set_meta("ore_type",      get_ore_type())

	_load_model(model_path)


func _load_model(path: String) -> void:
	var scene := load(path) as PackedScene
	if not scene:
		push_warning("AsteroidBase: could not load model: " + path)
		return

	mesh_root       = scene.instantiate() as Node3D
	mesh_root.scale = Vector3.ONE * radius
	add_child(mesh_root)

	_apply_material()
	_build_collision()


func _apply_material() -> void:
	var mat := _get_surface_material()
	for child in mesh_root.get_children():
		if child is MeshInstance3D:
			child.material_override = mat


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var mi:  MeshInstance3D = null
	for child in mesh_root.get_children():
		if child is MeshInstance3D:
			mi = child
			break

	if mi:
		var trimesh := mi.mesh.create_trimesh_shape() as ConcavePolygonShape3D
		var faces   := trimesh.get_faces()
		for i in faces.size():
			faces[i] *= radius
		trimesh.set_faces(faces)
		col.shape = trimesh
	else:
		var sphere   := SphereShape3D.new()
		sphere.radius = radius
		col.shape     = sphere

	add_child(col)


# ── Ore depletion ─────────────────────────────────────────────────────────────

## Remove `amount` ore. Returns the new ore_remaining value.
func deplete_ore(amount: int) -> int:
	ore_remaining = maxi(0, ore_remaining - amount)
	set_meta("ore_remaining", ore_remaining)
	return ore_remaining
