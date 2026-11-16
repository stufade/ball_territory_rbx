# Ball renders for the UI (own render, CC0 by this project).
# blender -b --factory-startup -P tools/art/blender/balls.py -- --only FIRE,WATER --out assets/art/balls3d
# One camera, one light rig for every ball; emblem = white icon(e) from assets/art/icons.png (8x4 of 128 px).
import argparse, math, os, sys

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TITLE = ["FIRE", "ICE", "PLANT", "LIGHTNING", "WATER", "EARTH", "WIND", "POISON", "METAL", "LIGHT", "SAND", "LAVA",
         "SLIME", "VOID", "CRYSTAL", "MUSHROOM", "SMILEY", "67", "GAS", "SOUND", "YIN YANG", "TIME", "GHOST", "BOMB",
         "BUBBLE", "GLITCH", "CANDY"]
RGB = [(255, 84, 44), (64, 186, 255), (46, 208, 104), (255, 208, 40), (26, 84, 230), (150, 96, 52), (128, 236, 200),
       (156, 60, 226), (150, 162, 184), (255, 248, 214), (226, 160, 70), (206, 24, 58), (255, 96, 196), (22, 12, 34),
       (0, 186, 170), (176, 224, 48), (255, 226, 40), (255, 140, 0), (150, 170, 40), (230, 30, 150), (200, 200, 200),
       (80, 70, 200), (200, 190, 255), (80, 105, 55), (120, 230, 240), (255, 43, 214), (255, 51, 85)]

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--only", default="FIRE,WATER,EARTH,VOID")
ap.add_argument("--out", default="assets/art/balls3d")
ap.add_argument("--samples", type=int, default=96)
ap.add_argument("--res", type=int, default=512)
A = ap.parse_args(argv)


def lin(c):
    return tuple(((v / 255) ** 2.2) for v in c) + (1.0,)


def mixc(c, d, k):
    return tuple(c[i] + (d[i] - c[i]) * k for i in range(3))


# ---------- scene ----------
sc = bpy.context.scene
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob)
sc.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
except Exception as e:  # CPU fallback
    print("gpu:", e)
sc.cycles.samples = A.samples
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 12
sc.cycles.transmission_bounces = 12
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = A.res
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
for vt, look in (("Standard", "Medium High Contrast"),):
    try:
        sc.view_settings.view_transform = vt
        sc.view_settings.look = look
    except TypeError as e:
        print("view:", e)
sc.view_settings.exposure = 0.0

world = bpy.data.worlds.new("W")
sc.world = world
wn = world.node_tree.nodes
bg = next(n for n in wn if n.type == "BACKGROUND")
# Studio gradient environment: brighter top, dark floor (reflections read as a horizon line on the gloss).
grad_tc = wn.new("ShaderNodeTexCoord")
sep = wn.new("ShaderNodeSeparateXYZ")
ramp = wn.new("ShaderNodeValToRGB")
world.node_tree.links.new(grad_tc.outputs["Generated"], sep.inputs[0])
world.node_tree.links.new(sep.outputs["Z"], ramp.inputs[0])
ramp.color_ramp.elements[0].position = 0.45
ramp.color_ramp.elements[0].color = (0.01, 0.01, 0.02, 1)
ramp.color_ramp.elements[1].position = 0.75
ramp.color_ramp.elements[1].color = (0.55, 0.6, 0.75, 1)
world.node_tree.links.new(ramp.outputs[0], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.35

# Camera: 85 mm, slight elevation; ball faces the camera.
EL = math.radians(10)
D = 5.5
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = 85
cam = bpy.data.objects.new("Cam", cam_d)
sc.collection.objects.link(cam)
cam.location = (0, -D * math.cos(EL), D * math.sin(EL))
cam.rotation_euler = (math.pi / 2 - EL, 0, 0)
sc.camera = cam


def area(name, loc, size, power, color=(1, 1, 1), shape="DISK", glossy=True):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = shape
    ld.size = size
    ld.size_y = size * 0.55
    ld.energy = power
    ld.color = color
    ob = bpy.data.objects.new(name, ld)
    sc.collection.objects.link(ob)
    ob.location = loc
    ob.visible_glossy = glossy
    d = -__import__("mathutils").Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


area("Key", (-3.0, -3.2, 4.4), 2.6, 800, shape="RECTANGLE")
area("Fill", (4.0, -3.0, 0.5), 4.0, 140, (0.85, 0.9, 1.0), glossy=False)
area("RimL", (-3.5, 3.5, 1.8), 1.6, 650, (0.9, 0.95, 1.0))
area("RimR", (3.5, 3.0, 2.4), 1.6, 650, (1.0, 0.95, 0.9))

bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0)
ball = bpy.context.active_object
ball.name = "Ball"
for p in ball.data.polygons:
    p.use_smooth = True
