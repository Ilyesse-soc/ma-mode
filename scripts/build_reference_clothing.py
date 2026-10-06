"""Author fitted, reusable clothing in Blender; never overwrite source mannequins.

Run: blender --background --python scripts/build_reference_clothing.py -- male
Outputs: .tmp/reference-clothing/{sex}-clothes.glb and review PNGs.
All geometry is original project-authored work, in metres, for the supplied pose.
"""
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SEX = sys.argv[sys.argv.index("--") + 1]
assert SEX in {"male", "female"}
OUT = ROOT / ".tmp/reference-clothing"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT / f"apps/mobile/assets/3d/mannequins/{SEX}.glb"))
body_objects = list(bpy.context.scene.objects)
MALE = SEX == "male"
SHIFT = 0 if MALE else -.05
WIDTH = 1 if MALE else .87
parts = []
materials = {}


def point(x, h, depth):
    return (x, -depth, h)


def material(kind, detail="main", shade=1):
    name = f"cloth:{kind}:{detail}"
    if name in materials:
        return materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next((node for node in m.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        output = m.node_tree.nodes.new("ShaderNodeOutputMaterial")
        m.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    base = {"hoodie": .57, "tshirt": .72, "sweater": .45,
            "jacket": .022, "cargo": .025, "trousers": .035,
            "shorts": .06, "skirt": .06, "dress": .06,
            "sneakers": .82, "boots": .045}.get(kind, .5)
    if detail.startswith("fixed"):
        base = shade
        shade = 1
    bsdf.inputs["Base Color"].default_value = (base * shade,) * 3 + (1,)
    bsdf.inputs["Roughness"].default_value = .83 if kind != "sneakers" else .66
    bsdf.inputs["Metallic"].default_value = .35 if "zip" in detail else 0
    # Small baked textile variation, portable to glTF without shader baking.
    if detail == "main":
        image = bpy.data.images.new(name + "-weave", width=128, height=128)
        rng = random.Random(42)
        pixels = []
        for y in range(128):
            for x in range(128):
                value = .84 + rng.random() * .12 + (.035 if (x + y) % 2 else 0)
                pixels.extend((value, value, value, 1))
        image.pixels = pixels
        image.pack()
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        multiply = m.node_tree.nodes.new("ShaderNodeMixRGB")
        multiply.blend_type = "MULTIPLY"
        multiply.inputs[0].default_value = 1
        multiply.inputs[2].default_value = (base * shade,) * 3 + (1,)
        m.node_tree.links.new(tex.outputs["Color"], multiply.inputs[1])
        m.node_tree.links.new(multiply.outputs["Color"], bsdf.inputs["Base Color"])
        # glTF multiplies the texture by the material factor patched after export.
    materials[name] = m
    return m


def mesh(name, verts, faces, mat, thickness=.003, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    # Stable cylindrical UVs: no dynamic photograph projection or stretching.
    uv = data.uv_layers.new(name="UVMap")
    for polygon in data.polygons:
        for loop in polygon.loop_indices:
            v = data.vertices[data.loops[loop].vertex_index].co
            uv.data[loop].uv = (v.x * 5, v.z * 5)
    if thickness:
        modifier = obj.modifiers.new("Sewn fabric thickness", "SOLIDIFY")
        modifier.thickness = thickness
        modifier.offset = -1
    parts.append(obj)
    return obj


def loft(name, rings, mat, count=64, start=0, end=2 * math.pi, folds=.0015, cap=False):
    # rings: height, centre x, centre depth, horizontal radius, depth radius.
    closed = abs(end - start - 2 * math.pi) < .001
    steps = count if closed else count + 1
    verts = []
    for index, (h, cx, cz, rx, rz) in enumerate(rings):
        for j in range(steps):
            angle = start + (end - start) * j / count
            wrinkle = folds * math.sin(angle * 8 + index * .9)
            verts.append(point(cx + (rx + wrinkle) * math.sin(angle), h,
                               cz + (rz + wrinkle) * math.cos(angle)))
    faces = []
    for i in range(len(rings) - 1):
        for j in range(count if closed else count):
            nxt = (j + 1) % steps
            faces.append((i * steps + j, i * steps + nxt,
                          (i + 1) * steps + nxt, (i + 1) * steps + j))
    if cap and closed:
        faces.extend([tuple(range(steps - 1, -1, -1)),
                      tuple((len(rings) - 1) * steps + j for j in range(steps))])
    return mesh(name, verts, faces, mat)


def line(name, coords, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    poly = curve.splines.new("POLY")
    poly.points.add(len(coords) - 1)
    for p, co in zip(poly.points, coords):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def torso(kind, hem, opening=False, ease=0, short_sleeves=False):
    mat = material(kind)
    rings = [
        (hem + SHIFT, 0, -.009, (.183 if MALE else .188) + ease, .142 + ease),
        (1.08 + SHIFT, 0, .002, .172 * WIDTH + ease, .126 + ease),
        (1.18 + SHIFT, 0, .004, .170 * WIDTH + ease, .123 + ease),
        (1.30 + SHIFT, 0, .008, .198 * WIDTH + ease, .129 + ease),
        (1.40 + SHIFT, 0, .004, .215 * WIDTH + ease, .133 + ease),
        (1.468 + SHIFT, 0, 0, .219 * WIDTH + ease, .112 + ease),
        (1.550 + SHIFT, 0, 0, .077, .073),
    ]
    if opening:
        # Open bomber front: hoodie remains visible, including from oblique views.
        loft(kind + "-body", rings, mat, start=.42, end=2 * math.pi - .42)
        for side in [-1, 1]:
            a = .42 * side
            coords = [point(rx * math.sin(a), h, cz + rz * math.cos(a))
                      for h, _, cz, rx, rz in rings]
            line(kind + "-zip", coords, .0022, material(kind, "fixed-zip", .15))
    else:
        loft(kind + "-body", rings, mat, cap=True)
    # Sleeves follow the actual lowered arm pose, not horizontal capsule tubes.
    for side in [-1, 1]:
        sleeve = [
            (1.487 + SHIFT, side * .193 * WIDTH, -.004, .032 + ease, .063 + ease),
            (1.457 + SHIFT, side * .222 * WIDTH, -.004, .055 + ease, .078 + ease),
            (1.403 + SHIFT, side * .239 * WIDTH, -.005, .069 + ease, .083 + ease),
            (1.32 + SHIFT, side * .268 * WIDTH, -.006, .067 + ease, .077 + ease),
            (1.20 + SHIFT, side * .295 * WIDTH, -.005, .061 + ease, .066 + ease),
            (1.08 + SHIFT, side * .319 * WIDTH, -.003, .052 + ease, .057 + ease),
            (.955 + SHIFT, side * .333 * WIDTH, -.005, .044 + ease, .047 + ease),
        ]
        if short_sleeves:
            sleeve = sleeve[:4]
        loft(f"{kind}-sleeve-{side}", sleeve, mat, count=48, cap=True)
        h, cx, cz, rx, rz = sleeve[-1]
        cuff = [(h - .004, cx, cz, rx * .99, rz * .99),
                (h + .030, cx, cz, rx * 1.01, rz * 1.01)]
        loft(kind + "-cuff", cuff, material(kind, "trim", .75), count=48, folds=0)
    loft(kind + "-hem", [(hem + SHIFT, 0, -.009, rings[0][3], rings[0][4]),
                         (hem + SHIFT + .032, 0, -.009, rings[0][3], rings[0][4])],
         material(kind, "trim", .78), folds=0)
    return rings


def rounded_patch(kind, name, cx, h, depth, width, height):
    # Rounded fabric pocket with a flap and an actual stitched perimeter.
    mat = material(kind)
    radius = (.187 if MALE else .18) if kind in {"hoodie", "jacket"} else .092
    origin = 0 if kind in {"hoodie", "jacket"} else math.copysign(.097, cx)
    def on_surface(x, y):
        z = depth * math.sqrt(max(.10, 1 - ((x - origin) / radius) ** 2)) + .003
        return point(x, y, z)
    vertices = []
    faces = []
    for row in range(4):
        for col in range(7):
            vertices.append(on_surface(cx + (col / 6 - .5) * width,
                                       h + (row / 3 - .5) * height))
    for row in range(3):
        for col in range(6):
            a = row * 7 + col
            faces.append((a, a + 1, a + 8, a + 7))
    obj = mesh(name, vertices, faces, mat, .003, True)
    bevel = obj.modifiers.new("Rounded pocket edge", "BEVEL")
    bevel.width = .006
    bevel.segments = 3
    border = [on_surface(cx + dx * width / 2, h + dy * height / 2)
              for dx, dy in [(-1, -1), (1, -1), (1, 1), (-1, 1), (-1, -1)]]
    line(name + "-stitch", border, .0007,
         material(kind, "trim", .72))
    return obj


for kind, hem in [("tshirt", 1.00), ("sweater", .985), ("hoodie", .975)]:
    torso(kind, hem, short_sleeves=kind == "tshirt")
    if kind == "hoodie":
        rounded_patch(kind, "Kangaroo pocket", 0, 1.10 + SHIFT, .139, .20 * WIDTH, .102)
        # Hood lies on the upper back, leaving the original head untouched.
        loft("hoodie-hood", [
            (1.38 + SHIFT, 0, -.105, .081, .052),
            (1.44 + SHIFT, 0, -.109, .110, .065),
            (1.50 + SHIFT, 0, -.090, .119, .073),
            (1.552 + SHIFT, 0, -.051, .096, .058),
        ], material(kind), start=.9, end=2 * math.pi - .9)
        for side in [-1, 1]:
            line("hoodie-drawstring", [point(side * .048, 1.496 + SHIFT, .085),
                                      point(side * .054, 1.40 + SHIFT, .140)],
                 .002, material(kind, "fixed-cord", .76))
torso("jacket", .988, opening=True, ease=.015)
for side in [-1, 1]:
    rounded_patch("jacket", "Bomber pocket", side * .13 * WIDTH,
                  1.095 + SHIFT, .150, .064, .086)


def pants(kind, short=False):
    mat = material(kind)
    # Connected pelvis; separate tapered trouser legs start inside it.
    hip = .192 if MALE else .191
    loft(kind + "-pelvis", [
        (1.075 + SHIFT, 0, -.010, .172 if MALE else .158, .122),
        (1.01 + SHIFT, 0, -.014, hip, .158),
        (.935 + SHIFT, 0, -.018, hip, .158),
        (.855 + SHIFT, 0, -.005, .182, .128),
    ], mat, cap=True)
    for side in [-1, 1]:
        rings = [
            (.925 + SHIFT, side * .093, -.008, .094, .135),
            (.82 + SHIFT, side * .096, .005, .090, .116),
            (.72 + SHIFT, side * .098, .005, .081, .093),
            (.59 + SHIFT, side * .095, 0, .080, .096),
            (.46 + SHIFT, side * .092, -.003, .077, .096),
            (.33 + SHIFT, side * .091, -.002, .068, .065),
            (.22 + SHIFT, side * .094, -.001, .055, .050),
            (.16, side * .095, -.002, .046, .043),
        ]
        if short:
            rings = rings[:4]
        loft(kind + "-leg", rings, mat, count=48, folds=.0025, cap=True)
        h, x, z, rx, rz = rings[-1]
        loft(kind + "-cuff", [(h, x, z, rx, rz), (h + .025, x, z, rx * 1.025, rz)],
             material(kind, "trim", .8), count=48, folds=0)
        if kind == "cargo":
            rounded_patch(kind, "Cargo thigh pocket", side * .127, .70 + SHIFT,
                          .103, .095, .123)
            rounded_patch(kind, "Cargo pocket flap", side * .127, .764 + SHIFT,
                          .107, .099, .034)
    # Waistband, belt loops and small fly detail.
    loft(kind + "-waistband", [(1.055 + SHIFT, 0, -.01, .174 if MALE else .160, .124),
                              (1.085 + SHIFT, 0, -.01, .174 if MALE else .160, .124)],
         material(kind, "trim", .80), folds=0)


pants("cargo")
pants("trousers")
pants("shorts", short=True)
loft("skirt", [(1.07 + SHIFT, 0, -.01, .176, .133),
               (.94 + SHIFT, 0, -.01, .205, .166),
               (.79 + SHIFT, 0, 0, .226, .181),
               (.62 + SHIFT, 0, 0, .24, .192)], material("skirt"), folds=.002)
torso("dress", .97, short_sleeves=True)
loft("dress-skirt", [(1.02 + SHIFT, 0, -.01, .188, .148),
                     (.88 + SHIFT, 0, -.01, .205, .165),
                     (.73 + SHIFT, 0, 0, .227, .185),
                     (.57 + SHIFT, 0, 0, .245, .196)], material("dress"), folds=.002)

for kind in ["sneakers", "boots"]:
    for side in [-1, 1]:
        cx = side * .096
        # Anatomical last: elongated toes, rounded sides and flat layered sole.
        rings = [(.006, cx, .057, .062, .135), (.025, cx, .057, .064, .139),
                 (.047, cx, .057, .064, .139), (.069, cx, .052, .061, .132),
                 (.089, cx, .046, .059, .118), (.119, cx, .015, .052, .068),
                 (.161 if kind == "sneakers" else .235, cx, -.003, .044, .047)]
        loft(kind + "-upper", rings[2:], material(kind), count=48, folds=0)
        loft(kind + "-sole", rings[:3], material(kind, "fixed-sole", .82),
             count=48, folds=0)
        mesh(kind + "-sole-bottom", [point(cx + .062 * math.sin(j * math.tau / 48),
                                         .006, .057 + .135 * math.cos(j * math.tau / 48))
                                    for j in range(48)], [tuple(range(47, -1, -1))],
             material(kind, "fixed-sole", .82), 0)
        for i in range(5):
            h = .098 + i * .008
            depth = .109 - i * .011
            line(kind + "-lace", [point(cx - .027, h, depth),
                                  point(cx + .027, h + .002, depth - .006)],
                 .0017, material(kind, "fixed-laces", .72))

# Sew intersecting closed pattern panels offline, avoiding tube/diaper seams.
for kind in ["cargo", "trousers", "shorts", "hoodie", "sweater", "tshirt"]:
    panel_names = ([kind + "-pelvis", kind + "-leg"] if kind in {"cargo", "trousers", "shorts"}
                   else [kind + "-body", kind + "-sleeve"])
    panels = [obj for obj in parts if any(obj.name.startswith(prefix) for prefix in panel_names)]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in panels:
        for modifier in list(obj.modifiers):
            obj.modifiers.remove(modifier)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = panels[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    parts = [obj for obj in parts if obj not in panels] + [joined]
    joined.name = kind + "-sewn"
    remesh = joined.modifiers.new("Sewn continuous surface", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = .006
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth = joined.modifiers.new("Relax pattern seams", "SMOOTH")
    smooth.factor = .8
    smooth.iterations = 3
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate = joined.modifiers.new("Mobile topology", "DECIMATE")
    decimate.ratio = .06
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    for polygon in joined.data.polygons:
        polygon.use_smooth = True
    uv = joined.data.uv_layers.new(name="UVMap")
    for polygon in joined.data.polygons:
        for loop in polygon.loop_indices:
            v = joined.data.vertices[joined.data.loops[loop].vertex_index].co
            uv.data[loop].uv = (v.x * 5, v.z * 5)

# Export just authored garments; the packaging step appends original source bytes.
bpy.ops.object.select_all(action="DESELECT")
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.export_scene.gltf(filepath=str(OUT / f"{SEX}-clothes.glb"),
                          export_format="GLB", use_selection=True,
                          export_apply=True, export_materials="EXPORT")

# Review with the real original body and the reference combination only.
for obj in parts:
    kind = obj.data.materials[0].name.split(":")[1]
    obj.hide_render = kind not in {"hoodie", "jacket", "cargo", "sneakers"}
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.render.resolution_x = 600
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.world.color = (.08, .08, .08)
scene.view_settings.view_transform = "AgX"
for pos, power, size in [((2, -3, 4), 450, 3), ((-2, -1, 2), 280, 2), ((0, 2, 3), 350, 2)]:
    bpy.ops.object.light_add(type="AREA", location=pos)
    bpy.context.object.data.energy = power
    bpy.context.object.data.shape = "DISK"
    bpy.context.object.data.size = size
    bpy.context.object.rotation_euler = (Vector((0, 0, .95)) - bpy.context.object.location).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.camera_add(location=(.25, -4.2, 1.16))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, .91)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.03
scene.camera = camera
scene.render.film_transparent = False
scene.render.filepath = str(OUT / f"{SEX}-front.png")
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"{SEX}-review.blend"))
bpy.ops.render.render(write_still=True)
camera.location = (.7, 3.8, 1.15)
camera.rotation_euler = (Vector((0, 0, .91)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(OUT / f"{SEX}-back.png")
bpy.ops.render.render(write_still=True)
