"""FouLov — intro cinématique « La première graine ».

Scène entièrement procédurale (aucun asset externe) :
graine qui tombe → deux tiges qui s'enlacent en poussant → feuilles → fleur qui éclot → pollen → caméra qui remonte
pour laisser la place au panneau d'accueil de l'app (la dernière image sert de fond à l'UI Flutter).

Usage :
  blender -b --factory-startup -P intro_garden.py -- --theme day --out render/day [--frames 20,100] [--res 540x1200] [--samples 40]
"""
import bpy, bmesh, math, random, sys, os, argparse
from mathutils import Vector

# ---------------------------------------------------------------- arguments
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument('--theme', default='day', choices=['day', 'night'])
ap.add_argument('--out', default='render/day')
ap.add_argument('--frames', default='')            # liste "20,100" pour des images fixes ; vide = animation complète
ap.add_argument('--range', default='')             # "112-225" : ne rend que ces images de l'animation (même numérotation)
ap.add_argument('--res', default='540x1200')
ap.add_argument('--samples', type=int, default=40)
ap.add_argument('--tbounces', type=int, default=64)   # traversées transparentes max (8 = ancien réglage, pour comparaison)
ap.add_argument('--fps', type=int, default=30)
A = ap.parse_args(argv)
NIGHT = A.theme == 'night'
FPS = A.fps
S = FPS / 30.0                                     # facteur temps : la chorégraphie est écrite en images à 30 i/s
F = lambda f: int(round(f * S))

random.seed(7)

# ---------------------------------------------------------------- utilitaires
def lin(hexstr):
    """sRGB hex -> linéaire (RGBA)."""
    h = hexstr.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*c, 1.0)

def setin(node, name, val):
    if name in node.inputs:
        node.inputs[name].default_value = val

def eout(t): return 1 - (1 - t) ** 3
def eio(t): return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def eback(t, s=1.70158): return 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2
def clamp(x, a=0., b=1.): return max(a, min(b, x))
def sstep_(a, b, x): t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t)

def principled(name, base, rough=.5, sss=0., sss_rad=(1, .4, .3), sss_scale=.01, sheen=0., coat=0., emit=None, emit_str=0., trans=0., ior=1.45):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    setin(b, 'Base Color', lin(base) if isinstance(base, str) else base)
    setin(b, 'Roughness', rough); setin(b, 'Subsurface Weight', sss); setin(b, 'Subsurface Radius', sss_rad)
    setin(b, 'Subsurface Scale', sss_scale); setin(b, 'Sheen Weight', sheen); setin(b, 'Coat Weight', coat)
    setin(b, 'Transmission Weight', trans); setin(b, 'IOR', ior)
    if emit: setin(b, 'Emission Color', lin(emit)); setin(b, 'Emission Strength', emit_str)
    return m, b

def ramp_on_uv_y(mat, bsdf, stops):
    """Dégradé de couleur le long de V (base → pointe) pour pétales et feuilles."""
    nt = mat.node_tree
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); cr = nt.nodes.new('ShaderNodeValToRGB')
    nt.links.new(tc.outputs['UV'], sep.inputs[0]); nt.links.new(sep.outputs['Y'], cr.inputs[0])
    els = cr.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], lin(stops[0][1])
    els[1].position, els[1].color = stops[-1][0], lin(stops[-1][1])
    for p, c in stops[1:-1]:
        e = els.new(p); e.color = lin(c)
    nt.links.new(cr.outputs['Color'], bsdf.inputs['Base Color'])

def add_bump(mat, bsdf, scale=60., strength=.15):
    nt = mat.node_tree
    n = nt.nodes.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value = scale
    bu = nt.nodes.new('ShaderNodeBump'); bu.inputs['Strength'].default_value = strength
    nt.links.new(n.outputs['Fac'], bu.inputs['Height']); nt.links.new(bu.outputs['Normal'], bsdf.inputs['Normal'])

