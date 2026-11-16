# Ball renders for the UI (own render, CC0 by this project).
# blender -b --factory-startup -P tools/art/blender/balls.py -- --only FIRE,WATER --out assets/art/balls3d
# One camera, one light rig for every ball. Emblem = icon(e) from assets/art/icons.png (8x4 of 128 px) pressed into the
# geometry as a raised relief with a recessed groove (real displacement, so it catches light and casts shade).
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

bpy.ops.mesh.primitive_uv_sphere_add(segments=768, ring_count=384, radius=1.0)
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

# ---------- emblem maps (256 px) ----------
atlas = bpy.data.images.load(os.path.join(ROOT, "assets/art/icons.png"))
AW, AH = atlas.size
apx = np.empty(AW * AH * 4, dtype=np.float32)
atlas.pixels.foreach_get(apx)
apx = apx.reshape(AH, AW, 4)  # row 0 = bottom
ER = 256  # emblem map resolution


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, sigma):
    r = int(sigma * 3) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, r, mode="edge")
    p = np.apply_along_axis(lambda m: np.convolve(m, k, mode="valid"), 0, p)
    return np.apply_along_axis(lambda m: np.convolve(m, k, mode="valid"), 1, p)


def zoom2(t):
    """128 -> 256 bilinear for an (h, w, c) array."""
    n = t.shape[0]
    x = (np.arange(ER) + 0.5) / 2 - 0.5
    x0 = np.clip(np.floor(x).astype(int), 0, n - 1)
    x1 = np.clip(x0 + 1, 0, n - 1)
    f = np.clip(x - x0, 0, 1)
    rows = t[x0] * (1 - f)[:, None, None] + t[x1] * f[:, None, None]
    return rows[:, x0] * (1 - f)[None, :, None] + rows[:, x1] * f[None, :, None]


def flame_mask():
    """Symmetric stylised flame (the atlas fire icon is lopsided): round base, S-curved tip, inner cut tongue."""
    y, x = (np.mgrid[0:ER, 0:ER] + 0.5) / ER  # y up (row 0 = bottom)
    x = x - 0.5
    yy = (y - 0.12) / 0.78  # 0 bottom .. 1 tip
    cx = 0.1 * np.sin(np.clip(yy, 0, 1) * math.pi * 1.1) * np.clip(yy - 0.35, 0, 1) * 2.2
    base_r = 0.26
    w = np.where(yy < 0.33, base_r * np.sqrt(np.clip(1 - ((yy - 0.33) / 0.33) ** 2, 0, 1)),
                 base_r * np.clip((1 - yy) / 0.67, 0, 1) ** 1.25)
    outer = (np.abs(x - cx) < w) & (yy > 0) & (yy < 1)
    # side tongues: small flames leaning out from the base, left taller
    for sx, top, lean in ((-1, 0.66, -0.07), (1, 0.52, 0.05)):
        ys = (y - 0.2) / (top - 0.2)
        cxs = sx * 0.17 + lean * np.clip(ys, 0, 1) ** 2
        ws = 0.085 * np.clip(1 - ys, 0, 1) ** 1.1 * np.clip(ys * 4, 0, 1)
        outer |= (np.abs(x - cxs) < ws) & (ys > 0) & (ys < 1)
    # inner tongue cut: small flame shape offset down
    y2 = (y - 0.14) / 0.42
    w2 = np.where(y2 < 0.4, 0.1 * np.sqrt(np.clip(1 - ((y2 - 0.4) / 0.4) ** 2, 0, 1)),
                  0.1 * np.clip((1 - y2) / 0.6, 0, 1) ** 1.3)
    inner = (np.abs(x + 0.01) < w2) & (y2 > 0) & (y2 < 1)
    return blur(outer.astype(np.float32), 1.0), blur(inner.astype(np.float32), 1.0)