ball.rotation_euler = (-EL, 0, 0)  # local -Y points at the camera

# Silhouette outline (as in Roblox shop art): a slightly larger sphere whose front faces are transparent and back faces
# dark, seen only by the camera.
bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.035)
hull = bpy.context.active_object
hull.name = "Outline"
for p in hull.data.polygons:
    p.use_smooth = True
for attr in ("visible_glossy", "visible_diffuse", "visible_shadow", "visible_transmission", "visible_volume_scatter"):
    setattr(hull, attr, False)
hm = bpy.data.materials.new("M_Outline")
hn = hm.node_tree.nodes
hn.clear()
geo = hn.new("ShaderNodeNewGeometry")
tr = hn.new("ShaderNodeBsdfTransparent")
em = hn.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (0.006, 0.007, 0.022, 1)  # Look.OUT #101228
mx = hn.new("ShaderNodeMixShader")
ho = hn.new("ShaderNodeOutputMaterial")
hm.node_tree.links.new(geo.outputs["Backfacing"], mx.inputs[0])
hm.node_tree.links.new(tr.outputs[0], mx.inputs[1])
hm.node_tree.links.new(em.outputs[0], mx.inputs[2])
hm.node_tree.links.new(mx.outputs[0], ho.inputs["Surface"])
hull.data.materials.append(hm)

# ---------- emblem images ----------
atlas = bpy.data.images.load(os.path.join(ROOT, "assets/art/icons.png"))
AW, AH = atlas.size
apx = np.empty(AW * AH * 4, dtype=np.float32)
atlas.pixels.foreach_get(apx)
apx = apx.reshape(AH, AW, 4)  # row 0 = bottom


OUTLINES = {}


def icon_image(e):
    col, row = e % 8, e // 8
    y0 = AH - (row + 1) * 128
    tile = apx[y0:y0 + 128, col * 128:(col + 1) * 128].copy()
    # outline mask: alpha dilated by 3 px, kept in the red channel of a second image
    a = tile[:, :, 3]
    d = a.copy()
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if dx * dx + dy * dy <= 10:
                d = np.maximum(d, np.roll(np.roll(a, dy, 0), dx, 1))
    om = bpy.data.images.new(f"outline{e}", 128, 128, alpha=True)
    o = np.zeros_like(tile)
    o[:, :, 0] = o[:, :, 1] = o[:, :, 2] = d
    o[:, :, 3] = 1.0
    om.colorspace_settings.name = "Non-Color"
    om.pixels.foreach_set(o.ravel())
    om.pack()
    OUTLINES[e] = om
    im = bpy.data.images.new(f"icon{e}", 128, 128, alpha=True)
    im.pixels.foreach_set(tile.ravel())
    im.pack()
    im.alpha_mode = "STRAIGHT"
    return im


# ---------- node helpers ----------
class NB:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()

    def n(self, t, ins=None, **props):
        node = self.nt.nodes.new(t)
        for k, v in props.items():
            setattr(node, k, v)
        for k, v in (ins or {}).items():
            s = node.inputs[k]
            if hasattr(v, "is_output"):
                self.nt.links.new(v, s)
            else:
                s.default_value = v
        return node

    def math(self, op, a, b=0.0, clamp=False):
        return self.n("ShaderNodeMath", {0: a, 1: b}, operation=op, use_clamp=clamp).outputs[0]

    def ramp(self, fac, stops, interp="LINEAR"):
        r = self.n("ShaderNodeValToRGB", {"Fac": fac})
        cr = r.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (p, c) in zip(cr.elements, stops):
            el.position = p
            el.color = c if len(c) == 4 else tuple(c) + (1,)
        return r.outputs["Color"]

    def mix(self, fac, a, b):
        return self.n("ShaderNodeMix", {"Factor": fac, 6: a, 7: b}, data_type="RGBA").outputs[2]

    def maprange(self, v, a, b, c=0.0, d=1.0):
        return self.n("ShaderNodeMapRange", {"Value": v, "From Min": a, "From Max": b, "To Min": c, "To Max": d}).outputs[0]


# ---------- per-element looks ----------
# Each look returns dict: base, rough, metal, emit, emit_k, bump (height socket), bump_k, extra principled inputs.
def look_plastic(b, e, obj):
    c = lin(RGB[e])
    n = b.n("ShaderNodeTexNoise", {"Vector": obj, "Scale": 2.0, "Detail": 2.0}).outputs["Fac"]
    base = b.ramp(n, [(0.3, mixc(c, (0, 0, 0), 0.12)), (0.7, c)])
    return dict(base=base, rough=0.35)


