"""
Blender 5.x headless script — generates 30 procedural asteroid meshes and
exports them to assets/asteroids/asteroid_00.glb … asteroid_29.glb.

Run via:
  blender --background --python assets/gen_asteroid.py
"""

import bpy
import bmesh
import math
import os
import random
from mathutils import Vector


OUT_DIR   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asteroids")
NUM_VARIANTS = 30


def _random_sphere_dir(rng: random.Random) -> Vector:
    theta = rng.uniform(0.0, math.tau)
    phi   = math.acos(rng.uniform(-1.0, 1.0))
    return Vector((math.sin(phi) * math.cos(theta),
                   math.sin(phi) * math.sin(theta),
                   math.cos(phi)))


def _crater_profile(t: float) -> float:
    """Signed displacement at normalised distance t (0=centre, 1=edge)."""
    if t >= 1.0:
        return 0.0
    depression = -(1.0 - t ** 1.4) ** 0.6
    rim        =  0.35 * math.sin(t * math.pi) ** 2
    return depression + rim


def generate(index: int) -> None:
    rng = random.Random(index * 137 + 42)

    # ── Varied parameters ─────────────────────────────────────────────────────
    noise_scale      = rng.uniform(1.2, 2.2)
    disp_strength    = rng.uniform(0.38, 0.65)
    detail_scale     = rng.uniform(0.28, 0.55)
    detail_strength  = rng.uniform(0.10, 0.24)
    scale_xyz        = (rng.uniform(0.78, 1.22),
                        rng.uniform(0.68, 1.08),
                        rng.uniform(0.74, 1.14))
    num_craters      = rng.randint(8, 16)
    crater_depth_min = rng.uniform(0.20, 0.32)
    crater_depth_max = rng.uniform(0.35, 0.55)
    crater_rad_min   = rng.uniform(0.18, 0.28)
    crater_rad_max   = rng.uniform(0.32, 0.58)

    # ── Base icosphere ────────────────────────────────────────────────────────
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = f"Asteroid_{index:02d}"

    # ── Large-scale displacement ──────────────────────────────────────────────
    tex1 = bpy.data.textures.new(f"Clouds_{index}", type="CLOUDS")
    tex1.noise_scale = noise_scale
    tex1.noise_depth = 4
    mod1 = obj.modifiers.new("Displace", type="DISPLACE")
    mod1.texture    = tex1
    mod1.strength   = disp_strength
    mod1.mid_level  = 0.5

    # ── Fine surface detail ───────────────────────────────────────────────────
    tex2 = bpy.data.textures.new(f"Detail_{index}", type="CLOUDS")
    tex2.noise_scale = detail_scale
    tex2.noise_depth = 6
    mod2 = obj.modifiers.new("DisplaceDetail", type="DISPLACE")
    mod2.texture        = tex2
    mod2.strength       = detail_strength
    mod2.mid_level      = 0.5
    mod2.texture_coords = "LOCAL"

    # ── Non-uniform scale ─────────────────────────────────────────────────────
    obj.scale = scale_xyz
    bpy.ops.object.transform_apply(scale=True)

    # ── Apply modifiers ───────────────────────────────────────────────────────
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        bpy.ops.object.modifier_apply(modifier=mod.name)

    # ── Carve craters ─────────────────────────────────────────────────────────
    craters = [
        {
            "dir":            _random_sphere_dir(rng),
            "angular_radius": rng.uniform(crater_rad_min, crater_rad_max),
            "depth":          rng.uniform(crater_depth_min, crater_depth_max),
        }
        for _ in range(num_craters)
    ]

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()

    for vert in bm.verts:
        vert_dir = vert.co.normalized()
        for c in craters:
            dot   = max(-1.0, min(1.0, vert_dir.dot(c["dir"])))
            angle = math.acos(dot)
            if angle < c["angular_radius"]:
                t = angle / c["angular_radius"]
                vert.co += vert_dir * _crater_profile(t) * c["depth"]

    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    # ── Shade smooth ──────────────────────────────────────────────────────────
    bpy.ops.object.shade_smooth()

    # ── Material ──────────────────────────────────────────────────────────────
    mat  = bpy.data.materials.new(f"AsteroidRock_{index:02d}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        # Slight colour variation: some asteroids more reddish, some grey/blue
        r = rng.uniform(0.14, 0.22)
        g = rng.uniform(0.12, 0.18)
        b = rng.uniform(0.10, 0.18)
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value  = rng.uniform(0.88, 0.97)
        bsdf.inputs["Metallic"].default_value   = rng.uniform(0.0, 0.08)
    obj.data.materials.append(mat)

    # ── Export ────────────────────────────────────────────────────────────────
    out_path = os.path.join(OUT_DIR, f"asteroid_{index:02d}.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_materials="EXPORT",
        export_normals=True,
        export_yup=True,
    )
    print(f"[gen_asteroid] {index+1:2d}/{NUM_VARIANTS}  →  {out_path}")

    # ── Clean up for next iteration ───────────────────────────────────────────
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for tex in list(bpy.data.textures):
        bpy.data.textures.remove(tex)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


# ── Entry point ───────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

for i in range(NUM_VARIANTS):
    generate(i)

print(f"[gen_asteroid] Done — {NUM_VARIANTS} asteroids exported to {OUT_DIR}")
