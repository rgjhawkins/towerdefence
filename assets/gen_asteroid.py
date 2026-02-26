"""
Blender 5.x headless script — generates 90 procedural asteroid meshes:
  30 large  → assets/asteroids/asteroid_00–29.glb      (radius 2.0 in Godot)
  30 medium → assets/asteroids/asteroid_med_00–29.glb  (radius 1.2 in Godot)
  30 small  → assets/asteroids/asteroid_sml_00–29.glb  (radius 0.6 in Godot)

Colour is painted as per-vertex colour using mathutils.noise (two-octave
Perlin: large-scale patches + fine detail), which exports correctly in GLB.

Run via:
  blender --background --python assets/gen_asteroid.py
"""

import bpy
import bmesh
import math
import os
import random
from mathutils import Vector
from mathutils import noise as mnoise


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


def _paint_vertex_colors(obj: bpy.types.Object, rng: random.Random) -> None:
    """Paint two-octave Perlin noise colours onto a vertex colour attribute.
    This exports correctly in GLB and is read by Godot."""
    mesh = obj.data

    # Remove any leftover colour attributes
    while mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes[0])

    col_attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")

    scale_large = rng.uniform(1.5, 3.5)
    scale_fine  = rng.uniform(5.0, 10.0)

    # Dark and light ends of the colour ramp for this variant
    dr = rng.uniform(0.02, 0.07);  dg = rng.uniform(0.02, 0.06);  db = rng.uniform(0.01, 0.05)
    lr = rng.uniform(0.10, 0.18);  lg = rng.uniform(0.08, 0.15);  lb = rng.uniform(0.06, 0.12)

    # Random offset so each variant samples a different region of noise space
    offset = Vector((rng.uniform(-50.0, 50.0),
                     rng.uniform(-50.0, 50.0),
                     rng.uniform(-50.0, 50.0)))

    for i, vert in enumerate(mesh.vertices):
        pos_large = (vert.co + offset) * scale_large
        pos_fine  = (vert.co + offset) * scale_fine

        # mnoise.noise() returns roughly -1..1; map to 0..1
        t_large = mnoise.noise(pos_large) * 0.5 + 0.5
        t_fine  = mnoise.noise(pos_fine)  * 0.5 + 0.5
        t = max(0.0, min(1.0, t_large * 0.75 + t_fine * 0.25))

        col_attr.data[i].color = (
            dr + (lr - dr) * t,
            dg + (lg - dg) * t,
            db + (lb - db) * t,
            1.0,
        )


def _make_rock_material(name: str, rng: random.Random) -> bpy.types.Material:
    """Simple Principled BSDF that reads colour from the vertex colour attribute."""
    mat   = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out  = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rng.uniform(0.85, 0.97)
    bsdf.inputs["Metallic"].default_value  = rng.uniform(0.0, 0.05)
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    vcol = nodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "Col"
    links.new(vcol.outputs["Color"], bsdf.inputs["Base Color"])

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

    _paint_vertex_colors(obj, rng)
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

    _paint_vertex_colors(obj, rng)
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
