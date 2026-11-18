# Intro FouLove « une bulle à deux » : deux lumières dansent, dessinent un cœur, et une bulle irisée les enveloppe.
#
#   blender -b --factory-startup -P intro_love.py -- --theme day --out render/love_day --samples 64
#
# Tout est généré par code. Seul élément externe : l'éclairage de studio CC0 « Studio Small 09 » (Poly Haven,
# Sergej Majboroda), visible uniquement dans les reflets de la bulle.
#
# Chorégraphie (images à 30 i/s, 225 images = 7,5 s) :
#   1–24     le fond s'éclaire, des lueurs floues flottent
#   10–70    une lumière rose (à gauche) et une lumière or (à droite) entrent en traînant une comète
#   70       elles se touchent à la pointe du cœur : étincelles
#   70–150   chacune dessine une moitié du cœur, en remontant
#   150      elles se retrouvent au creux du cœur : éclat, le cœur s'illumine
#   165–205  une bulle irisée se gonfle autour du cœur
#   190–225  la bulle monte doucement dans le tiers haut : place libre pour le panneau d'accueil

import bpy, math, random, sys, os, argparse
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument('--theme', default='day', choices=['day', 'night'])
ap.add_argument('--out', default='render/love_day')
ap.add_argument('--frames', default='')   # « 40,120,225 » : images fixes ; vide = animation complète
ap.add_argument('--range', default='')    # « 100-225 » : seulement ces images
ap.add_argument('--res', default='540x1200')
ap.add_argument('--samples', type=int, default=48)
A = ap.parse_args(argv)
NIGHT = A.theme == 'night'
HERE = os.path.dirname(os.path.abspath(__file__))
END = 225


def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4 for x in c) + (1.,)


def clamp(x, a=0., b=1.): return max(a, min(b, x))
def eio(t): t = clamp(t); return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def eout(t): t = clamp(t); return 1 - (1 - t) ** 3
def eback(t, s=1.4): t = clamp(t); return 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2
def ramp(f, a, b): return clamp((f - a) / (b - a))


# ---------------------------------------------------------------- scène et rendu
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
sc.cycles.max_bounces = 10; sc.cycles.transmission_bounces = 10; sc.cycles.transparent_max_bounces = 32
rx, ry = map(int, A.res.split('x'))
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = rx, ry, 100
sc.render.fps = 30
sc.render.use_motion_blur = True; sc.render.motion_blur_shutter = .5
# Khronos PBR Neutral : couleurs de la marque fidèles (crème, framboise, prune), hautes lumières adoucies.
sc.view_settings.view_transform = 'Khronos PBR Neutral'
sc.view_settings.exposure = 0
sc.frame_start, sc.frame_end = 1, END
random.seed(11)

# ---------------------------------------------------------------- caméra
cam_d = bpy.data.cameras.new('cam'); cam = bpy.data.objects.new('cam', cam_d); sc.collection.objects.link(cam)
sc.camera = cam
cam_d.lens = 50; cam_d.sensor_fit = 'HORIZONTAL'; cam_d.sensor_width = 36
cam.location = (0, -3.6, 0); cam.rotation_euler = (math.radians(90), 0, 0)
cam_d.dof.use_dof = True; cam_d.dof.focus_distance = 3.6; cam_d.dof.aperture_fstop = .22   # scène à l'échelle du mètre : grande ouverture pour des lueurs bien floues
VIEW_W = .72 * 3.6                     # largeur visible dans le plan du cœur
VIEW_H = VIEW_W * ry / rx

# ---------------------------------------------------------------- fond (caméra) et reflets (studio)
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; nt = w.node_tree
for n in list(nt.nodes):
    if n.type != 'OUTPUT_WORLD': nt.nodes.remove(n)
tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ')
nt.links.new(tc.outputs['Window'], sep.inputs[0])
cr = nt.nodes.new('ShaderNodeValToRGB')
stops = (['#FFE3E8', '#FFF1EE', '#FFE6D6'] if not NIGHT else ['#2A0F24', '#140C14', '#22112C'])
cr.color_ramp.elements[0].position, cr.color_ramp.elements[0].color = 0., lin(stops[0])
cr.color_ramp.elements[1].position, cr.color_ramp.elements[1].color = 1., lin(stops[2])
e = cr.color_ramp.elements.new(.52); e.color = lin(stops[1])
nt.links.new(sep.outputs['Y'], cr.inputs[0])
# Khronos Neutral assombrit un peu les tons très clairs : on compense pour retrouver la crème de l'app.
bgc = nt.nodes.new('ShaderNodeBackground'); bgc.inputs['Strength'].default_value = 1.0 if NIGHT else 1.5
nt.links.new(cr.outputs[0], bgc.inputs['Color'])
env = nt.nodes.new('ShaderNodeTexEnvironment')
env.image = bpy.data.images.load(os.path.join(HERE, 'assets', 'hdri', 'studio_small_09_2k.hdr'))
bgh = nt.nodes.new('ShaderNodeBackground'); bgh.inputs['Strength'].default_value = .5 if NIGHT else .55
nt.links.new(env.outputs['Color'], bgh.inputs['Color'])
# Le studio n'apparaît que dans les reflets ; la caméra, et ce qu'on voit à travers la bulle, montrent le fond.
lp = nt.nodes.new('ShaderNodeLightPath'); mx = nt.nodes.new('ShaderNodeMixShader')
nt.links.new(lp.outputs['Is Camera Ray'], mx.inputs[0])
nt.links.new(bgh.outputs[0], mx.inputs[1]); nt.links.new(bgc.outputs[0], mx.inputs[2])
nt.links.new(mx.outputs[0], nt.nodes['World Output'].inputs['Surface'])


# ---------------------------------------------------------------- matériaux
def emission_mat(name, color, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True; n = m.node_tree
    for x in list(n.nodes):
        if x.type != 'OUTPUT_MATERIAL': n.nodes.remove(x)
    em = n.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = lin(color)
    em.inputs['Strength'].default_value = strength
    n.links.new(em.outputs[0], n.nodes['Material Output'].inputs['Surface'])
    return m, em


HALO = .55


def glow_mat(name, color, strength):
    """Halo : disque transparent dont l'émission décroît du centre vers le bord (billboard face caméra)."""
    m = bpy.data.materials.new(name); m.use_nodes = True; n = m.node_tree
    for x in list(n.nodes):
        if x.type != 'OUTPUT_MATERIAL': n.nodes.remove(x)
    tc = n.nodes.new('ShaderNodeTexCoord'); gr = n.nodes.new('ShaderNodeTexGradient'); gr.gradient_type = 'SPHERICAL'
    # Le billboard fait `HALO` de côté : rayon ramené à 1 pour que le halo s'éteigne avant les bords.
    mp = n.nodes.new('ShaderNodeMapping'); k = 2 / HALO; mp.inputs['Scale'].default_value = (k, k, k)
    n.links.new(tc.outputs['Object'], mp.inputs[0]); n.links.new(mp.outputs[0], gr.inputs[0])
    pw = n.nodes.new('ShaderNodeMath'); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.6
    n.links.new(gr.outputs['Fac'], pw.inputs[0])
    em = n.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = lin(color); em.inputs['Strength'].default_value = strength
    tr = n.nodes.new('ShaderNodeBsdfTransparent'); add = n.nodes.new('ShaderNodeAddShader')
    mul = n.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'
    n.links.new(pw.outputs[0], mul.inputs[0]); mul.inputs[1].default_value = strength
    n.links.new(mul.outputs[0], em.inputs['Strength'])
    n.links.new(em.outputs[0], add.inputs[0]); n.links.new(tr.outputs[0], add.inputs[1])
    n.links.new(add.outputs[0], n.nodes['Material Output'].inputs['Surface'])
    return m, mul


ROSE = '#FF4F8B' if NIGHT else '#E8417A'
GOLD = '#FFC56B' if NIGHT else '#F0A52E'
TRAIL_STR = 7. if NIGHT else 3.2


def sphere(name, r, mat, loc=(0, 0, 0), seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=seg // 2, location=loc)
    o = bpy.context.active_object; o.name = name; o.data.materials.append(mat)
    for p in o.data.polygons: p.use_smooth = True
    return o


def billboard(name, size, mat, parent):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0), rotation=(math.radians(90), 0, 0))
    o = bpy.context.active_object; o.name = name; o.data.materials.append(mat); o.parent = parent
    o.visible_shadow = False
    return o


# ---------------------------------------------------------------- le cœur
K = 1.55 / 32                          # le cœur fait ~1,55 de large
SHIFT = 2.2 * K                        # centré verticalement


