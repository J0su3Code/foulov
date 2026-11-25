# FouLove — repères pour Claude

Messagerie privée chiffrée de bout en bout pour un couple. Android en test fermé sur Google Play (`org.foulov.app`).

## Règles de travail (demandées par l'utilisateur)
- Toujours répondre en français, simplement.
- Début de session : lire ce fichier et `PROGRESS.md`, puis seulement le code utile à la tâche.
- Retour testeur reçu : l'ajouter dans `PROGRESS.md` (« Retours testeurs ») **avant** de coder.
- Correction ou fonctionnalité terminée : mettre `PROGRESS.md` à jour (quoi, quels fichiers, pourquoi) sans qu'on le demande.
- Fin de tâche : vérifier `CLAUDE.md` et `PROGRESS.md`, puis dire « ✅ Tout est sauvegardé, tu peux faire /clear ».
- Messagerie : reprendre ce que fait WhatsApp plutôt qu'inventer.

## Stack
- `app/` Flutter (Dart 3.12). `core/` Rust : chiffrement libsignal, base SQLCipher, médias chiffrés.
- `app/rust/` pont flutter_rust_bridge 2.13 vers `core` (code généré dans `app/lib/src/rust/`).
- `supabase/` : Postgres, Realtime (enveloppes chiffrées), fonctions `media` (liens R2 signés), `push`, `account`.
- Cloudflare R2 : `foulovmedia` (fichiers chiffrés), `foulove-stickers` (pack public de stickers, seau privé).
- `site/` Astro (Vercel), `video/` Remotion, `docs/` (SECURITY.md fait foi pour la crypto).

## Fichiers clés
- `core/src/chat.rs` : format des messages (protobuf `pb::Body`, ne jamais réutiliser un numéro), réception.
- `core/src/chat_media.rs` (photos, vidéos, vocaux, stickers kind 4), `stickers.rs` (bibliothèque locale), `store.rs` (schéma + migrations).
- `app/lib/features/chat/chat_screen.dart` (conversation), `chat_service.dart` (transport), `stickers.dart` + `sticker_pack.dart`, `media_preview.dart`.
- `app/lib/features/space/personalize_screen.dart` (thème), `chat/bubble_look.dart` (bulles, fonds).
- `tools/stickers/` : préparer et déposer le pack de stickers sur R2.

## Commandes
- Rust : `export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$HOME/.cargo/bin:$PATH"` (absent du PATH par défaut).
- Tests : `cd core && cargo test` ; `cd app && flutter analyze lib && flutter test`.
- Pont Rust après changement d'API : `cd app && flutter_rust_bridge_codegen generate`.
- Build : `cd app && flutter build appbundle --release --dart-define-from-file=dart_defines.local.json` (aussi `apk --profile`).
- Fonction serveur : `supabase functions deploy media` (projet déjà lié). Base : `supabase db push`.
- Site : `cd site && vercel deploy --prod` (pas relié à GitHub, déploiement à la main).
- Comptes : l'utilisateur change souvent de compte. Avant un déploiement, vérifier : `supabase projects list`
  (organisation « FouLov », projet `uaxouzccldvjhktcavlk`) et `vercel teams ls` (équipe `fou-lov`, projet `foulove`).
- Tests serveur : `supabase start -x studio,…` puis `supabase migration up --local` et `supabase test db`.
- Recherche web : `~/bin/cherche "requête"` (SearXNG local, OrbStack) ; WebSearch indisponible.

## Pièges connus
- Monter `version:` dans `app/pubspec.yaml` (+N) avant chaque AAB : Play refuse un numéro déjà envoyé.
- Émulateurs : `Pixel_7a` = compte démo Inès/Sami (ne rien supprimer ni envoyer), `Pixel_8` = Made ↔ JOSHUA. Ils ont la version **profil** (clé debug) : `adb install -r app-profile.apk` garde les données. Un téléphone avec la version Play exige une désinstallation (perte de l'historique local).
- Le téléphone de l'utilisateur (TECNO, ADB sans fil) se reconnecte tout seul : `adb disconnect` avant d'installer.
- Lancer un émulateur détaché (`subprocess.Popen(..., start_new_session=True)`), sinon il meurt avec la tâche.
- Ne pas lancer `flutter analyze`/`test` pendant un build Gradle (casse `GeneratedPluginRegistrant`).
- Retour système : `HomeShell` a son `PopScope` ; la conversation passe par `ChatBack` (pas de PopScope dans `ChatScreen`).
- Secrets : `Secret Keys/` (hors git). Ne jamais afficher de valeur ; copie temporaire dans `~/.foulov-r2.env`, à effacer.
- `test/widget_test.dart` (couleurs du splash) échoue déjà avant nos changements.
- Compat : un nouveau contenu doit avoir son propre numéro protobuf pour que les vieilles versions le gardent (`unknown_contents`).
