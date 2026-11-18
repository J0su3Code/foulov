#!/usr/bin/env bash
# Rendu final des deux intros (jour puis nuit), puis montage et export vers l'app.
set -euo pipefail
cd "$(dirname "$0")"
for t in day night; do
  blender -b --factory-startup -P intro_love.py -- --theme $t --out render/love_$t --res 1080x2400 --samples 40 2>&1 | grep -E "Fra:|Error|Traceback|FOULOV_DONE" | grep -vE "Fra:.*(Sample|Path Tracing|Updating|Synchroniz|Loading|Denois|Rendering|Remaining)" || true
  ./make_video_love.sh render/love_$t render/love_$t.mp4
done
echo RENDU_TERMINE
