class_name MTypeAsteroid
extends AsteroidBase
## M-type (metallic) asteroid.
## Rare. Bright silvery-grey surface with high metallic sheen.
## Lower ore count but highest future value per piece.

func get_asteroid_type() -> String: return "M"
func get_ore_type()      -> String: return "metal"

func get_ore_capacity(t: String) -> int:
	match t:
		"large":  return 35
		"medium": return 18
		_:        return 9

func _get_surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.65, 0.70)  # Cool silver-grey
	mat.roughness    = 0.25
	mat.metallic     = 0.92
	return mat