def emblem(e):
    """Returns (colour image, mask image, height array). mask: R fill, G groove, B inner (second colour level)."""
    col, row = e % 8, e // 8
    y0 = AH - (row + 1) * 128
    tile = zoom2(apx[y0:y0 + 128, col * 128:(col + 1) * 128].copy())
    inner = np.zeros((ER, ER), np.float32)
    if TITLE[e] == "FIRE":
        a, inner = flame_mask()
        tile[:, :, :3] = 1.0
    else:
        a = blur(smooth(tile[:, :, 3], 0.4, 0.6), 0.8)
    hard = smooth(a, 0.45, 0.55)
    fill = smooth(blur(hard, 0.8), 0.3, 0.7)
    dil = smooth(blur(hard, 5.0), 0.04, 0.2)
    groove = np.clip(dil - fill, 0, 1)
    bevel = smooth(blur(hard, 3.0), 0.5, 0.97)
    h = 0.042 * bevel - 0.014 * blur(groove, 1.5) - 0.02 * blur(inner, 1.2) * bevel
    rgb = tile.copy()
    rgb[:, :, 3] = 1.0
    ci = bpy.data.images.new(f"emb{e}", ER, ER, alpha=True)
    ci.pixels.foreach_set(rgb.astype(np.float32).ravel())
    ci.pack()
    mk = np.zeros((ER, ER, 4), np.float32)
    mk[:, :, 0], mk[:, :, 1], mk[:, :, 2], mk[:, :, 3] = fill, groove, inner, 1.0
    mi = bpy.data.images.new(f"mask{e}", ER, ER, alpha=True)
    mi.colorspace_settings.name = "Non-Color"
    mi.pixels.foreach_set(mk.astype(np.float32).ravel())
    mi.pack()
    return ci, mi, h


# ---------- sphere: emblem UVs (angles of the normal around the front -Y axis) ----------
A_HALF = 0.6  # emblem half-angle (rad)
me = ball.data
NV = len(me.vertices)
CO0 = np.empty(NV * 3, np.float32)
me.vertices.foreach_get("co", CO0)
CO0 = CO0.reshape(NV, 3)
U = 0.5 + np.arctan2(CO0[:, 0], -CO0[:, 1]) / (2 * A_HALF)
V = 0.5 + np.arctan2(CO0[:, 2], -CO0[:, 1]) / (2 * A_HALF)
uvl = me.uv_layers.new(name="EMB")
li = np.empty(len(me.loops), np.int32)
me.loops.foreach_get("vertex_index", li)
uvl.data.foreach_set("uv", np.stack([U[li], V[li]], 1).astype(np.float32).ravel())


def displace(h):
    inside = (U >= 0) & (U <= 1) & (V >= 0) & (V <= 1) & (CO0[:, 1] < 0)
    px = np.clip(U * ER - 0.5, 0, ER - 1.001)
    py = np.clip(V * ER - 0.5, 0, ER - 1.001)
    x0, y0 = px.astype(int), py.astype(int)
    fx, fy = px - x0, py - y0
    s = (h[y0, x0] * (1 - fx) * (1 - fy) + h[y0, x0 + 1] * fx * (1 - fy) + h[y0 + 1, x0] * (1 - fx) * fy
         + h[y0 + 1, x0 + 1] * fx * fy)
    s = np.where(inside, s, 0.0)
    me.vertices.foreach_set("co", (CO0 * (1 + s)[:, None]).astype(np.float32).ravel())
    me.update()


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

    def mix(self, fac, a, b, blend="MIX"):
        return self.n("ShaderNodeMix", {"Factor": fac, 6: a, 7: b}, data_type="RGBA", blend_type=blend).outputs[2]

    def maprange(self, v, a, b, c=0.0, d=1.0):
        return self.n("ShaderNodeMapRange", {"Value": v, "From Min": a, "From Max": b, "To Min": c, "To Max": d}).outputs[0]

    def noise(self, v, scale, detail=2.0, dist=0.0, rough=0.5):
        return self.n("ShaderNodeTexNoise", {"Vector": v, "Scale": scale, "Detail": detail, "Distortion": dist,
                                             "Roughness": rough}).outputs["Fac"]

    def vor(self, v, scale, feature="F1", rand=1.0):
        return self.n("ShaderNodeTexVoronoi", {"Vector": v, "Scale": scale, "Randomness": rand}, feature=feature)

    def wave(self, v, scale, dist, kind="BANDS", direction="Z", detail=2.0):
        w = self.n("ShaderNodeTexWave", {"Vector": v, "Scale": scale, "Distortion": dist, "Detail": detail},
                   wave_type=kind)
        if kind == "BANDS":
            w.bands_direction = direction
        else:
            w.rings_direction = direction
        return w.outputs["Fac"]

    def z(self, v):
        return self.n("ShaderNodeSeparateXYZ", {0: v}).outputs["Z"]

    def rim(self, blend=0.35, power=3.0):
        return self.math("POWER", self.n("ShaderNodeLayerWeight", {"Blend": blend}).outputs["Facing"], power)


