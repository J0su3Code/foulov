# Icône FouLove : un cœur dans une bulle irisée, sur fond framboise (les mêmes éléments que l'intro).
#
#   blender -b --factory-startup -P icon_love.py -- --out render/icon
#
# Produit `foreground.png` (1024², fond transparent : premier plan de l'icône adaptative Android, dans la zone sûre)
# et `full.png` (icône complète, fond dégradé : iOS et anciens Android). Le fond seul est dessiné par make_icon.py.

import bpy, math, sys, os, argparse

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser(); ap.add_argument('--out', default='render/icon'); ap.add_argument('--samples', type=int, default=128)
A = ap.parse_args(argv)
HERE = os.path.dirname(os.path.abspath(__file__))


def lin(h):
    h = h.lstrip('#'); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4 for x in c) + (1.,)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.engine = 'CYCLES'
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for d in prefs.devices: d.use = d.type == 'METAL'
    sc.cycles.device = 'GPU'
except Exception:
    pass
sc.cycles.samples = A.samples; sc.cycles.use_denoising = True; sc.cycles.transparent_max_bounces = 32
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.render.film_transparent = True
sc.view_settings.view_transform = 'Khronos PBR Neutral'

cd = bpy.data.cameras.new('cam'); cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam); sc.camera = cam
cd.type = 'ORTHO'; cd.ortho_scale = 3.3                 # bulle (Ø 2,04) ≈ 62 % de la largeur : dans la zone sûre (66 %)
cam.location = (0, -5, 0); cam.rotation_euler = (math.radians(90), 0, 0)

w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; nt = w.node_tree
bg = nt.nodes['Background']; env = nt.nodes.new('ShaderNodeTexEnvironment')
env.image = bpy.data.images.load(os.path.join(HERE, 'assets', 'hdri', 'studio_small_09_2k.hdr'))
nt.links.new(env.outputs['Color'], bg.inputs['Color']); bg.inputs['Strength'].default_value = .9

# Cœur plein, crème lumineux.
K = 1.25 / 32; SHIFT = 2.2 * K


def heart_pt(s, side):
    t = math.pi * (1 - s) * side
    return (16 * math.sin(t) ** 3 * K, 0, (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * K + SHIFT)


right = [heart_pt(i / 300, 1) for i in range(301)]; left = [heart_pt(i / 300, -1) for i in range(301)]
contour = right + list(reversed(left))[1:-1]
me = bpy.data.meshes.new('coeur'); me.from_pydata(contour, [], [list(range(len(contour)))])
heart = bpy.data.objects.new('coeur', me); sc.collection.objects.link(heart)
sol = heart.modifiers.new('epaisseur', 'SOLIDIFY'); sol.thickness = .12; sol.offset = 0
bev = heart.modifiers.new('arrondi', 'BEVEL'); bev.width = .05; bev.segments = 6; bev.limit_method = 'ANGLE'
hm = bpy.data.materials.new('coeur'); hm.use_nodes = True; p = hm.node_tree.nodes['Principled BSDF']
p.inputs['Base Color'].default_value = lin('#FFF4F7'); p.inputs['Roughness'].default_value = .25
p.inputs['Coat Weight'].default_value = .6
p.inputs['Emission Color'].default_value = lin('#FFE3EC'); p.inputs['Emission Strength'].default_value = .55
heart.data.materials.append(hm)
for poly in heart.data.polygons: poly.use_smooth = True

# Bulle irisée (même construction que l'intro).
bm = bpy.data.materials.new('bulle'); bm.use_nodes = True; bn = bm.node_tree
for x in list(bn.nodes):
    if x.type != 'OUTPUT_MATERIAL': bn.nodes.remove(x)
lw = bn.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = .14
noise = bn.nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 1.8
ma = bn.nodes.new('ShaderNodeMath'); ma.operation = 'MULTIPLY_ADD'; ma.inputs[1].default_value = 1.7
bn.links.new(noise.outputs['Fac'], ma.inputs[0]); bn.links.new(lw.outputs['Facing'], ma.inputs[2])
fr = bn.nodes.new('ShaderNodeMath'); fr.operation = 'FRACT'; bn.links.new(ma.outputs[0], fr.inputs[0])
rain = bn.nodes.new('ShaderNodeValToRGB'); el = rain.color_ramp.elements
cols = ['#FFB3D1', '#FFE3A3', '#B8F2D8', '#A9D8FF', '#D6B8FF', '#FFB3D1']
el[0].position, el[0].color = 0., lin(cols[0]); el[1].position, el[1].color = 1., lin(cols[-1])
for k, c in enumerate(cols[1:-1], 1): e = el.new(k / 5); e.color = lin(c)
bn.links.new(fr.outputs[0], rain.inputs[0])
gl = bn.nodes.new('ShaderNodeBsdfGlossy'); gl.inputs['Roughness'].default_value = .03; bn.links.new(rain.outputs[0], gl.inputs['Color'])
tb = bn.nodes.new('ShaderNodeBsdfTransparent')
wg = bn.nodes.new('ShaderNodeMapRange'); wg.inputs['To Min'].default_value = .03; wg.inputs['To Max'].default_value = .9
bn.links.new(lw.outputs['Fresnel'], wg.inputs['Value'])
mx = bn.nodes.new('ShaderNodeMixShader'); bn.links.new(wg.outputs['Result'], mx.inputs[0])
bn.links.new(tb.outputs[0], mx.inputs[1]); bn.links.new(gl.outputs[0], mx.inputs[2])
em = bn.nodes.new('ShaderNodeEmission'); bn.links.new(rain.outputs[0], em.inputs['Color'])
emw = bn.nodes.new('ShaderNodeMath'); emw.operation = 'MULTIPLY'; emw.inputs[1].default_value = .5
bn.links.new(lw.outputs['Fresnel'], emw.inputs[0]); bn.links.new(emw.outputs[0], em.inputs['Strength'])
add = bn.nodes.new('ShaderNodeAddShader'); bn.links.new(mx.outputs[0], add.inputs[0]); bn.links.new(em.outputs[0], add.inputs[1])
bn.links.new(add.outputs[0], bn.nodes['Material Output'].inputs['Surface'])
bpy.ops.mesh.primitive_uv_sphere_add(radius=1.02, segments=128, ring_count=64)
bubble = bpy.context.active_object; bubble.data.materials.append(bm)
for poly in bubble.data.polygons: poly.use_smooth = True
bubble.rotation_euler = (.4, .8, .2)

li = bpy.data.lights.new('cle', 'AREA'); li.energy = 160; li.size = 3
lo = bpy.data.objects.new('cle', li); sc.collection.objects.link(lo); lo.location = (-1.5, -3, 2.5)
lo.rotation_euler = (math.radians(55), 0, math.radians(-25))

out = os.path.abspath(A.out); os.makedirs(out, exist_ok=True)
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
sc.render.filepath = os.path.join(out, 'foreground.png'); bpy.ops.render.render(write_still=True)
print('FOULOV_DONE')
