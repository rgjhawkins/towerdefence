"""
Blender 5.x headless script — generates an animated squid alien GLB.

Mesh:
  - Mantle (elongated ICO sphere, tapered at base)
  - 8 tentacles (4 long, 4 short, alternating), tapered cylinders
  - Toxic green bioluminescent material, no eyes

Rig:
  - root bone (stub at origin)
  - body bone (covers mantle)
  - 8 × 3 tentacle bone chains

Animations (pushed to NLA for multi-clip GLB export):
  - "idle"  : 60 frames, gentle tentacle ripple
  - "swim"  : 30 frames, propulsion pulse (body squash + tentacle flare)

Output: assets/squid_aliens/squid_alien.glb

Run via:
  blender --background --python assets/gen_squid_alien.py
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "squid_aliens")
os.makedirs(OUT_DIR, exist_ok=True)

NUM_TENTACLES    = 8
SEG_PER_TENTACLE = 3
ATTACH_Z         = -0.9   # Z level where tentacles meet the mantle base


# ── Helpers ───────────────────────────────────────────────────────────────────

def _cleanup() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for blk in list(bpy.data.meshes):    bpy.data.meshes.remove(blk)
    for blk in list(bpy.data.materials): bpy.data.materials.remove(blk)
    for blk in list(bpy.data.armatures): bpy.data.armatures.remove(blk)
    for blk in list(bpy.data.actions):   bpy.data.actions.remove(blk)


def _deselect_all() -> None:
    bpy.ops.object.select_all(action="DESELECT")


def _set_active(obj: bpy.types.Object) -> None:
    _deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# ── Mesh builders ─────────────────────────────────────────────────────────────

def _make_mantle() -> bpy.types.Object:
    """Elongated, base-tapered ICO sphere for the squid mantle."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = "Mantle"

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for v in bm.verts:
        z = v.co.z  # -1..+1 on the unit sphere
        # Taper the bottom (base) in XY and elongate along Z
        if z < 0:
            r = 1.0 + z * 0.55   # narrows toward base
        else:
            r = 1.0 - z * 0.20   # slight taper at crown
        v.co.x *= r * 0.85
        v.co.y *= r * 0.75       # slightly flatter front-to-back
        v.co.z *= 1.3
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj



def _make_tentacle(index: int) -> bpy.types.Object:
    """Tapered tentacle mesh, 4 segments, curving outward and downward."""
    angle    = (index / NUM_TENTACLES) * math.tau
    long_arm = (index % 2 == 0)
    length   = 1.8 if long_arm else 1.2
    segments = 4
    ring_n   = 6
    base_r   = 0.09 if long_arm else 0.07
    spread0  = 0.40   # XY spread at attachment

    bm = bmesh.new()
    rings = []
    for s in range(segments + 1):
        t      = s / segments
        radius = base_r * (1.0 - t * 0.88)
        spread = spread0 + t * 0.30
        cx     = math.cos(angle) * spread
        cy     = math.sin(angle) * spread
        cz     = ATTACH_Z - t * length
        ring   = [bm.verts.new(Vector((cx + math.cos(rv / ring_n * math.tau) * radius,
                                       cy + math.sin(rv / ring_n * math.tau) * radius,
                                       cz)))
                  for rv in range(ring_n)]
        rings.append(ring)

    for s in range(segments):
        for rv in range(ring_n):
            rv2 = (rv + 1) % ring_n
            bm.faces.new([rings[s][rv], rings[s][rv2],
                          rings[s + 1][rv2], rings[s + 1][rv]])

    # Tip cap
    tip_spread = spread0 + 0.30
    tip_c = bm.verts.new(Vector((math.cos(angle) * tip_spread,
                                 math.sin(angle) * tip_spread,
                                 ATTACH_Z - length)))
    for rv in range(ring_n):
        bm.faces.new([rings[-1][rv], rings[-1][(rv + 1) % ring_n], tip_c])

    mesh = bpy.data.meshes.new(f"Tentacle_{index:02d}")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _join(objects: list) -> bpy.types.Object:
    _deselect_all()
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return bpy.context.active_object


# ── Materials ─────────────────────────────────────────────────────────────────

def _principled(name: str, base, roughness: float, metallic: float,
                emit=None, emit_strength: float = 0.0) -> bpy.types.Material:
    mat   = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out  = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value  = roughness
    bsdf.inputs["Metallic"].default_value   = metallic
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value    = emit
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


# ── Armature ──────────────────────────────────────────────────────────────────