def C(r, g, bb):
    return lin((r, g, bb))


def grad(b, obj, c_lo, c_hi, k=0.35):
    """Base colour lit from above: c_lo bottom -> c_hi top with soft noise."""
    t = b.math("ADD", b.math("MULTIPLY", b.z(obj), k), b.math("MULTIPLY", b.noise(obj, 2.0, 2.0), 0.3))
    return b.ramp(t, [(0.0, c_lo), (0.55, c_hi)])


# ---------- per-element looks ----------
# dict: base, rough, metal, coat, emit, emit_k, bump, bump_k, sss, thin, trans; emblem: emb (tint), emb_k (glow),
# emb_metal, emb_rough, emb_icon (use icon colours, e.g. yin yang)
def look_plastic(b, e, obj):
    c = lin(RGB[e])
    return dict(base=grad(b, obj, lin(mixc(RGB[e], (0, 0, 0), 0.35)), c), rough=0.3)


def look_fire(b, e, obj):
    m = b.n("ShaderNodeMapping", {"Vector": obj, "Scale": (1, 1, 0.6)})
    n = b.noise(m.outputs[0], 2.6, 8.0, 1.6, 0.6)
    t = b.math("ADD", n, b.math("MULTIPLY", b.z(obj), -0.22))
    flame = b.ramp(t, [(0.32, (0.12, 0.0, 0.0)), (0.46, (0.6, 0.03, 0.0)), (0.58, (1.0, 0.2, 0.0)),
                       (0.7, (1.0, 0.6, 0.05)), (0.8, (1.0, 0.9, 0.4))])
    glow = b.maprange(t, 0.4, 0.8, 0.15, 1.6)
    return dict(base=flame, rough=0.3, emit=flame, emit_k=glow, coat=0.8, emb=C(255, 214, 90), emb_k=0.9,
                emb_inner=C(255, 120, 20))


def look_ice(b, e, obj):
    v = b.vor(obj, 2.6, "DISTANCE_TO_EDGE").outputs["Distance"]
    crack = b.maprange(v, 0.035, 0.0)
    n = b.noise(obj, 3.0, 6.0, 0.5)
    base = b.ramp(n, [(0.3, C(70, 160, 225)), (0.7, C(170, 225, 255))])
    base = b.mix(crack, base, C(235, 250, 255))
    return dict(base=base, rough=0.08, bump=crack, bump_k=-0.4, sss=0.25, emit=C(150, 220, 255),
                emit_k=b.math("MULTIPLY", crack, 0.5), emb=C(240, 252, 255))


def look_plant(b, e, obj):
    v = b.vor(obj, 3.5, "DISTANCE_TO_EDGE").outputs["Distance"]
    vein = b.maprange(v, 0.03, 0.0)
    base = grad(b, obj, C(10, 80, 30), C(70, 215, 100))
    base = b.mix(b.math("MULTIPLY", vein, 0.6), base, C(190, 255, 150))
    return dict(base=base, rough=0.35, bump=vein, bump_k=0.4, sss=0.1, emb=C(200, 255, 170))


def look_lightning(b, e, obj):
    n = b.noise(obj, 2.2, 4.0, 0.8)
    bolt = b.maprange(b.math("ABSOLUTE", b.math("SUBTRACT", n, 0.5)), 0.03, 0.0)
    base = grad(b, obj, C(200, 120, 0), C(255, 215, 40))
    base = b.mix(bolt, base, C(255, 255, 230))
    return dict(base=base, rough=0.25, emit=C(255, 245, 180), emit_k=b.math("MULTIPLY", bolt, 3.0),
                emb=C(255, 255, 235), emb_k=0.5)


def look_water(b, e, obj):
    n = b.noise(obj, 1.6, 4.0, 1.0)
    deep = b.ramp(n, [(0.35, (0.0, 0.02, 0.2)), (0.65, (0.0, 0.12, 0.65))])
    f = b.wave(obj, 1.3, 7.0, detail=3.0)
    crest = b.maprange(f, 0.86, 1.0)
    base = b.mix(b.math("MULTIPLY", crest, 0.75), deep, (0.35, 0.75, 1.0, 1))
    base = b.mix(b.maprange(b.z(obj), 0.2, 1.0, 0.0, 0.35), base, (0.3, 0.75, 1.0, 1))
    return dict(base=base, rough=0.08, bump=f, bump_k=0.3, emit=base, emit_k=b.math("MULTIPLY", crest, 0.35),
                emb=C(150, 215, 255))


