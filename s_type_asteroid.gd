class_name STypeAsteroid
extends AsteroidBase
## S-type (silicaceous) asteroid.
## Moderately common. Stony reddish-brown surface. Standard ore yield.

func get_asteroid_type() -> String: return "S"
func get_ore_type()      -> String: return "silicate"

func get_ore_capacity(t: String) -> int:
	match t:
		"large":  return 50
		"medium": return 25
		_:        return 12

func _get_surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.32, 0.20)  # Reddish-brown stony
	mat.roughness    = 0.88
	mat.metallic     = 0.08
	return mat
