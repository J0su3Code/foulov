"""FouLov — génération procédurale des textures botaniques (aucune image externe).

Produit dans textures/ :
  leaf_albedo.png (RGBA, alpha = contour dentelé), leaf_normal.png, leaf_rough.png, leaf_trans.png
  petal_{day,night}_albedo.png (RGBA), petal_normal.png, petal_{day,night}_trans.png

Repère : u ∈ [-1, 1] en travers (gauche → droite), v ∈ [0, 1] de la base (bas de l'image) à la pointe (haut).
Usage : .venv/bin/python texgen.py
"""
import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from scipy.spatial import cKDTree

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'textures')
os.makedirs(OUT, exist_ok=True)
W, H = 1024, 2048
rng = np.random.default_rng(42)

# grille : ligne 0 = haut de l'image = pointe (v=1)
U, V = np.meshgrid(np.linspace(-1, 1, W), np.linspace(1, 0, H))
PX = 2.0 / W                                        # taille d'un pixel en unités u


def hexc(h):
    h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def fbm(octaves=5, base=8, seed=0):
    """Bruit fractal lisse en [0, 1]."""
    r = np.random.default_rng(seed); acc = np.zeros((H, W)); amp = 1.0; tot = 0
    for o in range(octaves):
        sig = max(1.0, H / (base * 2 ** o) / 2)
        acc += amp * gaussian_filter(r.standard_normal((H, W)), sig, mode='wrap'); tot += amp; amp *= .55
    acc -= acc.min(); return acc / max(acc.max(), 1e-9)


def ramp(x, stops):
    """Dégradé multi-couleurs : stops = [(pos, '#hex'), ...]."""
    out = np.zeros(x.shape + (3,))
    ps = [p for p, _ in stops]; cs = [hexc(c) for _, c in stops]
    for i in range(3):
        out[..., i] = np.interp(x, ps, [c[i] for c in cs])
    return out