def look_fire(b, e, obj):
    m = b.n("ShaderNodeMapping", {"Vector": obj, "Scale": (1, 1, 0.6)})
    n = b.n("ShaderNodeTexNoise", {"Vector": m.outputs[0], "Scale": 2.6, "Detail": 8.0, "Roughness": 0.6,
                                   "Distortion": 1.6}).outputs["Fac"]
    z = b.n("ShaderNodeSeparateXYZ", {0: obj}).outputs["Z"]
    t = b.math("ADD", n, b.math("MULTIPLY", z, -0.22))
    flame = b.ramp(t, [(0.32, (0.12, 0.0, 0.0)), (0.46, (0.6, 0.03, 0.0)), (0.58, (1.0, 0.2, 0.0)),
                       (0.7, (1.0, 0.6, 0.05)), (0.8, (1.0, 0.9, 0.4))])
    glow = b.maprange(t, 0.4, 0.8, 0.15, 1.6)
    return dict(base=flame, rough=0.3, emit=flame, emit_k=glow, coat=0.8)


def look_water(b, e, obj):
    n = b.n("ShaderNodeTexNoise", {"Vector": obj, "Scale": 1.6, "Detail": 4.0, "Distortion": 1.0}).outputs["Fac"]
    deep = b.ramp(n, [(0.35, (0.0, 0.02, 0.2)), (0.65, (0.0, 0.12, 0.65))])
    w = b.n("ShaderNodeTexWave", {"Vector": obj, "Scale": 1.3, "Distortion": 7.0, "Detail": 3.0, "Detail Scale": 1.0},
            wave_type="BANDS", bands_direction="Z")
    f = w.outputs["Fac"]
    crest = b.maprange(f, 0.86, 1.0)
    base = b.mix(b.math("MULTIPLY", crest, 0.75), deep, (0.35, 0.75, 1.0, 1))
    z = b.n("ShaderNodeSeparateXYZ", {0: obj}).outputs["Z"]
    base = b.mix(b.maprange(z, 0.2, 1.0, 0.0, 0.35), base, (0.3, 0.75, 1.0, 1))
    return dict(base=base, rough=0.08, bump=f, bump_k=0.3, emit=base, emit_k=b.math("MULTIPLY", crest, 0.35))


def look_earth(b, e, obj):
    v = b.n("ShaderNodeTexVoronoi", {"Vector": obj, "Scale": 3.2, "Randomness": 0.9})
    edge = b.n("ShaderNodeTexVoronoi", {"Vector": obj, "Scale": 3.2, "Randomness": 0.9},
               feature="DISTANCE_TO_EDGE").outputs["Distance"]
    cell = b.n("ShaderNodeSeparateColor", {0: v.outputs["Color"]}).outputs[0]
    n = b.n("ShaderNodeTexNoise", {"Vector": obj, "Scale": 14.0, "Detail": 10.0, "Roughness": 0.65}).outputs["Fac"]
    shade = b.math("ADD", b.math("MULTIPLY", cell, 0.6), b.math("MULTIPLY", n, 0.6))
    stone = b.ramp(shade, [(0.25, (0.05, 0.02, 0.008)), (0.6, (0.17, 0.07, 0.02)), (0.95, (0.36, 0.2, 0.08))])
    groove = b.maprange(edge, 0.0, 0.06)
    base = b.mix(groove, (0.05, 0.02, 0.01, 1), stone)
    height = b.math("ADD", b.math("MULTIPLY", groove, 1.0), b.math("MULTIPLY", n, 0.35))
    return dict(base=base, rough=0.55, bump=height, bump_k=0.5, coat=0.45)


def look_void(b, e, obj):
    m = b.n("ShaderNodeTexNoise", {"Vector": obj, "Scale": 1.8, "Detail": 8.0, "Roughness": 0.62,
                                   "Distortion": 2.4}).outputs["Fac"]
    neb = b.ramp(m, [(0.45, (0.0, 0.0, 0.0)), (0.6, (0.05, 0.0, 0.16)), (0.72, (0.3, 0.04, 0.75)),
                     (0.85, (0.9, 0.35, 1.0))])
    st = b.n("ShaderNodeTexVoronoi", {"Vector": obj, "Scale": 26.0}).outputs["Distance"]
    star = b.math("POWER", b.maprange(st, 0.09, 0.0), 3.0)
    emit = b.mix(star, neb, (1, 1, 1, 1))
    lw = b.n("ShaderNodeLayerWeight", {"Blend": 0.35}).outputs["Facing"]
    rim = b.math("POWER", lw, 3.0)
    emit = b.mix(rim, emit, (0.5, 0.1, 1.0, 1))
    return dict(base=(0.002, 0.0, 0.006, 1), rough=0.2, emit=emit, emit_k=1.4, coat=1.0)


LOOKS = {"FIRE": look_fire, "WATER": look_water, "EARTH": look_earth, "VOID": look_void}

A_HALF = 0.6  # emblem half-angle (rad)


