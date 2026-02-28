"""
Blender headless script — generates a mining mothership GLB.

Hull layout (Blender coords: Y = forward/stern, Z = up):
  • Main hull: elongated box, 8 units long along Y, 3 wide, 1.4 tall
  • Tapered prow at bow (−Y direction)
  • Bridge tower near bow on dorsal surface
  • Dorsal spine ridge running full length
  • 5 turret mount pads along dorsal spine
  • Twin engine nacelles at stern (+Y)
  • Landing deck at stern-top
  • Cargo bay frame at stern

Named Empty objects (become Node3D children in Godot after GLB import):
  TurretMount1 … TurretMount5  along dorsal spine (bow→stern)
  LandingPad                    at stern-top
  CargoBay                      at stern-centre

Godot coordinate mapping (GLB import converts Blender→Godot):
  Blender (x, y, z)  →  Godot (x, z, -y)

So the Blender turret positions (0, -3…+3, 1.05) become Godot (0, 1.05, 3…-3).

Run via:
  blender --background --python assets/gen_mothership.py

Output: assets/mothership/mothership.glb
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mothership")
os.makedirs(OUT_DIR, exist_ok=True)

# Hardpoint positions in Blender space (X, Y, Z)
# Bow = −Y, Stern = +Y, Up = +Z
TURRET_MOUNT_POSITIONS = [
    (0.0, -3.0, 1.05),  # TurretMount1 — nearest bow
    (0.0, -1.5, 1.05),  # TurretMount2
    (0.0,  0.0, 1.05),  # TurretMount3 — amidships
    (0.0,  1.5, 1.05),  # TurretMount4
    (0.0,  3.0, 1.05),  # TurretMount5 — nearest stern
]
LANDING_PAD_POS = (0.0,  3.5, 1.25)
CARGO_BAY_POS   = (0.0,  3.8,  0.4)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _cleanup() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for blk in list(bpy.data.meshes):    bpy.data.meshes.remove(blk)
    for blk in list(bpy.data.materials): bpy.data.materials.remove(blk)


def _deselect_all() -> None:
    bpy.ops.object.select_all(action="DESELECT")


def _set_active(obj: bpy.types.Object) -> None:
    _deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


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
    mat = bpy.data.materials.new(name)
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


# ── Mesh part builders ────────────────────────────────────────────────────────

def _box(name: str, loc: tuple, w: float, l: float, h: float,
         mat: bpy.types.Material = None) -> bpy.types.Object:
    """Axis-aligned box centred at loc with dimensions w(X) × l(Y) × h(Z)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (w, l, h)
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def _cylinder(name: str, loc: tuple, radius: float, depth: float,
              rot: tuple = (0.0, 0.0, 0.0),
              mat: bpy.types.Material = None) -> bpy.types.Object:
    """Cylinder with given rotation (Euler XYZ radians)."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=loc, rotation=rot, vertices=16)
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    if mat:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def _make_prow(mat: bpy.types.Material) -> bpy.types.Object:
    """Tapered frustum from hull nose (y=−4.0) to sharp bow tip (y=−5.0)."""
    bm = bmesh.new()
    # Back face — same cross-section as hull end
    bw, bh = 3.0, 1.4
    tw, th = 0.3, 0.3      # tip dimensions
    y_back, y_tip = -4.0, -5.0

    vb = [bm.verts.new(Vector(( bw / 2,  y_back, -bh / 2))),
          bm.verts.new(Vector((-bw / 2,  y_back, -bh / 2))),
          bm.verts.new(Vector((-bw / 2,  y_back,  bh / 2))),
          bm.verts.new(Vector(( bw / 2,  y_back,  bh / 2)))]
    vt = [bm.verts.new(Vector(( tw / 2,  y_tip, -th / 2))),
          bm.verts.new(Vector((-tw / 2,  y_tip, -th / 2))),
          bm.verts.new(Vector((-tw / 2,  y_tip,  th / 2))),
          bm.verts.new(Vector(( tw / 2,  y_tip,  th / 2)))]

    bm.faces.new([vb[3], vb[2], vb[1], vb[0]])          # back
    bm.faces.new([vt[0], vt[1], vt[2], vt[3]])          # front tip
    bm.faces.new([vb[0], vb[1], vt[1], vt[0]])          # bottom
    bm.faces.new([vb[2], vb[3], vt[3], vt[2]])          # top
    bm.faces.new([vb[1], vb[2], vt[2], vt[1]])          # port
    bm.faces.new([vb[3], vb[0], vt[0], vt[3]])          # starboard

    mesh = bpy.data.meshes.new("Prow")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Prow", mesh)
    bpy.context.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    return obj


# ── Entry point ───────────────────────────────────────────────────────────────

bpy.ops.wm.read_factory_settings(use_empty=True)
_cleanup()

# Materials
hull_mat   = _principled("Hull",
                          base=(0.12, 0.13, 0.15, 1.0), roughness=0.50, metallic=0.80)
accent_mat = _principled("Accent",
                          base=(0.75, 0.50, 0.02, 1.0), roughness=0.40, metallic=0.70)
engine_mat = _principled("Engine",
                          base=(0.20, 0.10, 0.05, 1.0), roughness=0.60, metallic=0.30,
                          emit=(1.0, 0.40, 0.10, 1.0), emit_strength=8.0)
pad_mat    = _principled("LandPad",
                          base=(0.50, 0.55, 0.18, 1.0), roughness=0.50, metallic=0.50,
                          emit=(0.50, 0.60, 0.10, 1.0), emit_strength=0.8)
window_mat = _principled("BridgeWindow",
                          base=(0.10, 0.30, 0.60, 1.0), roughness=0.10, metallic=0.00,
                          emit=(0.20, 0.50, 1.00, 1.0), emit_strength=2.0)

# ── Build ship parts ──────────────────────────────────────────────────────────
parts = []

# 1. Main hull body
parts.append(_box("Hull_main",   (0, 0, 0),           3.0,  8.0,  1.40, hull_mat))

# 2. Tapered prow
parts.append(_make_prow(hull_mat))

# 3. Bridge tower (near bow, elevated on dorsal surface)
parts.append(_box("Bridge",      (0, -1.5, 1.10),     1.20, 1.80, 0.80, hull_mat))

# 4. Bridge window strip (front face of bridge tower)
parts.append(_box("BridgeWin",   (0, -2.40, 1.32),    1.00, 0.08, 0.32, window_mat))

# 5. Dorsal spine ridge (runs full hull length, slightly narrower)
parts.append(_box("DorsalRidge", (0, 0, 0.84),        0.45, 8.00, 0.30, hull_mat))

# 6. Turret mount pads — 5 accent cylinders on dorsal ridge
for i, pos in enumerate(TURRET_MOUNT_POSITIONS):
    parts.append(_cylinder(f"TurretPad_{i+1}", pos,
                            radius=0.28, depth=0.16, rot=(0.0, 0.0, 0.0),
                            mat=accent_mat))

# 7. Engine nacelles — twin rectangular blocks at stern
for label, sx in (("L", -1.10), ("R", 1.10)):
    parts.append(_box(f"Nacelle_{label}", (sx, 4.25, 0.0),  0.75, 1.50, 0.85, hull_mat))

# 8. Engine nozzles — 4 cylinders (2 per nacelle), pointing aft along Y
HALF_PI = math.pi / 2
for sx in (-1.10, 1.10):
    for sz in (-0.17, 0.17):
        parts.append(_cylinder("Nozzle",
                                (sx, 5.00, sz),
                                radius=0.18, depth=0.40,
                                rot=(HALF_PI, 0.0, 0.0),
                                mat=engine_mat))

# 9. Landing deck — flat platform at stern-top
parts.append(_box("LandingDeck", (0, 3.50, 1.14),    2.20, 1.60, 0.12, accent_mat))

# 10. Landing pad glow rails (port and starboard)
for sx in (-0.90, 0.90):
    parts.append(_box("LandRail", (sx, 3.50, 1.24),  0.07, 1.60, 0.04, pad_mat))

# 11. Cargo bay frame — open recess at stern underside
parts.append(_box("CargoBayFloor", (0, 3.60, -0.56), 2.00, 1.40, 0.12, hull_mat))
for sx in (-0.90, 0.90):
    parts.append(_box("CargoBaySide", (sx, 3.60, -0.22), 0.12, 1.40, 0.70, hull_mat))

# 12. Side accent stripes along hull length
for sx in (-1.45, 1.45):
    parts.append(_box("SideStripe", (sx, 0, 0.20),   0.06, 6.00, 0.14, accent_mat))

# ── Join all parts into one mesh ──────────────────────────────────────────────
mothership = _join(parts)
mothership.name = "MiningMothership"
_set_active(mothership)
bpy.ops.object.shade_smooth()


# ── Named Empty objects (hardpoints & special nodes) ─────────────────────────

def _add_empty(name: str, loc: tuple) -> bpy.types.Object:
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    emp = bpy.context.active_object
    emp.name = name
    emp.empty_display_size = 0.30
    return emp


for i, pos in enumerate(TURRET_MOUNT_POSITIONS):
    _add_empty(f"TurretMount{i + 1}", pos)

_add_empty("LandingPad", LANDING_PAD_POS)
_add_empty("CargoBay",   CARGO_BAY_POS)


# ── Export ────────────────────────────────────────────────────────────────────

out_path = os.path.join(OUT_DIR, "mothership.glb")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=False,
    export_materials="EXPORT",
    export_normals=True,
    export_yup=True,
    export_animations=False,
)
print(f"[gen_mothership] Exported → {out_path}")
