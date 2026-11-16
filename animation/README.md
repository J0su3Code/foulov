# Intro cinématique FouLove

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
