"""
Blender 5.x headless script — generates 90 procedural asteroid meshes:
  30 large  → assets/asteroids/asteroid_00–29.glb      (radius 2.0 in Godot)
  30 medium → assets/asteroids/asteroid_med_00–29.glb  (radius 1.2 in Godot)
  30 small  → assets/asteroids/asteroid_sml_00–29.glb  (radius 0.6 in Godot)

Each mesh uses two material slots:
  slot 0 — rocky surface
  slot 1 — dark crater interior (black + faint purple depth-glow)

Run via:
  blender --background --python assets/gen_asteroid.py
"""

import bpy
import bmesh
import math
import os
import random
from mathutils import Vector


OUT_DIR      = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asteroids")
NUM_VARIANTS = 30


# ── Shared helpers ────────────────────────────────────────────────────────────

def _random_sphere_dir(rng: random.Random) -> Vector:
    theta = rng.uniform(0.0, math.tau)
    phi   = math.acos(rng.uniform(-1.0, 1.0))
    return Vector((math.sin(phi) * math.cos(theta),
                   math.sin(phi) * math.sin(theta),
                   math.cos(phi)))


def _crater_profile(t: float) -> float:
    """Smooth bowl depression at normalised distance t (0=centre, 1=edge).
    Pure cosine falloff — no raised rim, so no star-shaped topology artefacts."""
    if t >= 1.0:
        return 0.0
    return -(math.cos(t * math.pi * 0.5)) ** 2


def _carve(bm: bmesh.types.BMesh, craters: list) -> None:
    """Displace vertices into crater shapes."""
    bm.verts.ensure_lookup_table()
    for vert in bm.verts:
        vert_dir = vert.co.normalized()
        for c in craters:
            dot   = max(-1.0, min(1.0, vert_dir.dot(c["dir"])))
            angle = math.acos(dot)
            if angle < c["angular_radius"]:
                t = angle / c["angular_radius"]
                vert.co += vert_dir * _crater_profile(t) * c["depth"]


def _make_rock_material(name: str, rng: random.Random) -> bpy.types.Material:
    mat   = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # Output + shader
    out  = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rng.uniform(0.85, 0.97)
    bsdf.inputs["Metallic"].default_value  = rng.uniform(0.0, 0.05)
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Object-space coords so textures rotate with the asteroid
    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping   = nodes.new("ShaderNodeMapping")
    s = rng.uniform(0.8, 1.5)
    mapping.inputs["Scale"].default_value = (s, s, s)
    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])

    # Large-scale colour noise → colour ramp (dark stone to lighter grey-brown)
    n_color = nodes.new("ShaderNodeTexNoise")
    n_color.inputs["Scale"].default_value      = rng.uniform(1.5, 3.5)
    n_color.inputs["Detail"].default_value     = 8.0
    n_color.inputs["Roughness"].default_value  = 0.65
    n_color.inputs["Distortion"].default_value = rng.uniform(0.2, 0.6)
    links.new(mapping.outputs["Vector"], n_color.inputs["Vector"])

    ramp = nodes.new("ShaderNodeValToRGB")
    rd, gd, bd = rng.uniform(0.07, 0.15), rng.uniform(0.06, 0.12), rng.uniform(0.05, 0.11)
    rl, gl, bl = rng.uniform(0.22, 0.38), rng.uniform(0.18, 0.30), rng.uniform(0.14, 0.25)
    ramp.color_ramp.elements[0].color    = (rd, gd, bd, 1.0)
    ramp.color_ramp.elements[0].position = rng.uniform(0.0, 0.25)
    ramp.color_ramp.elements[1].color    = (rl, gl, bl, 1.0)
    ramp.color_ramp.elements[1].position = rng.uniform(0.55, 1.0)
    links.new(n_color.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"],  bsdf.inputs["Base Color"])

    # Fine-detail noise → bump map for micro surface texture
    n_bump = nodes.new("ShaderNodeTexNoise")
    n_bump.inputs["Scale"].default_value      = rng.uniform(6.0, 14.0)
    n_bump.inputs["Detail"].default_value     = 12.0
    n_bump.inputs["Roughness"].default_value  = 0.75
    n_bump.inputs["Distortion"].default_value = 0.3
    links.new(mapping.outputs["Vector"], n_bump.inputs["Vector"])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value  = rng.uniform(0.5, 1.0)
    bump.inputs["Distance"].default_value  = 0.02
    links.new(n_bump.outputs["Fac"],   bump.inputs["Height"])
    links.new(bump.outputs["Normal"],  bsdf.inputs["Normal"])

    return mat



def _cleanup() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for tex  in list(bpy.data.textures):  bpy.data.textures.remove(tex)
    for mat  in list(bpy.data.materials): bpy.data.materials.remove(mat)
    for mesh in list(bpy.data.meshes):    bpy.data.meshes.remove(mesh)


def _export(out_path: str) -> None:
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_materials="EXPORT",
        export_normals=True,
        export_yup=True,
    )


# ── Per-tier generators ───────────────────────────────────────────────────────

