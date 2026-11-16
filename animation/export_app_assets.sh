#!/usr/bin/env bash
# Prépare les intros pour l'app Flutter, avec une synchronisation parfaite :
#   splash natif (couleur unie) → vidéo qui démarre par un fondu depuis cette même couleur → dernière image = fond de l'accueil.
# Usage : ./export_app_assets.sh <video_jour.mp4> <video_nuit.mp4>
set -euo pipefail
DAY="$1"; NIGHT="$2"
OUT="$(cd "$(dirname "$0")/.." && pwd)/app/assets/intro"
mkdir -p "$OUT"
# Couleurs du splash natif : elles doivent rester identiques à celles de app/flutter_native_splash.yaml et lib/theme.
COLOR_DAY="0x0C2219"; COLOR_NIGHT="0x0A0710"

export_one() {
  local src="$1" name="$2" color="$3"
  # 0,7 s de fondu depuis la couleur du splash ; H.264 (lecture matérielle partout), démarrage rapide.
  ffmpeg -y -loglevel error -i "$src" \
    -vf "fade=t=in:st=0:d=0.7:color=${color},format=yuv420p" \
    -c:v libx264 -profile:v high -crf 21 -preset slow -movflags +faststart -an "$OUT/$name.mp4"
  # Dernière image exacte : sert de fond à l'écran d'accueil après la vidéo.
  ffmpeg -y -loglevel error -sseof -0.1 -i "$OUT/$name.mp4" -update 1 -frames:v 1 -q:v 2 "$OUT/${name}_last.jpg"
  echo "  $name : $(du -h "$OUT/$name.mp4" | cut -f1)"
}
export_one "$DAY" intro_day "$COLOR_DAY"
export_one "$NIGHT" intro_night "$COLOR_NIGHT"
echo "ok : $OUT"