def build(e):
    name = TITLE[e]
    mat = bpy.data.materials.new(f"M_{name}")
    b = NB(mat)
    tc = b.n("ShaderNodeTexCoord")
    obj, nrm = tc.outputs["Object"], tc.outputs["Normal"]
    L = LOOKS.get(name, look_plastic)(b, e, obj)
    P = b.n("ShaderNodeBsdfPrincipled")
    out = b.n("ShaderNodeOutputMaterial")
    b.nt.links.new(P.outputs[0], out.inputs["Surface"])

    # emblem coordinates: angles of the object normal around the front (-Y) axis, so the icon wraps the sphere
    s = b.n("ShaderNodeSeparateXYZ", {0: nrm})
    ny = b.math("MULTIPLY", s.outputs["Y"], -1.0)
    u = b.math("ADD", b.math("DIVIDE", b.math("ARCTAN2", s.outputs["X"], ny), 2 * A_HALF), 0.5)
    v = b.math("ADD", b.math("DIVIDE", b.math("ARCTAN2", s.outputs["Z"], ny), 2 * A_HALF), 0.5)
    uv = b.n("ShaderNodeCombineXYZ", {0: u, 1: v}).outputs[0]
    img = b.n("ShaderNodeTexImage", {"Vector": uv}, image=icon_image(e), extension="CLIP", interpolation="Cubic")
    alpha = img.outputs["Alpha"]
    fill = b.maprange(alpha, 0.35, 0.6)
    oimg = b.n("ShaderNodeTexImage", {"Vector": uv}, image=OUTLINES[e], extension="CLIP", interpolation="Cubic")
    ring = b.maprange(oimg.outputs["Color"], 0.3, 0.6)
    dark = lin(mixc(RGB[e], (0, 0, 0), 0.7))
    if name == "VOID":
        dark = lin((70, 20, 140))
    base_in = L["base"]
    base_in = b.mix(ring, base_in, dark)
    icon_rgb = b.n("ShaderNodeMix", {"Factor": 0.3, 6: img.outputs["Color"], 7: (0.55, 0.58, 0.72, 1)}, data_type="RGBA").outputs[2]
    base_in = b.mix(fill, base_in, icon_rgb)
    b.nt.links.new(base_in, P.inputs["Base Color"]) if hasattr(base_in, "is_output") else None
    if not hasattr(base_in, "is_output"):
        P.inputs["Base Color"].default_value = base_in

    rough = L.get("rough", 0.35)
    P.inputs["Roughness"].default_value = rough
    P.inputs["Metallic"].default_value = L.get("metal", 0.0)
    P.inputs["Coat Weight"].default_value = L.get("coat", 1.0)
    P.inputs["Coat Roughness"].default_value = 0.04
    if "trans" in L:
        P.inputs["Transmission Weight"].default_value = L["trans"]
        P.inputs["IOR"].default_value = L.get("ior", 1.45)

    # emission: element glow everywhere but on the emblem; the emblem itself glows softly white
    em = L.get("emit")
    ek = L.get("emit_k", 0.0)
    nofill = b.math("SUBTRACT", 1.0, b.math("MAXIMUM", fill, ring), clamp=True)
    if em is not None:
        emc = b.mix(fill, em, icon_rgb)
        b.nt.links.new(emc, P.inputs["Emission Color"])
        k = b.math("MULTIPLY", ek if hasattr(ek, "is_output") else float(ek), nofill)
        k = b.math("ADD", k, b.math("MULTIPLY", fill, 0.9 if name == "VOID" else 0.06))
        b.nt.links.new(k, P.inputs["Emission Strength"])
    else:
        b.nt.links.new(icon_rgb, P.inputs["Emission Color"])
        b.nt.links.new(b.math("MULTIPLY", fill, 0.06), P.inputs["Emission Strength"])

    # bump: surface relief + raised emblem (outline ring is the bevel)
    h = b.math("ADD", ring, fill)
    if "bump" in L:
        h = b.math("ADD", h, b.math("MULTIPLY", b.math("MULTIPLY", L["bump"], L.get("bump_k", 0.3)), nofill))
    bump = b.n("ShaderNodeBump", {"Height": h, "Strength": 0.35, "Distance": 0.02})
    b.nt.links.new(bump.outputs["Normal"], P.inputs["Normal"])
    return mat


out_dir = os.path.join(ROOT, A.out)
os.makedirs(out_dir, exist_ok=True)
names = [s.strip() for s in A.only.split(",") if s.strip()] if A.only != "ALL" else TITLE
for name in names:
    e = TITLE.index(name)
    ball.data.materials.clear()
    ball.data.materials.append(build(e))
    fn = name.lower().replace(" ", "_")
    sc.render.filepath = os.path.join(out_dir, f"ball_{fn}.png")
    bpy.ops.render.render(write_still=True)
    print("@@JSON@@", {"ball": name, "file": sc.render.filepath})