def veins(mat, bsdf, kind):
    """Nervures : nervure centrale + nervures latérales en chevrons (feuille), stries radiales (pétale), fibres (tige)."""
    nt = mat.node_tree; N = nt.nodes.new; L = nt.links.new
    def mth(op, a, b=0., clampit=False):
        n = N('ShaderNodeMath'); n.operation = op; n.use_clamp = clampit
        (L(a, n.inputs[0]) if not isinstance(a, (int, float)) else n.inputs[0].__setattr__('default_value', a))
        (L(b, n.inputs[1]) if not isinstance(b, (int, float)) else n.inputs[1].__setattr__('default_value', b))
        return n.outputs[0]
    tc = N('ShaderNodeTexCoord'); sep = N('ShaderNodeSeparateXYZ'); L(tc.outputs['UV'], sep.inputs[0])
    u, v = sep.outputs['X'], sep.outputs['Y']
    if kind == 'stem':
        noise = N('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 900; L(tc.outputs['Object'], noise.inputs['Vector'])
        h = noise.outputs['Fac']
    else:
        du = mth('ABSOLUTE', mth('SUBTRACT', u, .5))
        if kind == 'leaf':
            mid = mth('SUBTRACT', 1., mth('DIVIDE', du, .025, True), True)
            lat = mth('SINE', mth('MULTIPLY', mth('ADD', v, mth('MULTIPLY', du, .55)), 6.283 * 9))
            lat = mth('POWER', mth('MAXIMUM', lat, 0.), 18.)
            h = mth('MAXIMUM', mid, mth('MULTIPLY', lat, .6))
        else:
            h = mth('POWER', mth('MAXIMUM', mth('SINE', mth('MULTIPLY', u, 6.283 * 16)), 0.), 10.)
            h = mth('MULTIPLY', h, mth('SUBTRACT', 1., mth('MULTIPLY', v, .6)))
        mix = N('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MIX'
        src_col = bsdf.inputs['Base Color'].links[0].from_socket if bsdf.inputs['Base Color'].is_linked else None
        if src_col: L(src_col, mix.inputs[6])
        else: mix.inputs[6].default_value = bsdf.inputs['Base Color'].default_value
        mix.inputs[7].default_value = lin('#E9F3C9') if kind == 'leaf' else lin('#FFF6F8')
        L(mth('MULTIPLY', h, .22), mix.inputs[0]); L(mix.outputs[2], bsdf.inputs['Base Color'])
    bu = N('ShaderNodeBump'); bu.inputs['Strength'].default_value = .25 if kind != 'stem' else .1; bu.inputs['Distance'].default_value = .0004
    L(h, bu.inputs['Height']); L(bu.outputs['Normal'], bsdf.inputs['Normal'])

def link(obj):
    bpy.context.scene.collection.objects.link(obj); return obj

def smooth(obj):
    for p in obj.data.polygons: p.use_smooth = True

def blade_mesh(name, length, width, nu, nv, profile, zfun):
    """Surface paramétrique (u∈[-1,1] travers, v∈[0,1] longueur) avec UV. Sert aux pétales et aux feuilles."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    grid = []
    for j in range(nv + 1):
        v = j / nv; row = []
        for i in range(nu + 1):
            u = -1 + 2 * i / nu; w = width * profile(v)
            row.append(bm.verts.new((u * w, v * length, zfun(u, v) )))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for k, (ii, jj) in enumerate(((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                f.loops[k][uv].uv = (ii / nu, jj / nv)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); smooth(ob)
    so = ob.modifiers.new('ep', 'SOLIDIFY'); so.thickness = .0012; so.offset = 0
    sd = ob.modifiers.new('sub', 'SUBSURF'); sd.levels = 1; sd.render_levels = 2
    return ob

# ---------------------------------------------------------------- scène
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for d in prefs.devices: d.use = d.type == 'METAL'
    sc.cycles.device = 'GPU'
except Exception as e:
    print('GPU indisponible, rendu CPU :', e)
sc.cycles.samples = A.samples
sc.cycles.use_denoising = True
try: sc.cycles.denoiser = 'OPENIMAGEDENOISE'
except Exception: pass
sc.cycles.max_bounces = 8; sc.cycles.transmission_bounces = 8
# Chaque contour de pétale ou de feuille découpé par l'alpha compte comme une traversée transparente. Dans le bouton,
# un rayon en franchit plus de 8 (valeur par défaut) : au-delà, Cycles renvoie du noir → rectangle sombre derrière la fleur.
sc.cycles.transparent_max_bounces = A.tbounces
rx, ry = map(int, A.res.split('x'))
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = rx, ry, 100
sc.render.fps = FPS
sc.render.use_motion_blur = True; sc.render.motion_blur_shutter = .4
for vt in ('AgX', 'Filmic'):
    try: sc.view_settings.view_transform = vt; sc.view_settings.exposure = -.25; break
    except Exception: pass
for lk in ('AgX - Medium High Contrast', 'Medium High Contrast'):
    try: sc.view_settings.look = lk; break
    except Exception: pass

END = F(225)
sc.frame_start, sc.frame_end = 1, END

PAL = dict(
    day=dict(world='#0E2A1F', world_str=.55, key=(1., .93, .84), key_w=26, rim=lin('#FFC9D8')[:3], rim_w=40, fill=lin('#9FD3B0')[:3], fill_w=2.5,
             petal=[(0, '#FFE3EC'), (.3, '#F49AB9'), (1, '#D9447A')], stemA='#33573A', stemB='#4B7040', leafA='#2F5E34', leafB='#5A8C3E',
             pollen='#F2D27A', soil='#2A1F17', ground='#0B1C15'),
    night=dict(world='#0A0710', world_str=.35, key=(.72, .78, 1.), key_w=12, rim=lin('#FF9E7A')[:3], rim_w=55, fill=lin('#6E4C8A')[:3], fill_w=5,
               petal=[(0, '#FFE6DA'), (.35, '#FFB08A'), (1, '#FF5C8A')], stemA='#2E5546', stemB='#41705A', leafA='#2A5A55', leafB='#3F7F74',
               pollen='#FFD38A', soil='#1A1218', ground='#08060C'),
)[A.theme]

# monde
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes['Background']; bg.inputs['Color'].default_value = lin(PAL['world']); bg.inputs['Strength'].default_value = PAL['world_str']

# ---------------------------------------------------------------- sol (texture scannée Poly Haven, CC0)
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')
def append(blend, mats=(), objs=()):
    before = set(bpy.data.images)
    with bpy.data.libraries.load(os.path.join(ASSETS, blend), link=False) as (src, dst):
        dst.materials = [m for m in src.materials if m in mats]; dst.objects = [o for o in src.objects if o in objs]
    base = os.path.dirname(os.path.join(ASSETS, blend))
    for im in set(bpy.data.images) - before:
        if im.filepath.startswith('//'): im.filepath = os.path.join(base, im.filepath[2:])
    return dst
MOUND_H = .022
bpy.ops.mesh.primitive_grid_add(x_subdivisions=260, y_subdivisions=260, size=1.8)
gnd = bpy.context.active_object; gnd.name = 'ground'
for v in gnd.data.vertices:
    r = v.co.xy.length
    v.co.z = MOUND_H * math.exp(-(r / .11) ** 2) + .004 * math.sin(v.co.x * 23) * math.cos(v.co.y * 19)
smooth(gnd)
d = append('brown_mud_leaves_01/brown_mud_leaves_01_2k.blend', mats=['brown_mud_leaves_01'])
gmat = bpy.data.materials['brown_mud_leaves_01']; gnd.data.materials.append(gmat)
try: gmat.displacement_method = 'BOTH'
except Exception: pass
for n in gmat.node_tree.nodes:                     # échelle réaliste : ~0,9 m par répétition
    if n.type == 'MAPPING': n.inputs['Scale'].default_value = (2.6, 2.6, 2.6)
    if n.type == 'DISPLACEMENT': n.inputs['Scale'].default_value = .012
for n in list(gmat.node_tree.nodes):              # assombrir et réchauffer la terre (sol humide)
    if n.type == 'BSDF_PRINCIPLED' and n.inputs['Base Color'].is_linked:
        src = n.inputs['Base Color'].links[0].from_socket
        hsv = gmat.node_tree.nodes.new('ShaderNodeHueSaturation')
        hsv.inputs['Value'].default_value = .62 if not NIGHT else .4; hsv.inputs['Saturation'].default_value = 1.15
        gmat.node_tree.links.new(src, hsv.inputs['Color']); gmat.node_tree.links.new(hsv.outputs['Color'], n.inputs['Base Color'])
bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, -.003))     # grand sol de fond : pas de bord visible à l'horizon
far = bpy.context.active_object; far.name = 'ground_far'
fmat = gmat.copy(); fmat.name = 'ground_far'
for n in fmat.node_tree.nodes:
    if n.type == 'HUE_SAT': n.inputs['Value'].default_value = .22 if not NIGHT else .14
far.data.materials.append(fmat)
for o in (far,):
    for uvd in o.data.uv_layers.active.data: uvd.uv = (uvd.uv[0] * 5.5, uvd.uv[1] * 5.5)
# décor : touffes d'herbe et fougères réelles, floues au second plan
append('grass_medium_01/grass_medium_01_2k.blend', objs=[f'grass_medium_01_geonodes_{k}_LOD0' for k in ('large_a', 'large_b', 'large_c', 'mid_a')])
append('fern_02/fern_02_2k.blend', objs=['fern_02_a', 'fern_02_b', 'fern_02_d'])
grass_src = [o for o in bpy.data.objects if o.name.startswith('grass_medium_01_geonodes')]
fern_src = [o for o in bpy.data.objects if o.name.startswith('fern_02')]
def place(src, loc, scale, rotz):
    o = src.copy(); o.location = loc; o.scale = (scale,) * 3; o.rotation_euler = (0, 0, rotz); link(o); return o
for i in range(34):
    ang = random.random() * math.tau; r = random.uniform(.13, .7)
    x, y = math.cos(ang) * r, math.sin(ang) * r
    if y < -.05 and abs(x) < .16: continue                     # garder la vue dégagée devant la tige
    sc_g = random.uniform(.45, .9) * (.75 if y < 0 else 1.15)
    place(random.choice(grass_src), (x, y, .003), sc_g, random.random() * math.tau)
for i, (x, y, k) in enumerate(((-.42, .55, .55), (.38, .7, .6), (.05, .95, .7), (-.15, .42, .35), (.55, .3, .4))):
    place(fern_src[i % len(fern_src)], (x, y, 0), k, random.random() * math.tau)
for i in range(150):                                            # prairie de fond : masque l'horizon quand la caméra s'élève
    y = random.uniform(.65, 3.2); x = random.uniform(-1, 1) * (.55 + y * .7)
    place(random.choice(grass_src), (x, y, -.002), random.uniform(1.0, 1.7) * (1 + y * .15), random.random() * math.tau)
for i in range(12):
    y = random.uniform(.9, 2.6); x = random.uniform(-1, 1) * (.4 + y * .6)
    place(random.choice(fern_src), (x, y, -.002), random.uniform(.6, 1.05), random.random() * math.tau)
for o in grass_src + fern_src: bpy.context.scene.collection.objects.unlink(o) if o.name in bpy.context.scene.collection.objects else None
ms = gmat

# ---------------------------------------------------------------- graine
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=.011, location=(0, 0, .6))
seed = bpy.context.active_object; seed.name = 'seed'; seed.scale = (1, 1, 1.35); smooth(seed)
mseed, bseed = principled('seed', '#C9962E', rough=.35, coat=.4); add_bump(mseed, bseed, 300, .2); seed.data.materials.append(mseed)
GROUND_Z = MOUND_H + .013
for f in range(1, F(60) + 1):
    t = f / S
    if t <= 26:   z = .62 - (.62 - GROUND_Z) * (t / 26) ** 2
    elif t <= 38: z = GROUND_Z + .028 * math.sin((t - 26) / 12 * math.pi)
    elif t <= 44: z = GROUND_Z + .008 * math.sin((t - 38) / 6 * math.pi)
    else:         z = GROUND_Z - .032 * eout(clamp((t - 44) / 14))       # s'enfonce dans la terre
    seed.location.z = z; seed.rotation_euler.y = t * .05; seed.keyframe_insert('location', frame=f); seed.keyframe_insert('rotation_euler', frame=f)

# ---------------------------------------------------------------- tiges enlacées
H, R0, BASE_Z = .30, .017, MOUND_H - .004
STEM0, STEMD = 46, 96                                    # début / durée de la pousse (images @30)
def helix(s, ph):
    r = R0 * min(1, s * 6) * (1 - s) ** .55
    a = s * math.tau * 1.25 + ph
    return Vector((math.cos(a) * r, math.sin(a) * r, BASE_Z + s * H))
def grow(t):                                               # progression 0→1 de la pousse à l'instant t (images @30)
    return eout(clamp((t - STEM0) / STEMD))

stems = []
for k, (ph, col) in enumerate(((0, PAL['stemA']), (math.pi, PAL['stemB']))):
    cu = bpy.data.curves.new(f'stem{k}', 'CURVE'); cu.dimensions = '3D'
    cu.bevel_depth = .0031; cu.bevel_resolution = 6; cu.use_fill_caps = True
    cu.bevel_factor_mapping_end = 'SPLINE'
    sp = cu.splines.new('NURBS'); N = 90; sp.points.add(N - 1); sp.order_u = 4; sp.use_endpoint_u = True
    for i in range(N):
        s = i / (N - 1); p = helix(s, ph); sp.points[i].co = (p.x, p.y, p.z, 1); sp.points[i].radius = 1.15 - .65 * s
    ob = link(bpy.data.objects.new(f'stem{k}', cu))
    m, b = principled(f'stem{k}', col, rough=.68, sss=.15, sss_rad=(.4, 1, .3), sss_scale=.002); setin(b, 'Specular IOR Level', .3); setin(b, 'Sheen Weight', .6); setin(b, 'Sheen Roughness', .35); veins(m, b, 'stem')
    ob.data.materials.append(m)
    for f in range(1, END + 1):
        cu.bevel_factor_end = grow(f / S); cu.keyframe_insert('bevel_factor_end', frame=f)
    for fc in (cu.animation_data.action.fcurves if hasattr(cu.animation_data.action, 'fcurves') else []):
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
    stems.append((ob, ph))

def frame_at_growth(g):                                    # inverse de grow() → image @30
    return STEM0 + STEMD * (1 - (1 - g) ** (1 / 3))

# ---------------------------------------------------------------- matières botaniques (textures générées par texgen.py)
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'textures')
def tex_node(nt, name, noncolor=False):
    n = nt.nodes.new('ShaderNodeTexImage'); n.image = bpy.data.images.load(os.path.join(TEX, name), check_existing=True)
    if noncolor: n.image.colorspace_settings.name = 'Non-Color'
    return n
def botanical_mat(name, albedo, normal, trans, trans_w, sss_rad, rough_tex=None, rough_val=.4, sheen=0., nstr=1., sss=.25):
    """Face : Principled (albédo, relief, rugosité) + lumière traversante (Translucent) + découpe alpha du contour."""
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    b = nt.nodes['Principled BSDF']; out = nt.nodes['Material Output']
    ta = tex_node(nt, albedo); Lk(ta.outputs['Color'], b.inputs['Base Color'])
    tn = tex_node(nt, normal, True); nm = N('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value = nstr
    Lk(tn.outputs['Color'], nm.inputs['Color']); Lk(nm.outputs['Normal'], b.inputs['Normal'])
    if rough_tex: tr = tex_node(nt, rough_tex, True); Lk(tr.outputs['Color'], b.inputs['Roughness'])
    else: b.inputs['Roughness'].default_value = rough_val
    setin(b, 'Specular IOR Level', .28); setin(b, 'Specular Tint', (.55, .75, .4, 1))
    setin(b, 'Subsurface Weight', sss); setin(b, 'Subsurface Radius', sss_rad); setin(b, 'Subsurface Scale', .0015); setin(b, 'Sheen Weight', sheen)
    tt = N('ShaderNodeBsdfTranslucent'); tc = tex_node(nt, trans); Lk(tc.outputs['Color'], tt.inputs['Color']); Lk(nm.outputs['Normal'], tt.inputs['Normal'])
    mx = N('ShaderNodeMixShader'); mx.inputs[0].default_value = trans_w; Lk(b.outputs[0], mx.inputs[1]); Lk(tt.outputs[0], mx.inputs[2])
    tp = N('ShaderNodeBsdfTransparent'); mx2 = N('ShaderNodeMixShader')
    Lk(ta.outputs['Alpha'], mx2.inputs[0]); Lk(tp.outputs[0], mx2.inputs[1]); Lk(mx.outputs[0], mx2.inputs[2])
    Lk(mx2.outputs[0], out.inputs['Surface'])
    return m

def add_shape(ob, name, fn):
    """Ajoute une clé de forme : fn(x, y, z) -> (x, y, z) appliquée aux sommets de base."""
    if not ob.data.shape_keys: ob.shape_key_add(name='Basis')
    k = ob.shape_key_add(name=name)
    for i, v in enumerate(ob.data.vertices): k.data[i].co = fn(*v.co)
    return k

# tiges : brun-rouge à la base, vert plus tendre vers le haut
for ob, _ in stems:
    m = ob.data.materials[0]; nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); sp_ = nt.nodes.new('ShaderNodeSeparateXYZ'); cr = nt.nodes.new('ShaderNodeValToRGB')
    nt.links.new(tc.outputs['Generated'], sp_.inputs[0]); nt.links.new(sp_.outputs['Z'], cr.inputs[0])
    cr.color_ramp.elements[0].position, cr.color_ramp.elements[0].color = 0, lin('#5B3F2A' if not NIGHT else '#3A2A34')
    cr.color_ramp.elements[1].position, cr.color_ramp.elements[1].color = 1, lin(PAL['stemB'])
    e = cr.color_ramp.elements.new(.18); e.color = lin(PAL['stemA'])
    nt.links.new(cr.outputs['Color'], b.inputs['Base Color'])

# ---------------------------------------------------------------- feuilles (se déplient en poussant)
mleaf = botanical_mat('leaf', 'leaf_albedo.png', 'leaf_normal.png', 'leaf_trans.png', .24, (.3, 1, .15), rough_val=.68, nstr=1.0)
def leaf_obj(name, L):
    Wd = .17 * L
    ob = blade_mesh(name, L, Wd, 18, 34, lambda v: 1.0,
                    lambda u, v: .13 * abs(u) * Wd - .17 * v * v * L + .025 * Wd * math.sin(v * 15 + u * 2) * u * u)
    th = math.radians(72)
    add_shape(ob, 'fold', lambda x, y, z: (math.copysign(abs(x) * math.cos(th), x), y, abs(x) * math.sin(th) + z * .3))
    return ob
LEAVES = [(.16, 0, 1), (.27, 1, -1), (.40, 0, -1), (.52, 1, 1), (.64, 0, 1), (.75, 1, -1)]
for i, (s, k, side) in enumerate(LEAVES):
    ob = link(leaf_obj(f'leaf{i}', .095 * (1 - s * .42)))
    ob.data.materials.append(mleaf)
    p = helix(s, stems[k][1]); a = math.atan2(p.y, p.x) if p.xy.length > 1e-5 else stems[k][1]
    a += side * .35
    ob.location = p; ob.rotation_euler = (math.radians(30 + 12 * random.random()), 0, a - math.pi / 2)
    f0 = frame_at_growth(s); kf = ob.data.shape_keys.key_blocks['fold']
    for f in range(1, END + 1):
        t = f / S; g = clamp((t - f0) / 18)
        sc_ = eback(g, 1.1) if g > 0 else 0.0001
        ob.scale = (sc_, sc_, sc_)
        ob.rotation_euler.y = math.sin(t * .09 + i) * .03 * g
        kf.value = 1 - eout(clamp((t - f0 - 4) / 26))
        ob.keyframe_insert('scale', frame=f); ob.keyframe_insert('rotation_euler', frame=f); kf.keyframe_insert('value', frame=f)

# gouttes de rosée sur deux feuilles
mdew, _ = principled('dew', '#FFFFFF', rough=0, trans=1, ior=1.33)
for i in (1, 3):
    lf = bpy.data.objects[f'leaf{i}']; Ll = .095 * (1 - LEAVES[i][0] * .42)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=.0024, location=(.004, Ll * .45, .0032 - .17 * .45 ** 2 * Ll))
    d = bpy.context.active_object; d.scale = (1, 1, .65); d.parent = lf; d.data.materials.append(mdew); smooth(d)

# ---------------------------------------------------------------- fleur (bouton serré → éclosion)
TOP = helix(1, 0)
flower = link(bpy.data.objects.new('flower', None)); flower.location = TOP + Vector((0, 0, .002))
mpet = botanical_mat('petal', f'petal_{A.theme}_albedo.png', 'petal_normal.png', f'petal_{A.theme}_trans.png', .42, (1, .35, .45), rough_val=.48, sheen=.45, nstr=.6, sss=.3)
def petal_obj(name, L):
    Wd = .25 * L
    ob = blade_mesh(name, L, Wd, 16, 34, lambda v: 1.0,
                    lambda u, v: .26 * u * u * Wd - .12 * v ** 3 * L + .10 * Wd * math.sin(u * 8.5 + v * 6) * v ** 1.6 * (.35 + abs(u)) + .03 * Wd * math.sin(v * 21) * abs(u) ** 3)
    th = math.radians(62)
    add_shape(ob, 'bud', lambda x, y, z: (math.copysign(abs(x) * math.cos(th), x), y * .92, abs(x) * math.sin(th) + .30 * (y / L) ** 2 * L))
    return ob
BLOOM0, BLOOMD = 138, 50
petals = []
for ring, (n, L, open_deg, delay, off) in enumerate(((8, .088, 11, 0, 0), (5, .045, 38, 7, math.pi / 5))):
    for i in range(n):
        piv = link(bpy.data.objects.new(f'piv{ring}_{i}', None)); piv.parent = flower
        piv.rotation_euler.z = off + i / n * math.tau + random.uniform(-.07, .07)
        pe = link(petal_obj(f'petal{ring}_{i}', L * random.uniform(.93, 1.07))); pe.parent = piv
        pe.data.materials.append(mpet); kb = pe.data.shape_keys.key_blocks['bud']
        closed, opened = math.radians(84 - ring * 4), math.radians(open_deg + random.uniform(-5, 5))
        twist = random.uniform(-.08, .08)
        for f in range(1, END + 1):
            t = f / S; g = clamp((t - BLOOM0 - delay - i * 1.6) / BLOOMD)
            e = eback(g, 1.05)
            pe.rotation_euler = (closed + (opened - closed) * e, twist * e, 0)
            kb.value = 1 - eout(clamp(g * 1.15))
            k = .3 + .7 * eout(clamp((t - (STEM0 + STEMD * .78)) / 34))       # le bouton gonfle avant d'éclore
            pe.scale = (k, k, k)
            pe.keyframe_insert('rotation_euler', frame=f); pe.keyframe_insert('scale', frame=f); kb.keyframe_insert('value', frame=f)
        petals.append(pe)
# cœur : disque de fleurons en phyllotaxie (angle d'or), comme un vrai cosmos
from mathutils import Matrix
bm = bmesh.new(); RC = .0105; NFL = 220
for i in range(NFL):
    r = RC * math.sqrt((i + .5) / NFL); a = i * 2.399963
    z = .0062 * (1 - (r / RC) ** 2)
    rr = .00062 * (1.25 - .45 * r / RC)
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=rr, matrix=Matrix.Translation((math.cos(a) * r, math.sin(a) * r, z)))
me = bpy.data.meshes.new('florets'); bm.to_mesh(me); bm.free()
core = link(bpy.data.objects.new('florets', me)); core.parent = flower; smooth(core)
mcore, bcore = principled('florets', '#F2B630', rough=.55, sss=.25, sss_rad=(1, .7, .2), sss_scale=.001)
nt = mcore.node_tree; tc = nt.nodes.new('ShaderNodeTexCoord'); vl = nt.nodes.new('ShaderNodeVectorMath'); vl.operation = 'LENGTH'
cr = nt.nodes.new('ShaderNodeValToRGB'); nt.links.new(tc.outputs['Object'], vl.inputs[0]); nt.links.new(vl.outputs['Value'], cr.inputs[0])
cr.color_ramp.elements[0].position, cr.color_ramp.elements[0].color = 0, lin('#9AA43A')
cr.color_ramp.elements[1].position, cr.color_ramp.elements[1].color = .0105, lin('#E58A1E')
e = cr.color_ramp.elements.new(.005); e.color = lin('#F2C230')
nt.links.new(cr.outputs['Color'], bcore.inputs['Base Color'])
core.data.materials.append(mcore)
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=RC * 1.02, depth=.003, location=(0, 0, -.0012))
rec = bpy.context.active_object; rec.parent = flower; smooth(rec)
msep, _ = principled('sepal', PAL['stemA'], rough=.62, sss=.2, sss_rad=(.4, 1, .3), sss_scale=.002, sheen=.4)
rec.data.materials.append(msep)
for i in range(5):                                              # sépales : tiennent le bouton fermé puis se rabattent
    piv = link(bpy.data.objects.new(f'sep_piv{i}', None)); piv.parent = flower; piv.rotation_euler.z = i / 5 * math.tau + .3
    sp_o = link(leaf_obj(f'sepal{i}', .026)); sp_o.parent = piv; sp_o.location = (0, RC * .7, -.002)
    sp_o.data.materials.append(mleaf); sk = sp_o.data.shape_keys.key_blocks['fold']
    for f in range(1, END + 1):
        t = f / S; g = clamp((t - BLOOM0 + 8) / 44)
        sp_o.rotation_euler.x = math.radians(78) + (math.radians(-38) - math.radians(78)) * eout(g)
        sk.value = .6 * (1 - g)
        sp_o.keyframe_insert('rotation_euler', frame=f); sk.keyframe_insert('value', frame=f)
# la fleur entière : apparition du bouton puis léger balancement
for f in range(1, END + 1):
    t = f / S; g = clamp((t - (STEM0 + STEMD * .72)) / 20)
    flower.scale = (max(g, .0001),) * 3
    flower.rotation_euler = (math.sin(t * .07) * .04, math.cos(t * .05) * .04, t * .004)
    flower.keyframe_insert('scale', frame=f); flower.keyframe_insert('rotation_euler', frame=f)

# ---------------------------------------------------------------- pollen
POL_MATS = []
for j in range(4):                                     # 4 matières décalées : scintillement irrégulier, comme de vraies lucioles
    m = bpy.data.materials.new(f'pollen{j}'); m.use_nodes = True
    nt = m.node_tree; nt.nodes.remove(nt.nodes['Principled BSDF'])
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = lin(PAL['pollen'])
    nt.links.new(em.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
    peak = (8 if not NIGHT else 14) * random.uniform(.7, 1.2)
    for f in range(1, END + 1, max(1, F(3))):
        t = f / S; on = sstep_(140 + j * 6, 185 + j * 6, t)
        flick = 1 if not NIGHT else .55 + .45 * math.sin(t * (.21 + .07 * j) + j * 1.7) ** 2
        em.inputs['Strength'].default_value = peak * on * flick; em.inputs['Strength'].keyframe_insert('default_value', frame=f)
    POL_MATS.append(m)
for i in range(46 if not NIGHT else 70):
    c = Vector((random.uniform(-.32, .32), random.uniform(-.25, .35), random.uniform(.05, .6)))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=random.uniform(.0006, .0016) * (1.3 if NIGHT else 1), location=c)
    p = bpy.context.active_object; p.data.materials.append(POL_MATS[i % 4])
    ph = random.random() * math.tau; sp_ = random.uniform(.6, 1.4)
    for f in range(1, END + 1, max(1, F(3))):
        t = f / S
        p.location = c + Vector((math.sin(t * .02 * sp_ + ph) * .03, math.cos(t * .017 * sp_ + ph) * .02, t * .0006 * sp_ + math.sin(t * .03 + ph) * .01))
        p.keyframe_insert('location', frame=f)

# ---------------------------------------------------------------- lumières
def area(name, loc, rot, color, power, size):
    l = bpy.data.lights.new(name, 'AREA'); l.color = color; l.energy = power; l.size = size
    o = link(bpy.data.objects.new(name, l)); o.location = loc; o.rotation_euler = rot; return o
def spot(name, loc, target, color, power, angle=45):
    l = bpy.data.lights.new(name, 'SPOT'); l.color = color; l.energy = power; l.spot_size = math.radians(angle); l.spot_blend = .8
    o = link(bpy.data.objects.new(name, l)); o.location = loc
    c = o.constraints.new('TRACK_TO'); c.target = target; c.track_axis = 'TRACK_NEGATIVE_Z'; c.up_axis = 'UP_Y'; return o
tgt = link(bpy.data.objects.new('target', None)); tgt.location = (0, 0, .2)
area('key', (-.55, -.6, .9), (math.radians(50), 0, math.radians(-40)), PAL['key'], PAL['key_w'], .6)
spot('rim', (.15, .7, .75), tgt, PAL['rim'], PAL['rim_w'] * .45, 40)
area('fill', (.8, -.3, .3), (math.radians(80), 0, math.radians(70)), PAL['fill'], PAL['fill_w'], 1.2)
sun = bpy.data.lights.new('sun', 'SUN'); sun.angle = math.radians(3)
sun.color = lin('#FFD9A8')[:3] if not NIGHT else lin('#A9B8FF')[:3]; sun.energy = 3.2 if not NIGHT else .5
so = link(bpy.data.objects.new('sun', sun)); so.rotation_euler = (math.radians(-70), 0, math.radians(18))
if NIGHT:   # lueur chaude depuis la fleur, comme une veilleuse
    l = bpy.data.lights.new('glow', 'POINT'); l.color = lin('#FF9E7A')[:3]; l.shadow_soft_size = .02
    gl = link(bpy.data.objects.new('glow', l)); gl.parent = flower; gl.location = (0, 0, .015)
    for f, v in ((1, 0), (F(160), 0), (F(200), 1.6), (END, 1.6)):
        l.energy = v; l.keyframe_insert('energy', frame=f)

# ---------------------------------------------------------------- caméra
cam_d = bpy.data.cameras.new('cam'); cam_d.lens = 40; cam_d.sensor_fit = 'VERTICAL'; cam_d.sensor_height = 24
cam_d.dof.use_dof = True; cam_d.dof.aperture_fstop = 2.0
cam = link(bpy.data.objects.new('cam', cam_d)); sc.camera = cam
c = cam.constraints.new('TRACK_TO'); c.target = tgt; c.track_axis = 'TRACK_NEGATIVE_Z'; c.up_axis = 'UP_Y'
for f in range(1, END + 1):
    t = f / S
    follow = eio(clamp((t - 34) / 140))                    # le cadre suit la pousse
    u = eio(clamp((t - 190) / 35))                          # fin : léger travelling avant, fleur dans le tiers haut
    crane = eio(clamp((t - 60) / 150))                      # la caméra s'élève avec la plante : finit légèrement au-dessus de la fleur
    cam.location = (math.sin(t * .006) * .04, -.95 + .04 * follow + .06 * u, .10 + .34 * crane)
    tgt.location = (0, 0, .045 + .155 * follow)
    fz = BASE_Z + H * clamp(grow(t), .0, .85)
    cam_d.dof.focus_distance = (cam.location - Vector((0, 0, fz))).length
    cam.keyframe_insert('location', frame=f); tgt.keyframe_insert('location', frame=f); cam_d.dof.keyframe_insert('focus_distance', frame=f)

# éclairage d'ambiance réel (HDRI forêt / nuit) visible seulement dans les reflets, fond caméra sombre à la couleur de la marque
nt = w.node_tree; env = nt.nodes.new('ShaderNodeTexEnvironment')
env.image = bpy.data.images.load(os.path.join(ASSETS, 'hdri', 'dikhololo_night_2k.hdr' if NIGHT else 'epping_forest_01_2k.hdr'))
bgh = nt.nodes.new('ShaderNodeBackground'); bgh.inputs['Strength'].default_value = .18 if NIGHT else .35
nt.links.new(env.outputs['Color'], bgh.inputs['Color'])
lp = nt.nodes.new('ShaderNodeLightPath'); mx = nt.nodes.new('ShaderNodeMixShader')
nt.links.new(lp.outputs['Is Camera Ray'], mx.inputs[0]); nt.links.new(bgh.outputs[0], mx.inputs[1]); nt.links.new(bg.outputs[0], mx.inputs[2])
nt.links.new(mx.outputs[0], nt.nodes['World Output'].inputs['Surface'])
# brume légère pour donner de la profondeur et des rayons
vm = bpy.data.materials.new('haze'); vm.use_nodes = True; vn = vm.node_tree
vn.nodes.remove(vn.nodes['Principled BSDF']); pv = vn.nodes.new('ShaderNodeVolumePrincipled')
pv.inputs['Density'].default_value = .12 if NIGHT else .07; pv.inputs['Color'].default_value = lin('#B8D2BF' if not NIGHT else '#9C86C0')
vn.links.new(pv.outputs[0], vn.nodes['Material Output'].inputs['Volume'])
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, .2, .45)); hz = bpy.context.active_object; hz.name = 'haze'; hz.scale = (2.4, 2.4, 1.0); hz.data.materials.append(vm)
sc.cycles.volume_step_rate = 4; sc.cycles.volume_bounces = 0

# ---------------------------------------------------------------- rendu
out = os.path.abspath(A.out); os.makedirs(out, exist_ok=True)
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGB'
if A.frames:
    for fr in [int(x) for x in A.frames.split(',')]:
        sc.frame_set(F(fr)); sc.render.filepath = os.path.join(out, f'still_{fr:04d}.png')
        bpy.ops.render.render(write_still=True)
else:
    if A.range:
        a, b = (F(int(x)) for x in A.range.split('-'))
        sc.frame_start, sc.frame_end = a, b
    sc.render.filepath = os.path.join(out, '')
    bpy.ops.render.render(animation=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, f'intro_{A.theme}.blend'))
print('FOULOV_DONE')