def look_earth(b, e, obj):
    v = b.vor(obj, 3.2, rand=0.9)
    edge = b.vor(obj, 3.2, "DISTANCE_TO_EDGE", 0.9).outputs["Distance"]
    cell = b.n("ShaderNodeSeparateColor", {0: v.outputs["Color"]}).outputs[0]
    n = b.noise(obj, 14.0, 10.0, 0, 0.65)
    shade = b.math("ADD", b.math("MULTIPLY", cell, 0.6), b.math("MULTIPLY", n, 0.6))
    stone = b.ramp(shade, [(0.25, (0.05, 0.02, 0.008)), (0.6, (0.17, 0.07, 0.02)), (0.95, (0.36, 0.2, 0.08))])
    groove = b.maprange(edge, 0.0, 0.06)
    base = b.mix(groove, (0.05, 0.02, 0.01, 1), stone)
    height = b.math("ADD", groove, b.math("MULTIPLY", n, 0.35))
    return dict(base=base, rough=0.55, bump=height, bump_k=0.5, coat=0.45, emb=C(215, 170, 110), emb_rough=0.5)


def look_wind(b, e, obj):
    m = b.n("ShaderNodeMapping", {"Vector": obj, "Rotation": (0.0, 0.5, 0.0)})
    f = b.wave(m.outputs[0], 1.4, 5.0, detail=1.0)
    base = b.ramp(f, [(0.2, C(40, 150, 125)), (0.6, C(120, 230, 195)), (0.9, C(225, 255, 245))])
    return dict(base=base, rough=0.25, bump=f, bump_k=0.15, emb=C(235, 255, 248))


def look_poison(b, e, obj):
    base = grad(b, obj, C(45, 8, 80), C(150, 55, 220))
    d = b.vor(obj, 6.0).outputs["Distance"]
    blob = b.maprange(d, 0.22, 0.12)
    base = b.mix(blob, base, C(120, 255, 60))
    return dict(base=base, rough=0.2, emit=C(120, 255, 60), emit_k=b.math("MULTIPLY", blob, 1.2), bump=blob,
                bump_k=0.6, emb=C(140, 255, 80), emb_k=0.35)


def look_metal(b, e, obj):
    n = b.noise(b.n("ShaderNodeMapping", {"Vector": obj, "Scale": (1, 1, 30)}).outputs[0], 4.0, 2.0)
    base = b.ramp(n, [(0.3, C(120, 130, 150)), (0.7, C(200, 208, 222))])
    # half-metal: a pure metal mirrors the dark studio and renders black
    return dict(base=base, rough=0.3, metal=0.55, coat=0.8, bump=n, bump_k=0.05, emb=C(240, 242, 248),
                emb_rough=0.12)


def look_light(b, e, obj):
    base = grad(b, obj, C(240, 200, 120), C(255, 250, 225))
    return dict(base=base, rough=0.3, emit=C(255, 236, 170), emit_k=b.math("MULTIPLY", b.rim(0.4, 2.0), 1.6),
                emb=C(255, 185, 40), emb_metal=0.35, emb_rough=0.2, emb_k=0.35)


def look_sand(b, e, obj):
    f = b.wave(obj, 2.0, 3.0, detail=2.0)
    g = b.noise(obj, 60.0, 2.0)
    base = b.ramp(b.math("ADD", b.math("MULTIPLY", f, 0.5), b.math("MULTIPLY", g, 0.4)),
                  [(0.2, C(170, 105, 45)), (0.7, C(240, 190, 110))])
    return dict(base=base, rough=0.6, coat=0.35, bump=b.math("ADD", f, b.math("MULTIPLY", g, 0.4)), bump_k=0.25,
                emb=C(255, 225, 160), emb_rough=0.5)