def _build_armature() -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("SquidRig")
    arm_obj  = bpy.data.objects.new("SquidRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    _set_active(arm_obj)
    bpy.ops.object.mode_set(mode="EDIT")

    eb = arm_data.edit_bones

    # Root stub at base
    root      = eb.new("root")
    root.head = Vector((0.0, 0.0, ATTACH_Z))
    root.tail = Vector((0.0, 0.0, ATTACH_Z + 0.15))

    # Body — covers full mantle height
    body        = eb.new("body")
    body.head   = Vector((0.0, 0.0, ATTACH_Z))
    body.tail   = Vector((0.0, 0.0, 1.4))
    body.parent = root

    # Tentacle chains — 3 bones each
    for i in range(NUM_TENTACLES):
        angle  = (i / NUM_TENTACLES) * math.tau
        long   = (i % 2 == 0)
        length = 1.8 if long else 1.2
        spread0 = 0.40
        prev   = body
        for seg in range(SEG_PER_TENTACLE):
            t0 = seg / SEG_PER_TENTACLE
            t1 = (seg + 1) / SEG_PER_TENTACLE
            s0 = spread0 + t0 * 0.30
            s1 = spread0 + t1 * 0.30
            b        = eb.new(f"tentacle_{i:02d}_{seg}")
            b.head   = Vector((math.cos(angle) * s0, math.sin(angle) * s0,
                               ATTACH_Z - t0 * length))
            b.tail   = Vector((math.cos(angle) * s1, math.sin(angle) * s1,
                               ATTACH_Z - t1 * length))
            b.parent = prev
            b.use_connect = (seg > 0)
            prev = b

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


# ── Animation ─────────────────────────────────────────────────────────────────

def _kf_rot(pb: bpy.types.PoseBone, rx: float, ry: float, rz: float, frame: int) -> None:
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((rx, ry, rz))
    pb.keyframe_insert("rotation_euler", frame=frame)


def _build_idle(arm_obj: bpy.types.Object) -> bpy.types.Action:
    """60-frame loop: gentle ripple along each tentacle chain."""
    action = bpy.data.actions.new("idle")
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = action

    _set_active(arm_obj)
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm_obj.pose.bones

    FRAMES = 60
    for f in range(FRAMES + 1):
        t = f / FRAMES * math.tau  # 0 → 2π
        for i in range(NUM_TENTACLES):
            phase = (i / NUM_TENTACLES) * math.tau
            for seg in range(SEG_PER_TENTACLE):
                b = pb.get(f"tentacle_{i:02d}_{seg}")
                if not b:
                    continue
                # Each segment lags behind the previous (wave propagation)
                wave = math.sin(t + phase + seg * 0.7) * 0.10
                _kf_rot(b, wave, 0.0, wave * 0.5, f)

    bpy.ops.object.mode_set(mode="OBJECT")
    action.use_cyclic = True
    return action


def _build_swim(arm_obj: bpy.types.Object) -> bpy.types.Action:
    """30-frame loop: tentacles flare outward then snap in (jet propulsion)."""
    action = bpy.data.actions.new("swim")
    arm_obj.animation_data.action = action

    _set_active(arm_obj)
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm_obj.pose.bones

    FRAMES = 30
    for f in range(FRAMES + 1):
        t = f / FRAMES * math.tau  # 0 → 2π

        # Body: slight squash on the stroke, stretch on the recovery
        body_pb = pb.get("body")
        if body_pb:
            sc = 1.0 + math.sin(t) * 0.08
            body_pb.scale = Vector((1.0 / sc, 1.0 / sc, sc))
            body_pb.keyframe_insert("scale", frame=f)

        # Tentacles: flare out then snap back
        for i in range(NUM_TENTACLES):
            for seg in range(SEG_PER_TENTACLE):
                b = pb.get(f"tentacle_{i:02d}_{seg}")
                if not b:
                    continue
                flare = math.sin(t) * 0.22 * (seg + 1) * 0.5
                _kf_rot(b, flare, 0.0, 0.0, f)

    bpy.ops.object.mode_set(mode="OBJECT")
    action.use_cyclic = True
    return action


def _push_nla(arm_obj: bpy.types.Object, action: bpy.types.Action, start: int) -> None:
    """Push action to a named NLA track so it exports as a named animation clip."""
    arm_obj.animation_data_create()
    track       = arm_obj.animation_data.nla_tracks.new()
    track.name  = action.name
    strip       = track.strips.new(action.name, start, action)
    strip.action = action


# ── Export ────────────────────────────────────────────────────────────────────

def _export(out_path: str) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_materials="EXPORT",
        export_normals=True,
        export_yup=True,
        export_animations=True,
        export_nla_strips=True,
    )


# ── Entry point ───────────────────────────────────────────────────────────────

bpy.ops.wm.read_factory_settings(use_empty=True)
_cleanup()

# ── Build mesh ────────────────────────────────────────────────────────────────
mantle    = _make_mantle()
tentacles = [_make_tentacle(i) for i in range(NUM_TENTACLES)]

# Assign material (before join)
body_mat = _principled("SquidBody",
                        base=(0.04, 0.22, 0.06, 1.0),
                        roughness=0.45, metallic=0.10,
                        emit=(0.08, 0.55, 0.10, 1.0), emit_strength=1.2)

mantle.data.materials.append(body_mat)
for t in tentacles:
    t.data.materials.append(body_mat)

# Join into one mesh object
squid = _join([mantle] + tentacles)
squid.name = "SquidAlien"

_set_active(squid)
bpy.ops.object.shade_smooth()

# ── Rig ───────────────────────────────────────────────────────────────────────
arm_obj = _build_armature()

# Parent mesh to armature; Blender computes vertex weights automatically
_deselect_all()
squid.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# ── Animate ───────────────────────────────────────────────────────────────────
idle = _build_idle(arm_obj)
swim = _build_swim(arm_obj)

# Push both onto separate NLA tracks so GLB export sees two named clips
_push_nla(arm_obj, idle, start=1)
_push_nla(arm_obj, swim, start=100)
arm_obj.animation_data.action = None   # let NLA drive export

# ── Export ────────────────────────────────────────────────────────────────────
out_path = os.path.join(OUT_DIR, "squid_alien.glb")
_export(out_path)
print(f"[gen_squid_alien] Exported → {out_path}")
