#!/usr/bin/env bash
# Étalonnage de l'intro « une bulle à deux » : halo doux sur les lumières, sans vignettage (fond clair le jour).
# Usage : ./make_video_love.sh render/love_day render/love_day.mp4
set -euo pipefail
SRC="$1"; OUT="$2"
ffmpeg -y -loglevel error -framerate 30 -i "$SRC/%04d.png" \
  -filter_complex "[0:v]split[a][b];[b]gblur=sigma=18,curves=all='0/0 0.6/0.12 1/1'[g];[a][g]blend=all_mode=screen:all_opacity=0.35,eq=saturation=1.04,noise=alls=2:allf=t,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -crf 17 -preset slow -movflags +faststart "$OUT"
echo "ok : $OUT"