def look_lava(b, e, obj):
    edge = b.vor(obj, 4.0, "DISTANCE_TO_EDGE").outputs["Distance"]
    crack = b.maprange(edge, 0.07, 0.0)
    n = b.noise(obj, 10.0, 8.0)
    rock = b.ramp(n, [(0.3, C(20, 10, 12)), (0.7, C(60, 30, 30))])
    hot = b.ramp(crack, [(0.0, C(200, 10, 20)), (0.6, C(255, 110, 20)), (1.0, C(255, 230, 120))])
    base = b.mix(crack, rock, hot)
    return dict(base=base, rough=0.5, coat=0.5, emit=hot, emit_k=b.math("MULTIPLY", crack, 4.0),
                bump=b.math("SUBTRACT", n, crack), bump_k=0.4, emb=C(255, 120, 40), emb_k=1.2,
                emb_inner=C(255, 220, 80))


def look_slime(b, e, obj):
    d = b.vor(obj, 3.0).outputs["Distance"]
    base = grad(b, obj, C(190, 30, 120), C(255, 140, 215))
    return dict(base=base, rough=0.05, sss=0.4, bump=b.maprange(d, 0.0, 0.5), bump_k=-0.35, emb=C(255, 200, 235))


def look_void(b, e, obj):
    m = b.noise(obj, 1.8, 8.0, 2.4, 0.62)
    neb = b.ramp(m, [(0.45, (0.0, 0.0, 0.0)), (0.6, (0.05, 0.0, 0.16)), (0.72, (0.3, 0.04, 0.75)),
                     (0.85, (0.9, 0.35, 1.0))])
    st = b.vor(obj, 26.0).outputs["Distance"]
    star = b.math("POWER", b.maprange(st, 0.09, 0.0), 3.0)
    emit = b.mix(star, neb, (1, 1, 1, 1))
    emit = b.mix(b.rim(), emit, (0.5, 0.1, 1.0, 1))
    return dict(base=(0.002, 0.0, 0.006, 1), rough=0.2, emit=emit, emit_k=1.4, coat=1.0, emb=C(150, 90, 255),
                emb_k=0.8)


def look_crystal(b, e, obj):
    v = b.vor(obj, 2.4, rand=1.0)
    cell = b.n("ShaderNodeSeparateColor", {0: v.outputs["Color"]}).outputs[0]
    edge = b.maprange(b.vor(obj, 2.4, "DISTANCE_TO_EDGE").outputs["Distance"], 0.02, 0.0)
    base = b.ramp(cell, [(0.0, C(0, 80, 90)), (0.5, C(0, 170, 160)), (1.0, C(150, 255, 240))])
    base = b.mix(edge, base, C(220, 255, 250))
    return dict(base=base, rough=0.05, bump=cell, bump_k=0.6, emit=C(100, 255, 230),
                emit_k=b.math("MULTIPLY", edge, 1.2), emb=C(200, 255, 248), emb_rough=0.05)


def look_mushroom(b, e, obj):
    base = grad(b, obj, C(80, 120, 10), C(185, 230, 60))
    d = b.vor(obj, 3.0, rand=0.7).outputs["Distance"]
    dot = b.maprange(d, 0.24, 0.2)
    base = b.mix(dot, base, C(255, 255, 235))
    return dict(base=base, rough=0.35, bump=dot, bump_k=0.5, emb=C(255, 252, 230))


def look_smiley(b, e, obj):
    return dict(base=grad(b, obj, C(220, 140, 0), C(255, 230, 50)), rough=0.2, emb=C(90, 50, 0), emb_rough=0.2)


def look_67(b, e, obj):
    return dict(base=grad(b, obj, C(190, 70, 0), C(255, 155, 20)), rough=0.25, emb=C(255, 245, 225))


def look_gas(b, e, obj):
    n = b.noise(obj, 2.0, 6.0, 1.5)
    base = b.ramp(n, [(0.3, C(70, 80, 10)), (0.55, C(150, 170, 40)), (0.75, C(215, 230, 120))])
    return dict(base=base, rough=0.4, emit=base, emit_k=b.maprange(n, 0.6, 0.8, 0.0, 0.3), emb=C(230, 245, 150))


def look_sound(b, e, obj):
    r = b.wave(obj, 2.5, 0.5, kind="RINGS", direction="Y", detail=0.0)
    base = b.ramp(r, [(0.3, C(150, 10, 90)), (0.7, C(250, 70, 180))])
    return dict(base=base, rough=0.2, bump=r, bump_k=0.15, emb=C(255, 210, 240))


def look_yinyang(b, e, obj):
    return dict(base=grad(b, obj, C(150, 150, 160), C(240, 240, 245)), rough=0.2, emb=C(255, 255, 255), emb_icon=1)


