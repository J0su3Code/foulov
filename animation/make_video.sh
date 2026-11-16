#!/usr/bin/env bash
# Assemble les images rendues en vidéo et applique l'étalonnage final (halo doux, contraste, vignettage, grain).
# Usage : ./make_video.sh render/anim_day intro_day.mp4 [fps]
set -euo pipefail
SRC="$1"; OUT="$2"; FPS="${3:-30}"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$SRC/%04d.png" \
  -filter_complex "[0:v]split[a][b];[b]gblur=sigma=14,curves=all='0/0 0.55/0.18 1/1'[g];[a][g]blend=all_mode=screen:all_opacity=0.22,eq=contrast=1.07:saturation=1.06:gamma=0.98,vignette=angle=PI/5,noise=alls=4:allf=t,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -crf 17 -preset slow -movflags +faststart "$OUT"
echo "ok : $OUT"
