"""
Blender headless script — generates an industrial mining mothership GLB (v2).

Design language: heavy, modular, utilitarian — bolted-together sections.

Sections (bow = −Y, stern = +Y, up = +Z):
  • Mining prow  : heavy reinforced block with cutter bars and drill ribs
  • Command module: boxy bridge, offset to port for asymmetry, viewport strip
  • Structural spine (I-beam): top flange + web + bottom flange along dorsal
  • Side hull plates: thick armour panels hanging off the spine web
  • Cargo bay skeleton: open frame of cross-beams and corner pillars (mid-ship)
  • Ore processing tanks: two offset cylinders on upper hull
  • Engine section: two large rectangular pods with heat-sink fins
  • Fuel tanks: large cylinders flanking the engine pods
  • Engine nozzles: 4 square-ish exhaust ports at the very stern

5 turret mount pads along the spine top, matching Godot TurretMount1-5.

Coordinate mapping (GLB import, Blender → Godot):
  Blender (x, y, z)  →  Godot (x, z, −y)

Run:
  blender --background --python assets/gen_mothership.py
Output:
  assets/mothership/mothership.glb
"""

import bpy
import math
import os

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mothership")
os.makedirs(OUT_DIR, exist_ok=True)

HALF_PI = math.pi / 2.0

# Turret pads: Blender Y positions → Godot Z = 3, 1.5, 0, −1.5, −3
TURRET_Y  = [-3.0, -1.5,  0.0,  1.5,  3.0]
TURRET_Z  = 1.38   # top of spine in Blender Z


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


def _box(name: str, loc: tuple, w: float, l: float, h: float,
         mat: bpy.types.Material = None) -> bpy.types.Object:
    """Box centred at loc, dimensions w(X) × l(Y) × h(Z)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (w, l, h)
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def _cyl(name: str, loc: tuple, r: float, d: float,
         rot: tuple = (0.0, 0.0, 0.0),
         mat: bpy.types.Material = None,
         verts: int = 10) -> bpy.types.Object:
    """Cylinder. Default axis = Y after 90 ° X-rotation applied here."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=d, location=loc, rotation=rot, vertices=verts)
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    if mat:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def _add_empty(name: str, loc: tuple) -> bpy.types.Object:
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    e = bpy.context.active_object
    e.name = name
    e.empty_display_size = 0.3
    return e


# ── Materials ─────────────────────────────────────────────────────────────────