def look_time(b, e, obj):
    r = b.wave(obj, 1.5, 0.0, kind="RINGS", direction="Y", detail=0.0)
    base = b.mix(b.math("MULTIPLY", r, 0.25), grad(b, obj, C(25, 15, 90), C(95, 85, 220)), C(150, 140, 255))
    return dict(base=base, rough=0.2, emb=C(255, 200, 80), emb_metal=0.5, emb_rough=0.2)


def look_ghost(b, e, obj):
    n = b.noise(obj, 1.6, 4.0, 1.0)
    base = b.ramp(n, [(0.3, C(150, 135, 230)), (0.7, C(235, 230, 255))])
    return dict(base=base, rough=0.25, sss=0.5, emit=C(210, 200, 255), emit_k=b.math("MULTIPLY", b.rim(0.4, 2.0), 1.0),
                emb=C(255, 255, 255), emb_icon=1)


def look_bomb(b, e, obj):
    base = grad(b, obj, C(12, 16, 10), C(70, 95, 50))
    return dict(base=base, rough=0.18, coat=1.0, emb=C(230, 235, 220), emb_icon=1)


def look_bubble(b, e, obj):
    base = grad(b, obj, C(60, 170, 200), C(190, 245, 255))
    return dict(base=base, rough=0.03, thin=520.0, emit=C(200, 250, 255), emit_k=b.math("MULTIPLY", b.rim(0.3, 2.0), 0.8),
                emb=C(255, 255, 255))


def look_glitch(b, e, obj):
    snap = b.n("ShaderNodeVectorMath", {0: b.n("ShaderNodeVectorMath", {0: obj, 1: (7, 7, 7)},
                                                operation="MULTIPLY").outputs[0]}, operation="FLOOR").outputs[0]
    wn = b.n("ShaderNodeTexWhiteNoise", {"Vector": snap}).outputs["Value"]
    base = b.ramp(wn, [(0.0, C(30, 10, 60)), (0.33, C(30, 10, 60)), (0.34, C(255, 43, 214)), (0.66, C(255, 43, 214)),
                       (0.67, C(43, 240, 255))], "CONSTANT")
    return dict(base=base, rough=0.2, emit=base, emit_k=0.35, emb=C(255, 255, 255), emb_k=0.4)


def look_candy(b, e, obj):
    m = b.n("ShaderNodeMapping", {"Vector": obj, "Rotation": (0.0, 0.7, 0.3)})
    f = b.wave(m.outputs[0], 2.0, 0.0, detail=0.0)
    stripe = b.maprange(f, 0.45, 0.55)
    base = b.mix(stripe, C(225, 20, 55), C(255, 245, 245))
    return dict(base=base, rough=0.12, emb=C(255, 255, 255), emb_icon=1)


LOOKS = {"FIRE": look_fire, "ICE": look_ice, "PLANT": look_plant, "LIGHTNING": look_lightning, "WATER": look_water,
         "EARTH": look_earth, "WIND": look_wind, "POISON": look_poison, "METAL": look_metal, "LIGHT": look_light,
         "SAND": look_sand, "LAVA": look_lava, "SLIME": look_slime, "VOID": look_void, "CRYSTAL": look_crystal,
         "MUSHROOM": look_mushroom, "SMILEY": look_smiley, "67": look_67, "GAS": look_gas, "SOUND": look_sound,
         "YIN YANG": look_yinyang, "TIME": look_time, "GHOST": look_ghost, "BOMB": look_bomb, "BUBBLE": look_bubble,
         "GLITCH": look_glitch, "CANDY": look_candy}


def sock(b, v):
    """Constant colour tuple -> RGB node output, so every input can be linked."""
    if hasattr(v, "is_output"):
        return v
    return _rgb(b, v)


def _rgb(b, v):
    n = b.n("ShaderNodeRGB")
    n.outputs[0].default_value = v if len(v) == 4 else tuple(v) + (1,)
    return n.outputs[0]


