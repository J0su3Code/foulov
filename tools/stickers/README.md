# Pack de stickers FouLove (R2)

1. `python3 -m venv /tmp/r2venv && /tmp/r2venv/bin/pip install boto3 pillow`
2. Préparer : `/tmp/r2venv/bin/python -I pack.py <dossier source avec whatsapp/ et business/> <sortie>`
   (dédoublonne, allège, nomme par SHA-256, miniatures 160 px, `v1/index.json`).
3. Accès R2 : fichier `~/.foulov-r2.env` (hors git, à effacer après) avec `R2_ENDPOINT`, `R2_KEY`, `R2_SECRET`,
   tirés de `Secret Keys/FOULOV.docx`. Ne jamais afficher ni commiter ces valeurs.
4. Déposer : `/tmp/r2venv/bin/python -I upload.py <sortie>` (seulement les nouveaux fichiers, l'index en dernier).

Seau : `foulove-stickers` (privé). L'app lit via la fonction `media` (action `stickers`), voir `sticker_pack.dart`.