def generate(index: int) -> None:
    """Large asteroid variant."""
    rng = random.Random(index * 137 + 42)

    noise_scale      = rng.uniform(1.2, 2.2)
    disp_strength    = rng.uniform(0.38, 0.65)
    detail_scale     = rng.uniform(0.28, 0.55)
    detail_strength  = rng.uniform(0.10, 0.24)
    scale_xyz        = (rng.uniform(0.78, 1.22), rng.uniform(0.68, 1.08), rng.uniform(0.74, 1.14))
    num_craters      = rng.randint(8, 16)
    crater_depth_min = rng.uniform(0.20, 0.32)
    crater_depth_max = rng.uniform(0.35, 0.55)
    crater_rad_min   = rng.uniform(0.18, 0.28)
    crater_rad_max   = rng.uniform(0.32, 0.58)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0, location=(0, 0, 0))
    obj      = bpy.context.active_object
    obj.name = f"Asteroid_{index:02d}"

    tex1 = bpy.data.textures.new(f"Clouds_{index}", type="CLOUDS")
    tex1.noise_scale = noise_scale;  tex1.noise_depth = 4
    mod1 = obj.modifiers.new("Displace", type="DISPLACE")
    mod1.texture = tex1;  mod1.strength = disp_strength;  mod1.mid_level = 0.5

    tex2 = bpy.data.textures.new(f"Detail_{index}", type="CLOUDS")
    tex2.noise_scale = detail_scale;  tex2.noise_depth = 6
    mod2 = obj.modifiers.new("DisplaceDetail", type="DISPLACE")
    mod2.texture = tex2;  mod2.strength = detail_strength
    mod2.mid_level = 0.5;  mod2.texture_coords = "LOCAL"

    obj.scale = scale_xyz
    bpy.ops.object.transform_apply(scale=True)
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        bpy.ops.object.modifier_apply(modifier=mod.name)

    craters = [{"dir": _random_sphere_dir(rng),
                "angular_radius": rng.uniform(crater_rad_min, crater_rad_max),
                "depth": rng.uniform(crater_depth_min, crater_depth_max)}
               for _ in range(num_craters)]

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    _carve(bm, craters)
    bm.to_mesh(obj.data);  bm.free();  obj.data.update()

    bpy.ops.object.shade_smooth()

    obj.data.materials.append(_make_rock_material(f"AsteroidRock_{index:02d}", rng))

    out_path = os.path.join(OUT_DIR, f"asteroid_{index:02d}.glb")
    _export(out_path)
    print(f"[gen_asteroid] {index+1:2d}/{NUM_VARIANTS}  →  {out_path}")
    _cleanup()


def generate_tier(index: int, prefix: str, seed_offset: int,
                  subdivisions: int = 4,
                  disp_range: tuple = (0.38, 0.65),
                  crater_count_range: tuple = (8, 16),
                  crater_depth_range: tuple = (0.20, 0.55),
                  crater_rad_range: tuple = (0.18, 0.58)) -> None:
    """Medium / small asteroid variant."""
    rng = random.Random(index * 137 + seed_offset)

    noise_scale     = rng.uniform(1.2, 2.2)
    disp_strength   = rng.uniform(*disp_range)
    detail_scale    = rng.uniform(0.28, 0.55)
    detail_strength = rng.uniform(0.10, 0.24)
    scale_xyz       = (rng.uniform(0.72, 1.28), rng.uniform(0.62, 1.10), rng.uniform(0.68, 1.18))
    num_craters     = rng.randint(*crater_count_range)
    depth_min       = rng.uniform(crater_depth_range[0], crater_depth_range[0] + 0.12)
    depth_max       = rng.uniform(crater_depth_range[1] - 0.10, crater_depth_range[1])
    rad_min         = rng.uniform(crater_rad_range[0], crater_rad_range[0] + 0.10)
    rad_max         = rng.uniform(crater_rad_range[1] - 0.10, crater_rad_range[1])

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=(0, 0, 0))
    obj      = bpy.context.active_object
    obj.name = f"{prefix}_{index:02d}"

    tex1 = bpy.data.textures.new(f"Clouds_{prefix}_{index}", type="CLOUDS")
    tex1.noise_scale = noise_scale;  tex1.noise_depth = 4
    mod1 = obj.modifiers.new("Displace", type="DISPLACE")
    mod1.texture = tex1;  mod1.strength = disp_strength;  mod1.mid_level = 0.5

    tex2 = bpy.data.textures.new(f"Detail_{prefix}_{index}", type="CLOUDS")
    tex2.noise_scale = detail_scale;  tex2.noise_depth = 6
    mod2 = obj.modifiers.new("DisplaceDetail", type="DISPLACE")
    mod2.texture = tex2;  mod2.strength = detail_strength
    mod2.mid_level = 0.5;  mod2.texture_coords = "LOCAL"

    obj.scale = scale_xyz
    bpy.ops.object.transform_apply(scale=True)
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        bpy.ops.object.modifier_apply(modifier=mod.name)

    craters = [{"dir": _random_sphere_dir(rng),
                "angular_radius": rng.uniform(rad_min, rad_max),
                "depth": rng.uniform(depth_min, depth_max)}
               for _ in range(num_craters)]

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    _carve(bm, craters)
    bm.to_mesh(obj.data);  bm.free();  obj.data.update()

    bpy.ops.object.shade_smooth()

    obj.data.materials.append(_make_rock_material(f"Rock_{prefix}_{index:02d}", rng))

    out_path = os.path.join(OUT_DIR, f"{prefix}_{index:02d}.glb")
    _export(out_path)
    print(f"[gen_asteroid] {prefix} {index+1:2d}/30  →  {out_path}")
    _cleanup()


# ── Entry point ───────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

for i in range(NUM_VARIANTS):
    generate(i)

for i in range(30):
    generate_tier(i, "asteroid_med", seed_offset=1000,
                  subdivisions=4,
                  disp_range=(0.30, 0.58),
                  crater_count_range=(6, 14),
                  crater_depth_range=(0.22, 0.52),
                  crater_rad_range=(0.20, 0.55))

for i in range(30):
    generate_tier(i, "asteroid_sml", seed_offset=2000,
                  subdivisions=3,
                  disp_range=(0.25, 0.50),
                  crater_count_range=(5, 12),
                  crater_depth_range=(0.25, 0.58),
                  crater_rad_range=(0.22, 0.60))

print(f"[gen_asteroid] Done — 90 asteroids exported to {OUT_DIR}")
