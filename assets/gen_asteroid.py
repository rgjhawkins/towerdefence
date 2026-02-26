"""
Blender 5.x headless script — generates a procedural asteroid mesh and exports
it to assets/asteroid.glb for use in Godot.

Run via:
  blender --background --python assets/gen_asteroid.py
"""

import bpy
import bmesh
import math
import random

random.seed(42)

# ── Clean scene ──────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

# ── Base icosphere ────────────────────────────────────────────────────────────
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0, location=(0, 0, 0))
obj = bpy.context.active_object
obj.name = "Asteroid"

# ── Displace with Clouds texture (main large-scale bumps) ────────────────────
clouds_tex = bpy.data.textures.new("AsteroidClouds", type="CLOUDS")
clouds_tex.noise_scale = 1.6
clouds_tex.noise_depth = 4

disp_mod = obj.modifiers.new("Displace", type="DISPLACE")
disp_mod.texture = clouds_tex
disp_mod.strength = 0.55
disp_mod.mid_level = 0.5

# ── Second Displace for fine surface detail (craters / pitting) ──────────────
detail_tex = bpy.data.textures.new("AsteroidDetail", type="CLOUDS")
detail_tex.noise_scale = 0.4
detail_tex.noise_depth = 6

disp_mod2 = obj.modifiers.new("DisplaceDetail", type="DISPLACE")
disp_mod2.texture = detail_tex
disp_mod2.strength = 0.18
disp_mod2.mid_level = 0.5
disp_mod2.texture_coords = "LOCAL"

# ── Non-uniform scale for irregular asteroid shape ────────────────────────────
obj.scale = (
    random.uniform(0.85, 1.15),
    random.uniform(0.75, 1.05),
    random.uniform(0.80, 1.10),
)
bpy.ops.object.transform_apply(scale=True)

# ── Apply all modifiers so the mesh is baked ─────────────────────────────────
bpy.context.view_layer.objects.active = obj
for mod in obj.modifiers:
    bpy.ops.object.modifier_apply(modifier=mod.name)

# ── Shade smooth so it looks good in Godot ───────────────────────────────────
bpy.ops.object.shade_smooth()

# ── Basic grey rocky material ─────────────────────────────────────────────────
mat = bpy.data.materials.new("AsteroidRock")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (0.18, 0.16, 0.14, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.05
obj.data.materials.append(mat)

# ── Export as GLB ─────────────────────────────────────────────────────────────
import os
out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asteroid.glb")

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=False,
    export_apply=False,
    export_materials="EXPORT",
    export_normals=True,
    export_yup=True,         # Godot uses Y-up for imported GLTF
)

print(f"[gen_asteroid] Exported → {out_path}")
