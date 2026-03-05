class_name CTypeAsteroid
extends AsteroidBase
## C-type (carbonaceous) asteroid.
## Most common. Dark, carbon-rich surface. Moderate ore yield.

func get_asteroid_type() -> String: return "C"
func get_ore_type()      -> String: return "carbon"

func get_ore_capacity(t: String) -> int:
	match t:
		"large":  return 60
		"medium": return 30
		_:        return 15

func _get_surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)  # Near-black carbonaceous
	mat.roughness    = 0.97
	mat.metallic     = 0.0
	return mat
