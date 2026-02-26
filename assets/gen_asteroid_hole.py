"""
Blender 5.x headless script — generates a procedural bug-hole mesh and exports
it to assets/asteroid_hole.glb for use in Godot.

Orientation convention (must match Godot hole marker):
  +Y  = outward surface normal (hole mouth faces +Y)
  -Y  = inward (tunnel goes toward -Y)

Run via:
  blender --background --python assets/gen_asteroid_hole.py
"""

import bpy
import bmesh
import math
import random

random.seed(7)

# ── Clean scene ──────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

SEGS        = 24
OUTER_R     = 0.46   # outer radius of rocky rim base
INNER_R     = 0.26   # tunnel opening radius
RIM_LIFT    = 0.11   # max height rim rises above the surface
TUNNEL_DEPTH = 0.55  # how far the tunnel goes in (-Y)


def make_ring(bm: bmesh.types.BMesh, r: float, z: float, n: int,
              r_jitter: float = 0.0, z_jitter: float = 0.0):
    """Return a list of n bmesh vertices in a ring on the XY plane at height z.
    Blender +Z → GLTF +Y → Godot +Y (outward surface normal on the hole marker).
    """
    verts = []
    for i in range(n):
        a = (i / n) * math.tau
        rj = r + random.uniform(-r_jitter, r_jitter)
        zj = z + random.uniform(-z_jitter, z_jitter)
        verts.append(bm.verts.new((math.cos(a) * rj, math.sin(a) * rj, zj)))
    return verts


def bridge_rings(bm: bmesh.types.BMesh, r0: list, r1: list, flip: bool = False) -> None:
    """Fill quad faces between two equal-length vertex rings."""
    n = len(r0)
    for i in range(n):
        j = (i + 1) % n
        quad = [r0[i], r0[j], r1[j], r1[i]]
        if flip:
            quad.reverse()
        bm.faces.new(quad)


me = bpy.data.meshes.new("AsteroidHole")
bm = bmesh.new()

# ── Build vertex rings (Y = outward/up in Godot) ─────────────────────────────

# Outer base — lies flat at the asteroid surface (Y = 0)
v_base_out  = make_ring(bm, OUTER_R,                   0.0,           SEGS, r_jitter=0.05)
# Rocky rim peak — raised and rough
v_rim_peak  = make_ring(bm, (OUTER_R + INNER_R) * 0.55, RIM_LIFT,      SEGS, r_jitter=0.05, z_jitter=0.03)
# Inner rim edge — where rocky collar meets tunnel mouth
v_rim_inner = make_ring(bm, INNER_R * 1.12,             RIM_LIFT * 0.4, SEGS, r_jitter=0.02, z_jitter=0.01)
# Tunnel mouth — flush with surface
v_tun_top   = make_ring(bm, INNER_R,                   0.0,           SEGS)
# Tunnel mid-point
v_tun_mid   = make_ring(bm, INNER_R * 0.88,            -TUNNEL_DEPTH * 0.5, SEGS)
# Tunnel bottom
v_tun_bot   = make_ring(bm, INNER_R * 0.55,            -TUNNEL_DEPTH,  SEGS)

bm.verts.ensure_lookup_table()

# ── Rocky rim faces (outward-facing normals) ──────────────────────────────────
bridge_rings(bm, v_base_out, v_rim_peak)
bridge_rings(bm, v_rim_peak, v_rim_inner)
bridge_rings(bm, v_rim_inner, v_tun_top)

# ── Tunnel interior faces (inward-facing — flip winding) ─────────────────────
bridge_rings(bm, v_tun_top, v_tun_mid, flip=True)
bridge_rings(bm, v_tun_mid, v_tun_bot, flip=True)

# ── Cap the tunnel bottom ─────────────────────────────────────────────────────
center_bot = bm.verts.new((0.0, 0.0, -TUNNEL_DEPTH))
for i in range(SEGS):
    j = (i + 1) % SEGS
    bm.faces.new([v_tun_bot[j], v_tun_bot[i], center_bot])

bm.to_mesh(me)
bm.free()
me.update()

obj = bpy.data.objects.new("AsteroidHole", me)
bpy.context.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)

bpy.ops.object.shade_smooth()

# ── Small surface-noise displacement on the rocky rim ────────────────────────
rim_noise = bpy.data.textures.new("RimNoise", type="CLOUDS")
rim_noise.noise_scale = 0.28
rim_noise.noise_depth = 5

disp = obj.modifiers.new("Displace", type="DISPLACE")
disp.texture = rim_noise
disp.strength = 0.045
disp.mid_level = 0.5
bpy.ops.object.modifier_apply(modifier="Displace")

# ── Materials ─────────────────────────────────────────────────────────────────

# Slot 0 — rocky exterior (rim + outer slope)
mat_rock = bpy.data.materials.new("HoleRock")
mat_rock.use_nodes = True
bsdf = mat_rock.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.10, 0.08, 0.06, 1.0)
bsdf.inputs["Roughness"].default_value  = 0.97
bsdf.inputs["Metallic"].default_value   = 0.0

# Slot 1 — dark tunnel interior with warm bioluminescent emission
mat_inner = bpy.data.materials.new("HoleInner")
mat_inner.use_nodes = True
tree  = mat_inner.node_tree
bsdf2 = tree.nodes.get("Principled BSDF")
bsdf2.inputs["Base Color"].default_value = (0.025, 0.010, 0.008, 1.0)
bsdf2.inputs["Roughness"].default_value  = 1.0

em  = tree.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value    = (0.9, 0.32, 0.04, 1.0)
em.inputs["Strength"].default_value = 0.9

mix = tree.nodes.new("ShaderNodeMixShader")
mix.inputs["Fac"].default_value = 0.28

out = tree.nodes.get("Material Output")
tree.links.new(bsdf2.outputs["BSDF"],      mix.inputs[1])
tree.links.new(em.outputs["Emission"],     mix.inputs[2])
tree.links.new(mix.outputs["Shader"],      out.inputs["Surface"])

obj.data.materials.append(mat_rock)   # index 0
obj.data.materials.append(mat_inner)  # index 1

# ── Assign materials by face position: tunnel faces (Y < -0.05) get inner mat ─
mesh = obj.data
for poly in mesh.polygons:
    avg_z = sum(mesh.vertices[v].co.z for v in poly.vertices) / len(poly.vertices)
    poly.material_index = 1 if avg_z < -0.05 else 0

# ── Export ────────────────────────────────────────────────────────────────────
import os
out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asteroid_hole.glb")

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=False,
    export_apply=False,
    export_materials="EXPORT",
    export_normals=True,
    export_yup=True,
)

print(f"[gen_asteroid_hole] Exported → {out_path}")