def heart_pt(s, side):
    t = math.pi * (1 - s) * side       # s=0 pointe basse, s=1 creux du haut
    x = 16 * math.sin(t) ** 3
    y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
    return Vector((x * K, 0, y * K + SHIFT))


def resample(pts, n):
    """Points régulièrement espacés le long d'une polyligne (vitesse constante, traînée uniforme)."""
    d = [0.]
    for a, b in zip(pts, pts[1:]): d.append(d[-1] + (b - a).length)
    out, j = [], 0
    for i in range(n):
        s = d[-1] * i / (n - 1)
        while j < len(d) - 2 and d[j + 1] < s: j += 1
        u = (s - d[j]) / max(1e-9, d[j + 1] - d[j])
        out.append(pts[j].lerp(pts[j + 1], u))
    return out


def catmull(ctrl, n=200):
    p = [ctrl[0]] + ctrl + [ctrl[-1]]
    out = []
    for i in range(1, len(p) - 2):
        for k in range(n // (len(ctrl) - 1)):
            t = k / (n // (len(ctrl) - 1)); a, b, c, d = p[i - 1], p[i], p[i + 1], p[i + 2]
            out.append(.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3))
    out.append(ctrl[-1])
    return out


TIP = heart_pt(0, 1); DIP = heart_pt(1, 1)
HALF = {side: resample([heart_pt(i / 400, side) for i in range(401)], 300) for side in (-1, 1)}
# Approche : de hors champ, en boucle, jusqu'à la pointe ; légère profondeur pour la parallaxe.
APPROACH = {
    -1: resample(catmull([Vector((-1.9, .9, -2.6)), Vector((-1.0, .4, -1.2)), Vector((-.15, .25, -1.55)),
                          Vector((-.55, .1, -.75)), TIP + Vector((-.05, 0, -.08)), TIP]), 260),
    1: resample(catmull([Vector((1.9, .9, 2.4)), Vector((1.15, .5, .9)), Vector((1.3, .3, -.6)),
                         Vector((.45, .12, -1.25)), TIP + Vector((.05, 0, -.08)), TIP]), 260),
}


def poly_curve(name, pts, mat, depth):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'
    sp = cu.splines.new('POLY'); sp.points.add(len(pts) - 1)
    for p, v in zip(sp.points, pts): p.co = (v.x, v.y, v.z, 1)
    cu.bevel_depth = depth; cu.bevel_resolution = 4; cu.use_fill_caps = True
    cu.bevel_factor_mapping_start = cu.bevel_factor_mapping_end = 'SPLINE'
    o = bpy.data.objects.new(name, cu); sc.collection.objects.link(o); o.data.materials.append(mat)
    o.visible_shadow = False
    return o


group = bpy.data.objects.new('groupe', None); sc.collection.objects.link(group)   # tout ce qui monte à la fin

orbs, comets, trails, halos, lights = {}, {}, {}, {}, {}
trail_em = {}
for side, col in ((-1, ROSE), (1, GOLD)):
    m_core, _ = emission_mat(f'coeur_{side}', '#FFFFFF' if NIGHT else col, 40 if NIGHT else 18)
    orbs[side] = sphere(f'lumiere_{side}', .028, m_core); orbs[side].parent = group
    hm, hmul = glow_mat(f'halo_{side}', col, 6 if NIGHT else 2.4)
    halos[side] = (billboard(f'halo_{side}', HALO, hm, orbs[side]), hmul)
    li = bpy.data.lights.new(f'lampe_{side}', 'POINT'); li.color = lin(col)[:3]; li.shadow_soft_size = .05
    lo = bpy.data.objects.new(f'lampe_{side}', li); sc.collection.objects.link(lo); lo.parent = orbs[side]
    lights[side] = li
    tm, tem = emission_mat(f'trait_{side}', col, TRAIL_STR); trail_em[side] = tem
    trails[side] = poly_curve(f'trait_{side}', HALF[side], tm, .0085); trails[side].parent = group
    cm, _ = emission_mat(f'comete_{side}', col, TRAIL_STR * .8)
    comets[side] = poly_curve(f'comete_{side}', APPROACH[side], cm, .006); comets[side].parent = group

# Cœur plein, qui s'illumine doucement à la fin (maillage rempli du contour).
contour = HALF[1] + list(reversed(HALF[-1]))[1:-1]
me = bpy.data.meshes.new('coeur_plein')
me.from_pydata([tuple(v + Vector((0, .01, 0))) for v in contour], [], [list(range(len(contour)))])
fill = bpy.data.objects.new('coeur_plein', me); sc.collection.objects.link(fill); fill.parent = group
fm = bpy.data.materials.new('coeur_plein'); fm.use_nodes = True; fn = fm.node_tree
for x in list(fn.nodes):
    if x.type != 'OUTPUT_MATERIAL': fn.nodes.remove(x)
fem = fn.nodes.new('ShaderNodeEmission'); fem.inputs['Color'].default_value = lin('#FF6F9F' if NIGHT else '#F06292')
ftr = fn.nodes.new('ShaderNodeBsdfTransparent'); fmx = fn.nodes.new('ShaderNodeMixShader')
fn.links.new(ftr.outputs[0], fmx.inputs[1]); fn.links.new(fem.outputs[0], fmx.inputs[2])
fn.links.new(fmx.outputs[0], fn.nodes['Material Output'].inputs['Surface'])
fill.data.materials.append(fm); fill.visible_shadow = False

# ---------------------------------------------------------------- la bulle (film de savon irisé)
bm = bpy.data.materials.new('bulle'); bm.use_nodes = True; bn = bm.node_tree
for x in list(bn.nodes):
    if x.type != 'OUTPUT_MATERIAL': bn.nodes.remove(x)
# Film de savon : le regard le traverse (surface transparente : on voit le vrai fond) ; seuls des reflets irisés
# s'y ajoutent, faibles au centre et forts sur les bords (Fresnel). Les couleurs pastel glissent avec l'épaisseur du film.
lw = bn.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = .12
noise = bn.nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 1.8; noise.inputs['Detail'].default_value = 2.5
tcb = bn.nodes.new('ShaderNodeTexCoord'); mpb = bn.nodes.new('ShaderNodeMapping')
bn.links.new(tcb.outputs['Object'], mpb.inputs[0]); bn.links.new(mpb.outputs[0], noise.inputs['Vector'])
mix_f = bn.nodes.new('ShaderNodeMath'); mix_f.operation = 'MULTIPLY_ADD'; mix_f.inputs[1].default_value = 1.7
bn.links.new(noise.outputs['Fac'], mix_f.inputs[0]); bn.links.new(lw.outputs['Facing'], mix_f.inputs[2])
frac = bn.nodes.new('ShaderNodeMath'); frac.operation = 'FRACT'; bn.links.new(mix_f.outputs[0], frac.inputs[0])
rain = bn.nodes.new('ShaderNodeValToRGB'); el = rain.color_ramp.elements
cols = ['#FFB3D1', '#FFE3A3', '#B8F2D8', '#A9D8FF', '#D6B8FF', '#FFB3D1']
el[0].position, el[0].color = 0., lin(cols[0]); el[1].position, el[1].color = 1., lin(cols[-1])
for k, c in enumerate(cols[1:-1], 1):
    e2 = el.new(k / (len(cols) - 1)); e2.color = lin(c)
bn.links.new(frac.outputs[0], rain.inputs[0])
gl = bn.nodes.new('ShaderNodeBsdfGlossy'); gl.inputs['Roughness'].default_value = .03
bn.links.new(rain.outputs[0], gl.inputs['Color'])
tb = bn.nodes.new('ShaderNodeBsdfTransparent')
wgt = bn.nodes.new('ShaderNodeMapRange'); wgt.inputs['To Min'].default_value = .015; wgt.inputs['To Max'].default_value = .6
bn.links.new(lw.outputs['Fresnel'], wgt.inputs['Value'])
mxb = bn.nodes.new('ShaderNodeMixShader'); bn.links.new(wgt.outputs['Result'], mxb.inputs[0])
bn.links.new(tb.outputs[0], mxb.inputs[1]); bn.links.new(gl.outputs[0], mxb.inputs[2])
# Un peu de couleur propre au film (visible même sans reflet), très légère.
em_b = bn.nodes.new('ShaderNodeEmission'); bn.links.new(rain.outputs[0], em_b.inputs['Color'])
emw = bn.nodes.new('ShaderNodeMath'); emw.operation = 'MULTIPLY'; emw.inputs[1].default_value = .16 if NIGHT else .09
bn.links.new(lw.outputs['Fresnel'], emw.inputs[0]); bn.links.new(emw.outputs[0], em_b.inputs['Strength'])
addb = bn.nodes.new('ShaderNodeAddShader'); bn.links.new(mxb.outputs[0], addb.inputs[0]); bn.links.new(em_b.outputs[0], addb.inputs[1])
bn.links.new(addb.outputs[0], bn.nodes['Material Output'].inputs['Surface'])
bubble = sphere('bulle', 1.0, bm, seg=96); bubble.parent = group
bubble.visible_shadow = False
wob = bubble.modifiers.new('ondule', 'DISPLACE'); wtex = bpy.data.textures.new('ondule', 'CLOUDS'); wtex.noise_scale = 1.4
wob.texture = wtex; wob.strength = .025; wob.texture_coords = 'GLOBAL'

# ---------------------------------------------------------------- étincelles et lueurs floues
def sparks(name, at, n, f0, life, speed, cols):
    out = []
    for i in range(n):
        m, _ = emission_mat(f'{name}_{i}', random.choice(cols), 30 if NIGHT else 12)
        o = sphere(f'{name}_{i}', .008 + random.random() * .007, m, seg=8); o.parent = group
        a = random.random() * 2 * math.pi; el = (random.random() - .5) * 1.2
        v = Vector((math.cos(a) * math.cos(el), math.sin(el) * .6, math.sin(a) * math.cos(el))) * speed * (.5 + random.random())
        out.append((o, at, v, f0 + random.randint(0, 3), life * (.7 + random.random() * .6)))
    return out


SPARKS = sparks('etincelle_a', TIP, 22, 70, 26, .9, [ROSE, GOLD, '#FFFFFF']) + \
         sparks('etincelle_b', DIP, 40, 150, 40, 1.3, [ROSE, GOLD, '#FFFFFF', '#FFD1DF'])

BOKEH = []
for i in range(45 if NIGHT else 60):
    col = random.choice(['#FFB3C7', '#FFD08A', '#FFFFFF', '#FF8FAB'] if NIGHT else ['#FFFFFF', '#FFC9D6', '#FFE0B8'])
    m, _ = emission_mat(f'lueur_{i}', col, (2.5 if NIGHT else 1.6) * (.4 + random.random()))
    depth = 2.2 + random.random() * 6
    half_w = (3.6 + depth) * .36 * 1.15; half_h = half_w * ry / rx
    o = sphere(f'lueur_{i}', .035 + random.random() * .05, m, seg=10)
    BOKEH.append((o, Vector(((random.random() * 2 - 1) * half_w, depth, (random.random() * 2 - 1) * half_h)),
                  .03 + random.random() * .05, random.random() * 6.28, half_h))

# ---------------------------------------------------------------- animation (une clé par image : contrôle total)
FINAL_RISE = VIEW_H * (.5 - .33)       # centre du cœur au tiers haut de l'écran

for f in range(1, END + 1):
    sc.frame_set(f)
    # Montée finale de tout le groupe.
    rise = eio(ramp(f, 188, 222)) * FINAL_RISE + math.sin(f / 30 * 1.6) * .012 * ramp(f, 190, 225)
    group.location = (0, 0, rise); group.keyframe_insert('location', frame=f)

    for side in (-1, 1):
        o = orbs[side]
        if f < 70:
            u = eio(ramp(f, 8, 70)); i = int(u * (len(APPROACH[side]) - 1)); pos = APPROACH[side][i]
            com = comets[side].data
            com.bevel_factor_end = u; com.bevel_factor_start = max(0., u - .38)
        else:
            com = comets[side].data
            fade = ramp(f, 70, 92)
            com.bevel_factor_end = 1.; com.bevel_factor_start = min(1., .62 + .38 * fade)
            u = eio(ramp(f, 72, 150)); i = int(u * (len(HALF[side]) - 1)); pos = HALF[side][i]
            if f > 150:                    # réunies au creux : elles glissent vers le centre et s'y fondent
                v = eout(ramp(f, 150, 178)); pos = DIP.lerp(Vector((0, 0, SHIFT - .05)), v)
        com.keyframe_insert('bevel_factor_start', frame=f); com.keyframe_insert('bevel_factor_end', frame=f)
        tr = trails[side].data
        tr.bevel_factor_start = 0.; tr.bevel_factor_end = eio(ramp(f, 72, 150)) if f >= 72 else 0.
        tr.keyframe_insert('bevel_factor_end', frame=f); tr.keyframe_insert('bevel_factor_start', frame=f)
        o.location = pos; o.keyframe_insert('location', frame=f)
        # Visibles dès l'entrée ; à la fin, elles se fondent dans le cœur (plus petites, plus douces).
        vis = ramp(f, 8, 16) * (1 - eout(ramp(f, 158, 188)))
        flash = math.exp(-((f - 70) / 4) ** 2) * .8 + math.exp(-((f - 151) / 6) ** 2) * 2.2
        s = max(.001, vis * (1 + flash))
        o.scale = (s, s, s); o.keyframe_insert('scale', frame=f)
        hl, hmul = halos[side]
        hmul.inputs[1].default_value = (6 if NIGHT else 2.4) * vis * (1 + flash)
        hmul.inputs[1].keyframe_insert('default_value', frame=f)
        lights[side].energy = (2.5 if NIGHT else 1.2) * vis * (1 + flash); lights[side].keyframe_insert('energy', frame=f)
        trail_em[side].inputs['Strength'].default_value = TRAIL_STR * (1 + .9 * math.exp(-((f - 152) / 10) ** 2) + .25 * ramp(f, 160, 200))
        trail_em[side].inputs['Strength'].keyframe_insert('default_value', frame=f)

    # Le cœur s'illumine.
    a = eio(ramp(f, 150, 186)) * (.5 if NIGHT else .78)
    fmx.inputs[0].default_value = a; fmx.inputs[0].keyframe_insert('default_value', frame=f)
    fem.inputs['Strength'].default_value = (2.2 if NIGHT else 1.05) * (1 + .25 * math.sin(f / 30 * 7.5) * ramp(f, 186, 225))
    fem.inputs['Strength'].keyframe_insert('default_value', frame=f)

    # La bulle se gonfle (avec un léger rebond) et ondule ; ses couleurs glissent doucement.
    b = eback(ramp(f, 165, 205)) if f >= 165 else 0.
    breathe = 1 + .012 * math.sin(f / 30 * 3.1) * ramp(f, 200, 225)
    r = max(.001, b * 1.02 * breathe)
    bubble.scale = (r, r, r * .985); bubble.keyframe_insert('scale', frame=f)
    bubble.rotation_euler = (0, f * .004, f * .006); bubble.keyframe_insert('rotation_euler', frame=f)
    mpb.inputs['Location'].default_value = (f * .004, 0, f * .007); mpb.inputs['Location'].keyframe_insert('default_value', frame=f)

    for o, at, v, f0, life in SPARKS:
        t = (f - f0) / life
        if 0 <= t <= 1:
            o.location = at + v * eout(t) * .5 + Vector((0, 0, -.12 * t * t)); s = (1 - t) ** 1.5
        else:
            o.location = at; s = .0001
        o.scale = (s, s, s); o.keyframe_insert('location', frame=f); o.keyframe_insert('scale', frame=f)

    for o, p, amp, ph, half_h in BOKEH:
        z = p.z + f * .0035
        if z > half_h: z -= 2 * half_h
        o.location = (p.x + math.sin(f / 30 * .7 + ph) * amp, p.y, z)
        s = ramp(f, 1, 26)
        o.scale = (max(s, .0001),) * 3
        o.keyframe_insert('location', frame=f); o.keyframe_insert('scale', frame=f)

# Plus de saut entre deux clés : interpolation constante (une clé par image).
for ob in list(bpy.data.objects) + list(bpy.data.curves) + list(bpy.data.materials) + list(bpy.data.lights):
    ad = getattr(ob, 'animation_data', None) or getattr(getattr(ob, 'node_tree', None), 'animation_data', None)
    if ad and ad.action:
        try:
            for fc in ad.action.fcurves:
                for k in fc.keyframe_points: k.interpolation = 'LINEAR'
        except AttributeError:
            pass  # Blender 5 : actions par couches, l'interpolation par défaut (Bézier) entre clés voisines suffit

# ---------------------------------------------------------------- rendu
out = os.path.abspath(A.out); os.makedirs(out, exist_ok=True)
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGB'
if A.frames:
    for fr in [int(x) for x in A.frames.split(',')]:
        sc.frame_set(fr); sc.render.filepath = os.path.join(out, f'still_{fr:04d}.png')
        bpy.ops.render.render(write_still=True)
else:
    if A.range:
        a, b = (int(x) for x in A.range.split('-')); sc.frame_start, sc.frame_end = a, b
    sc.render.filepath = os.path.join(out, '')
    bpy.ops.render.render(animation=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, f'intro_love_{A.theme}.blend'))
print('FOULOV_DONE')
