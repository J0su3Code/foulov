#!/bin/zsh
# Rend une version et normalise le son (-14 LUFS, réseaux sociaux et YouTube). Usage : scripts/finir.sh Vertical|Horizontal
set -e
cd "${0:A:h}/.."
v=$1; nom=foulove-${(L)v}
npx remotion render src/index.ts FouLove$v out/$nom-brut.mp4 --codec=h264 --crf=18 --log=error
ffmpeg -y -loglevel error -i out/$nom-brut.mp4 -c:v copy -af "loudnorm=I=-14:TP=-1.5:LRA=11" -c:a aac -b:a 192k -movflags +faststart out/$nom.mp4
rm out/$nom-brut.mp4