def build(e, ci, mi):
    name = TITLE[e]
    mat = bpy.data.materials.new(f"M_{name}")
    b = NB(mat)
    tc = b.n("ShaderNodeTexCoord")
    obj = tc.outputs["Object"]
    L = LOOKS.get(name, look_plastic)(b, e, obj)
    P = b.n("ShaderNodeBsdfPrincipled")
    out = b.n("ShaderNodeOutputMaterial")
    b.nt.links.new(P.outputs[0], out.inputs["Surface"])

    uv = b.n("ShaderNodeUVMap", uv_map="EMB").outputs[0]
    cimg = b.n("ShaderNodeTexImage", {"Vector": uv}, image=ci, extension="CLIP", interpolation="Linear")
    mimg = b.n("ShaderNodeTexImage", {"Vector": uv}, image=mi, extension="CLIP", interpolation="Linear")
    sm = b.n("ShaderNodeSeparateColor", {0: mimg.outputs["Color"]})
    fill, groove, inner = sm.outputs[0], sm.outputs[1], sm.outputs[2]

    base = sock(b, L["base"])
    # emblem = the ball's own material lifted to a lighter tone: tint * (0.75 + 0.25 * surface)
    tint = sock(b, L.get("emb", (1, 1, 1, 1)))
    if L.get("emb_icon"):
        tint = b.mix(1.0, tint, cimg.outputs["Color"], "MULTIPLY")
    if "emb_inner" in L:
        tint = b.mix(inner, tint, sock(b, L["emb_inner"]))
    embc = b.mix(0.18, tint, base)
    shaded = b.mix(b.math("MULTIPLY", groove, 0.75), base, (0.0, 0.0, 0.0, 1))
    b.nt.links.new(b.mix(fill, shaded, embc), P.inputs["Base Color"])

    rough = L.get("rough", 0.3)
    b.nt.links.new(b.n("ShaderNodeMix", {"Factor": fill, 2: rough, 3: L.get("emb_rough", min(rough, 0.25))},
                       data_type="FLOAT").outputs[0], P.inputs["Roughness"])
    b.nt.links.new(b.n("ShaderNodeMix", {"Factor": fill, 2: L.get("metal", 0.0), 3: L.get("emb_metal", 0.0)},
                       data_type="FLOAT").outputs[0], P.inputs["Metallic"])
    P.inputs["Coat Weight"].default_value = L.get("coat", 1.0)
    P.inputs["Coat Roughness"].default_value = 0.04
    if L.get("sss"):
        P.inputs["Subsurface Weight"].default_value = L["sss"]
        P.inputs["Subsurface Radius"].default_value = (0.3, 0.3, 0.3)
    if L.get("thin"):
        P.inputs["Thin Film Thickness"].default_value = L["thin"]
        P.inputs["Thin Film IOR"].default_value = 1.33

    # emission: body glow outside the emblem; the emblem glows only for glowing elements (emb_k)
    nofill = b.math("SUBTRACT", 1.0, b.math("MAXIMUM", fill, groove), clamp=True)
    em = L.get("emit")
    ek = L.get("emit_k", 0.0)
    emc = b.mix(fill, sock(b, em if em is not None else (0, 0, 0, 1)), embc)
    b.nt.links.new(emc, P.inputs["Emission Color"])
    k = b.math("MULTIPLY", ek, nofill) if em is not None else b.math("MULTIPLY", 0.0, nofill)
    k = b.math("ADD", k, b.math("MULTIPLY", fill, L.get("emb_k", 0.0)))
    b.nt.links.new(k, P.inputs["Emission Strength"])

    # micro relief of the body (the emblem relief is real geometry)
    if "bump" in L:
        h = b.math("MULTIPLY", b.math("MULTIPLY", L["bump"], L.get("bump_k", 0.3)), nofill)
        bump = b.n("ShaderNodeBump", {"Height": h, "Strength": 0.35, "Distance": 0.02})
        b.nt.links.new(bump.outputs["Normal"], P.inputs["Normal"])
    return mat


out_dir = os.path.join(ROOT, A.out)
os.makedirs(out_dir, exist_ok=True)
names = [s.strip() for s in A.only.split(",") if s.strip()] if A.only != "ALL" else TITLE
for name in names:
    e = TITLE.index(name)
    ci, mi, h = emblem(e)
    displace(h)
    ball.data.materials.clear()
    ball.data.materials.append(build(e, ci, mi))
    fn = name.lower().replace(" ", "_")
    sc.render.filepath = os.path.join(out_dir, f"ball_{fn}.png")
    bpy.ops.render.render(write_still=True)
    print("@@JSON@@", {"ball": name, "file": sc.render.filepath})
