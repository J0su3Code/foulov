# Intros FouLove

## « Une bulle à deux » (actuelle)

`intro_love.py` : deux lumières (rose et or) entrent, dessinent un cœur de leurs traînées, se retrouvent dans une
étincelle ; le cœur s'illumine et une bulle irisée se gonfle autour de lui, puis monte dans le tiers haut de l'écran
pour laisser la place au panneau d'accueil. Tout est généré par code ; seul élément externe : l'éclairage de studio
CC0 « Studio Small 09 » (Poly Haven, Sergej Majboroda), visible seulement dans les reflets de la bulle.

```bash
./render_all.sh                      # jour puis nuit, 1080×2400, 30 i/s, puis make_video.sh
./export_app_assets.sh render/love_day.mp4 render/love_night.mp4
```

Images de contrôle : `blender -b --factory-startup -P intro_love.py -- --theme night --res 360x800 --samples 24 --frames 40,152,225`.

| Images (30 i/s) | Action |
|---|---|
| 1–24 | Le fond s'éclaire, des lueurs floues flottent |
| 10–70 | La lumière rose (gauche) et la lumière or (droite) entrent en traînant une comète |
| 70 | Elles se touchent à la pointe du cœur : étincelles |
| 70–150 | Chacune dessine une moitié du cœur |
| 150 | Retrouvailles au creux du cœur : éclat, le cœur s'illumine |
| 165–205 | La bulle irisée se gonfle (film de savon : transparence + reflets arc-en-ciel au bord) |
| 190–225 | La bulle monte dans le tiers haut |

L'icône de l'app vient de `icon_love.py` (mêmes cœur et bulle), puis `dart run flutter_launcher_icons` dans `app/`.

## « Jardin » (ancienne, conservée pour mémoire)

Tout est généré par code : scène, animation, textures des feuilles et des pétales.
Les seuls éléments externes sont des matières et modèles **CC0** de [Poly Haven](https://polyhaven.com) (sol, herbe, fougères, éclairages HDRI), téléchargés par script.

| Fichier | Rôle |
|---|---|
| `texgen.py` | Génère les textures botaniques (nervures, contour dentelé, relief, translucidité) dans `textures/`. |
| `fetch_assets.py` | Télécharge les éléments CC0 dans `assets/`. |
| `intro_garden.py` | Construit la scène Blender et rend l'animation (thème `day` ou `night`). |
| `make_video.sh` | Assemble les images et applique l'étalonnage final. |

## Reproduire

```bash
python3 -m venv .venv && .venv/bin/pip install numpy scipy pillow
.venv/bin/python texgen.py
python3 fetch_assets.py
blender -b --factory-startup -P intro_garden.py -- --theme day --out render/anim_day --samples 32
./make_video.sh render/anim_day intro_day.mp4
```

Images fixes de contrôle : ajouter `--frames 60,140,225`.
Rendu final : `--res 1080x2400 --fps 60 --samples 128` (plusieurs heures sur un M1 Pro).

## Chorégraphie (images à 30 i/s)

| Images | Action |
|---|---|
| 1–26 | La graine tombe |
| 26–44 | Rebond, puis la graine s'enfonce dans la terre |
| 46–156 | Les deux tiges poussent en s'enlaçant, les feuilles se déplient |
| 132–150 | Le bouton apparaît et gonfle |
| 150–210 | Éclosion, pétale par pétale |
| 140–185 | Le pollen s'allume |
| 60–210 | La caméra s'élève avec la plante |
| 190–225 | Plan final : la fleur dans le tiers haut, place libre pour le panneau d'accueil |