def mix(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


def normal_from_height(h, strength):
    gy, gx = np.gradient(h)                        # gy : vers le bas de l'image = -v
    nx, ny = -gx * strength, gy * strength          # convention OpenGL (Y vers le haut = +v)
    n = np.stack([nx, ny, np.ones_like(h)], -1); n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * .5 + .5


def voronoi_edges(npts, seed, mask=None):
    r = np.random.default_rng(seed)
    pts = np.stack([r.uniform(-1, 1, npts), r.uniform(0, 1, npts) * 2], -1)   # v étiré ×2 (image 1:2)
    tree = cKDTree(pts)
    q = np.stack([U.ravel(), V.ravel() * 2], -1)
    d, _ = tree.query(q, k=2, workers=-1)
    f1 = d[:, 0].reshape(H, W); edge = (d[:, 1] - d[:, 0]).reshape(H, W)
    return f1, edge


def save(name, arr, mode='RGB'):
    a = np.clip(arr, 0, 1)
    img = Image.fromarray((a * 255 + .5).astype(np.uint8), mode)
    img.save(os.path.join(OUT, name), optimize=True); print('  ', name)


def save_gray(name, arr):
    save(name, arr, 'L')


# ======================================================================= FEUILLE
def leaf():
    print('feuille')
    au = np.abs(U)
    # contour : ovale à pointe effilée, élargi au premier tiers
    w = 1.9 * np.power(np.clip(V, 0, 1), .62) * np.power(np.clip(1 - V, 0, 1), .95)
    w = w / w.max() * .94
    # dents de scie orientées vers la pointe
    teeth = 30
    saw = (V * teeth) % 1.0
    tooth = .045 * (1 - saw) ** 1.6 * sstep(.12, .3, V) * (1 - sstep(.9, .99, V))
    edge = w * (1 - tooth)
    petiole = (V < .07) & (au < .035 * (1 - V / .07 * .4))
    d_edge = edge - au                                         # >0 à l'intérieur
    alpha = np.clip(d_edge / (2.2 * PX) + .5, 0, 1)
    alpha = np.maximum(alpha, petiole.astype(float))
    rel = np.clip(au / np.maximum(w, 1e-3), 0, 1.2)

    # nervure centrale (plus épaisse à la base)
    wm = .028 * (1 - V) + .006
    mid = sstep(0, 1, 1 - au / wm)
    # nervures secondaires : arcs qui partent de la nervure centrale vers la pointe, se rejoignent près du bord
    spacing = .088
    g = (V - .07 - .30 * rel ** 1.35) / spacing
    fr = np.abs(g - np.round(g)) * spacing
    th = .0065 * (1 - .65 * rel) + .0015
    sec = sstep(0, 1, 1 - fr / th) * (g > -.3) * (g < 10.2) * (rel < .92) * sstep(.02, .06, au)
    # réseau tertiaire (aréoles)
    f1, ed = voronoi_edges(5200, 3)
    ter = sstep(0, 1, 1 - ed / .009) * .55
    veins = np.clip(np.maximum(mid, np.maximum(sec, ter * (1 - sec))), 0, 1)
    veins_main = np.maximum(mid, sec)

    n1, n2 = fbm(6, 6, 1), fbm(4, 40, 2)
    # couleur : vert profond, plus clair près de la nervure, assombri sur le bord, légère dorure à la pointe
    base = ramp(n1 * .7 + rel * .3, [(0, '#3E6E33'), (.5, '#33602C'), (1, '#264B22')])
    base = mix(base, hexc('#5B8B3A'), sstep(.25, 0, rel) * .35)
    base = mix(base, hexc('#1F3F1C'), sstep(.012, 0, d_edge) * .55)
    base = mix(base, hexc('#8A9A3A'), sstep(.75, 1, V) * .25 * n2)
    base = mix(base, hexc('#A9C77A'), veins_main * .55 + ter * .18)
    # petites imperfections
    spots = (fbm(3, 160, 9) > .86).astype(float) * .3
    base = mix(base, hexc('#6B6A2E'), gaussian_filter(spots, 1.5))
    base *= (.92 + .16 * n2)[..., None]
    save('leaf_albedo.png', np.dstack([base, alpha]), 'RGBA')

    # relief : nervures en creux sur la face supérieure, aréoles bombées
    puff = 1 - np.clip(f1 / .02, 0, 1)
    hgt = .55 * puff * (1 - veins) - .9 * veins_main - .35 * ter + .15 * n2
    hgt = gaussian_filter(hgt, 1.2)
    save('leaf_normal.png', normal_from_height(hgt, 7.0))
    save_gray('leaf_rough.png', .32 + .2 * veins + .12 * n2)
    trans = ramp(n1, [(0, '#9BC24E'), (1, '#C7DE6A')]) * (1 - .55 * veins_main - .25 * ter)[..., None]
    trans = mix(trans, np.zeros(3), sstep(.01, 0, d_edge) * .5)
    save('leaf_trans.png', trans)


# ======================================================================= PÉTALE
def petal():
    print('pétale')
    au = np.abs(U)
    # obovale : onglet étroit à la base, large vers le haut, bord supérieur festonné (3 lobes) et irrégulier
    w = .16 + .82 * np.sin(np.pi / 2 * np.clip(V / .78, 0, 1)) ** 1.25
    w = np.where(V > .78, .98 - .22 * ((V - .78) / .22) ** 2.2, w)
    n_edge = fbm(4, 30, 11)
    tip = .965 - .05 * np.abs(np.sin(np.pi * 1.5 * (U + 1))) - .018 * n_edge
    d_side = w * (1 - .02 * n_edge) - au
    d_tip = (tip - V) * 1.0
    d = np.minimum(d_side, d_tip)
    alpha = np.clip(d / (2.2 * PX) + .5, 0, 1)

    q = U / np.maximum(w, 1e-3)                                    # coordonnée normalisée en travers
    wob = (fbm(4, 18, 12) - .5) * .06
    nv = 15
    ph = (q + wob) * nv
    fr = np.abs(ph - np.round(ph)) / nv
    main = sstep(0, 1, 1 - fr / (.012 + .01 * (1 - V)))
    ph2 = (q + wob * 1.7) * nv * 2.1 + .5
    fr2 = np.abs(ph2 - np.round(ph2)) / (nv * 2.1)
    fine = sstep(0, 1, 1 - fr2 / .006) * sstep(.35, .7, V)
    veins = np.clip(main + .55 * fine, 0, 1)
    n1, n2 = fbm(5, 10, 13), fbm(3, 90, 14)
    sparkle = (fbm(2, 400, 15) > .8).astype(float)

    hgt = gaussian_filter(-.8 * veins + .25 * n1, 1.0)
    save('petal_normal.png', normal_from_height(hgt, 5.0))

    for theme, stops, vein_col, guide in (
        ('day', [(0, '#F4F0D0'), (.09, '#FBE2EA'), (.4, '#F6A9C3'), (.85, '#EC7EA6'), (1, '#E26C98')], '#D04B80', '#B8336A'),
        ('night', [(0, '#FFF2DC'), (.09, '#FFE0CC'), (.4, '#FFB591'), (.85, '#FF8D86'), (1, '#FF7090')], '#F0607E', '#E2476E'),
    ):
        print('  thème', theme)
        col = ramp(np.clip(V + (n1 - .5) * .08, 0, 1), stops)
        col = mix(col, hexc(guide), sstep(.06, .1, V) * (1 - sstep(.16, .26, V)) * .55)   # anneau de couleur près du cœur
        col = mix(col, hexc(vein_col), veins * (.22 + .25 * (1 - V)))
        col = mix(col, np.ones(3), sstep(.012, 0, d) * .25)                                  # bord légèrement translucide
        col *= (.95 + .08 * n2)[..., None]
        col = mix(col, np.ones(3), gaussian_filter(sparkle, .7) * .08)
        save(f'petal_{theme}_albedo.png', np.dstack([col, alpha]), 'RGBA')
        tr = col * (1.05 - .35 * veins)[..., None]
        save(f'petal_{theme}_trans.png', tr)


if __name__ == '__main__':
    leaf(); petal(); print('ok')