def _mat(name: str, base, rough: float, metal: float,
         emit=None, emit_str: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    nodes.clear()
    out  = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value  = rough
    bsdf.inputs["Metallic"].default_value   = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value    = emit
        bsdf.inputs["Emission Strength"].default_value = emit_str
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


# ── Entry point ───────────────────────────────────────────────────────────────

bpy.ops.wm.read_factory_settings(use_empty=True)
_cleanup()

hull    = _mat("Hull",   (0.13, 0.13, 0.14, 1), rough=0.58, metal=0.72)
struct  = _mat("Struct", (0.22, 0.20, 0.18, 1), rough=0.62, metal=0.60)
accent  = _mat("Accent", (0.72, 0.48, 0.02, 1), rough=0.38, metal=0.72)
engine  = _mat("Engine", (0.16, 0.07, 0.03, 1), rough=0.55, metal=0.30,
               emit=(1.0, 0.38, 0.08, 1), emit_str=9.0)
window  = _mat("Window", (0.06, 0.22, 0.55, 1), rough=0.08, metal=0.00,
               emit=(0.12, 0.40, 1.00, 1), emit_str=2.5)
tank    = _mat("Tank",   (0.20, 0.19, 0.17, 1), rough=0.52, metal=0.58)

parts = []

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. STRUCTURAL SPINE — I-beam running the full dorsal length
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
parts += [
    _box("Spine_top_flange", (0,  0.0, 1.28), 0.82, 10.0, 0.24, struct),
    _box("Spine_web",        (0,  0.0, 0.48), 0.26, 10.0, 1.56, struct),
    _box("Spine_bot_flange", (0,  0.0,-0.18), 0.72, 10.0, 0.22, struct),
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. MINING PROW — heavy reinforced block at the bow
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
parts += [
    _box("Prow_block",    (0, -5.2, 0.10), 3.50, 2.80, 2.10, hull),
    _box("Prow_upper",    (0, -4.0, 1.15), 2.60, 1.20, 0.80, hull),  # stepped transition
    # Horizontal reinforcement bars on the front face
    _box("Prow_bar_mid",  (0, -6.55, 0.50), 3.70, 0.32, 0.32, accent),
    _box("Prow_bar_top",  (0, -6.55, 1.10), 3.70, 0.32, 0.22, accent),
    # Vertical structural ribs on prow face
    _box("Prow_rib_c",   ( 0.0, -6.55, 0.35), 0.24, 0.32, 1.10, struct),
    _box("Prow_rib_l",   (-1.35, -6.55, 0.35), 0.24, 0.32, 1.10, struct),
    _box("Prow_rib_r",   ( 1.35, -6.55, 0.35), 0.24, 0.32, 1.10, struct),
    # Mining cutters — thick accent blocks at bow corners
    _box("Cutter_l",    (-1.15, -6.80, 0.60), 0.55, 0.26, 0.50, accent),
    _box("Cutter_r",    ( 1.15, -6.80, 0.60), 0.55, 0.26, 0.50, accent),
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. COMMAND MODULE — offset to port (asymmetric, industrial feel)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
parts += [
    _box("Bridge_body",   (-0.45, -3.0, 1.60), 1.90, 3.00, 1.40, hull),
    _box("Bridge_roof",   (-0.45, -3.0, 2.33), 1.70, 2.70, 0.32, hull),
    # Viewport strip across front
    _box("Bridge_window", (-0.45, -4.48, 1.92), 1.50, 0.10, 0.58, window),
    # Side window (port)
    _box("Bridge_win_p",  (-1.36, -3.0,  1.92), 0.10, 1.80, 0.44, window),
    # Antenna mast + dish
    _box("Mast",          (-0.45, -3.60, 2.55), 0.06, 0.06, 0.58, struct),
    _box("AntDish",       (-0.45, -3.60, 2.88), 0.44, 0.44, 0.08, struct),
    # Roof detail box (sensor cluster)
    _box("SensorBox",     ( 0.55, -2.80, 2.42), 0.42, 0.60, 0.22, struct),
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. SIDE HULL ARMOUR PLATES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for sx in (-1.0, 1.0):
    s = -1 if sx < 0 else 1
    parts += [
        _box("Side_plate",  (sx * 1.68, -1.0, 0.08), 0.32, 7.80, 2.00, hull),
        _box("Side_skirt",  (sx * 1.58, -1.0,-0.82), 0.40, 7.20, 0.58, hull),
        # Yellow safety stripe along lower edge of plate
        _box("AccentLine",  (sx * 1.86, -1.5, 0.22), 0.05, 5.20, 0.14, accent),
        # Bolted panel dividers (short vertical bars)
        _box("PanelDiv",    (sx * 1.86, -3.0, 0.22), 0.05, 0.18, 0.80, struct),
        _box("PanelDiv2",   (sx * 1.86,  0.5, 0.22), 0.05, 0.18, 0.80, struct),
        _box("PanelDiv3",   (sx * 1.86,  2.5, 0.22), 0.05, 0.18, 0.80, struct),
    ]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. LOWER KEEL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
parts.append(_box("Keel", (0, -0.5, -1.02), 2.90, 9.00, 0.52, hull))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. CARGO BAY SKELETON — open structural frame (mid-ship)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for y in (-0.3, 1.1, 2.5):
    parts += [
        _box("CargoFrame_top", (0, y, 0.72), 3.50, 0.24, 0.20, struct),
        _box("CargoFrame_bot", (0, y,-0.58), 3.50, 0.24, 0.18, struct),
    ]
# Vertical corner pillars
for sx in (-1.52, 1.52):
    for y in (-0.3, 1.1, 2.5):
        parts.append(_box("CargoPillar", (sx, y, 0.06), 0.24, 0.24, 2.30, struct))
# Cargo bay floor plate
parts.append(_box("CargoFloor", (0, 1.1, -0.90), 3.10, 3.80, 0.20, hull))
# Diagonal bracing (X-brace look)
for sx in (-1.0, 1.0):
    parts.append(_box("XBrace", (sx * 0.75, 0.9, 0.10), 0.10, 0.18, 2.20, struct))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. ORE PROCESSING TANKS — pair of offset cylinders on upper hull
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for sx, cy in ((-0.85, -0.2), (0.85, 0.8)):
    parts.append(_cyl("OreTank", (sx, cy, 1.55), r=0.34, d=2.80,
                       rot=(HALF_PI, 0, 0), mat=tank, verts=12))
    for dy in (-1.40, 1.40):
        parts.append(_cyl("TankCap", (sx, cy + dy, 1.55), r=0.38, d=0.10,
                           rot=(HALF_PI, 0, 0), mat=accent, verts=12))
    # Mounting bracket
    parts.append(_box("TankMount", (sx, cy, 1.22), 0.38, 2.60, 0.12, struct))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. ENGINE PODS — two large rectangular blocks at stern
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for sx in (-1.18, 1.18):
    s = -1 if sx < 0 else 1
    parts += [
        _box("EngPod",    (sx, 4.00, 0.08), 0.95, 3.20, 1.45, hull),
        # Heat-sink fins on outer face
        _box("HeatFin_1", (sx + s * 0.56, 3.20, 0.55), 0.06, 0.60, 0.72, struct),
        _box("HeatFin_2", (sx + s * 0.56, 4.00, 0.55), 0.06, 0.60, 0.72, struct),
        _box("HeatFin_3", (sx + s * 0.56, 4.80, 0.55), 0.06, 0.60, 0.72, struct),
        # Accent stripe on engine face
        _box("EngAccent", (sx, 5.55, 0.08), 0.85, 0.10, 1.30, accent),
    ]
# Cross-brace connecting the two pods
parts += [
    _box("EngBrace_top", (0, 3.80, 0.84), 2.46, 0.36, 0.22, struct),
    _box("EngBrace_bot", (0, 3.80,-0.55), 2.46, 0.36, 0.22, struct),
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. FUEL TANKS — large cylinders flanking engine pods
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for sx in (-1.95, 1.95):
    parts.append(_cyl("FuelTank", (sx, 3.80, 0.08), r=0.44, d=2.60,
                       rot=(HALF_PI, 0, 0), mat=tank, verts=12))
    for dy in (-1.30, 1.30):
        parts.append(_cyl("FuelCap", (sx, 3.80 + dy, 0.08), r=0.48, d=0.10,
                           rot=(HALF_PI, 0, 0), mat=accent, verts=12))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. ENGINE NOZZLES — 4 boxy exhaust ports (square-ish, industrial)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for sx in (-1.18, 1.18):
    for sz in (-0.28, 0.28):
        # Outer shroud
        parts.append(_cyl("NozzleShroud", (sx, 5.85, sz + 0.08), r=0.22, d=0.45,
                           rot=(HALF_PI, 0, 0), mat=hull, verts=8))
        # Glowing inner
        parts.append(_cyl("NozzleGlow",   (sx, 5.95, sz + 0.08), r=0.14, d=0.12,
                           rot=(HALF_PI, 0, 0), mat=engine, verts=8))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. TURRET MOUNT PADS along the spine top
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for i, ty in enumerate(TURRET_Y):
    parts.append(_cyl(f"TurretPad_{i+1}", (0, ty, TURRET_Z),
                       r=0.30, d=0.18, rot=(0, 0, 0), mat=accent, verts=8))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# JOIN + SHADE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
mothership = _join(parts)
mothership.name = "MiningMothership"
_set_active(mothership)
bpy.ops.object.shade_smooth()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# NAMED EMPTIES (hardpoint anchors → Node3D in Godot)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for i, ty in enumerate(TURRET_Y):
    _add_empty(f"TurretMount{i+1}", (0, ty, TURRET_Z + 0.12))

_add_empty("CargoBay", (0, 5.5, 0.30))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# EXPORT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
