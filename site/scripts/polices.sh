#!/bin/zsh
# Refait public/fonts/fraunces-*.woff2 à partir de Fraunces (SIL OFL) : graisse 500 à 650, axes SOFT et WONK figés,
# caractères latins seulement. Demande fonttools et brotli (par exemple dans un venv : pip install fonttools brotli)
# et le paquet npm @fontsource-variable/fraunces (npm i --no-save @fontsource-variable/fraunces@5.3.0).
set -e
cd "${0:A:h}/.."
F=node_modules/@fontsource-variable/fraunces/files
U="U+0020-007E,U+00A0-00FF,U+0152-0153,U+0178,U+2013-2014,U+2018-201E,U+2026,U+202F,U+2039-203A,U+20AC,U+2192"
T=$(mktemp -d)
for st in normal italic; do
  if [[ $st == normal ]]; then s=60; w=0; else s=100; w=1; fi
  fonttools varLib.instancer $F/fraunces-latin-full-$st.woff2 wght=500:650 SOFT=$s WONK=$w -o $T/$st.ttf -q
  pyftsubset $T/$st.ttf --unicodes="$U" --layout-features='kern,liga,clig,calt,ccmp,locl,mark,mkmk' \
    --flavor=woff2 --output-file=public/fonts/fraunces-$st.woff2
done
rm -rf $T
