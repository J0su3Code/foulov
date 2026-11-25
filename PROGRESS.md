# Suivi FouLove

## État actuel (25 nov. 2026)
- Test fermé Google Play. Dernier AAB : **1.0.0+5** (`~/Desktop/FouLove-1.0.0-build5.aab`) : audit de sécurité,
  appairage par lien, vue unique, panneau émojis. Ordre de sortie : site (`vercel deploy --prod`, pour les liens
  d'app) → AAB sur Play → `git push` (le rapport d'audit devient public) → plus tard couper « Allow public access »
  de Realtime quand plus personne n'a la 1.0.0+4.
- Fonctionne : messages chiffrés, photos/vidéos/vocaux, instants, lettres, souvenirs, sauvegarde, thème.
- Ajouté dans 1.0.0+3 / +4 : stickers (pack de 2 037 sur R2 + import + favoris), modification 15 min,
  réponses façon WhatsApp avec saut au message, albums photo, aperçu avant envoi, galerie Android, nouveau thème.

## Retours testeurs
### Corrigés
- (25 nov., 1.0.0+5) Appairage confus, les deux créaient une bulle → écran de choix à deux cartes de même poids
  (« J'invite mon amour » / « Mon amour m'a invité(e) »), frises d'étapes en icônes, sortie visible
  « C'est mon amour qui m'a invité(e) » (`couple_screens.dart`). Si les deux ont créé : toucher le lien de l'autre
  remplace la bulle vide (`InvitationReceivedScreen`). Testé sur 2 émulateurs avec 2 comptes jetables (supprimés).
- (25 nov.) Invitation « pas un lien » → vrai lien `https://foulove.josuecode.com/rejoindre/#2.code.empreinte.secret`
  qui ouvre l'app (App Links, `site/public/.well-known/assetlinks.json` avec les 5 empreintes : Play ×3, envoi,
  debug), pages de secours `site/src/pages/rejoindre.astro` et `lien.astro`, réception `incoming_links.dart`
  (paquet `app_links`). Liens de retrouvailles aussi en `…/lien/#empreinte`. Anciens formats acceptés.
  Test : `app/test/invitation_test.dart`.
- (25 nov.) Vue unique demandée → bouton « 1 » dans l'aperçu (`media_preview.dart`), bulle `ViewOnceBubble` et
  écran protégé `view_once.dart` (FLAG_SECURE : capture noire vérifiée), cœur `create_view_once`,
  `view_once_begin/done`, `purge_view_once` (14 jours), protobuf 21/22, colonne `media.view_once`
  (`chat_media.rs`, `store.rs`), exclue de la galerie, des albums et de la sauvegarde. Tests `core/tests/view_once.rs`.
  Vérifié de bout en bout : « Ouverte » chez l'expéditeur, plus de fichier chez le destinataire, 0 objet sur R2.
- (25 nov.) Bouton smiley = stickers → panneau Émojis | Stickers façon WhatsApp (`expression_panel.dart`, paquet
  `emoji_picker_flutter`), ouvre sur les smileys ; l'onglet « Mes stickers » n'a plus l'icône smiley.
- (25 nov.) Risque trouvé avant l'envoi : sans les 7 symboles, un examinateur Google (compte démo, téléphone neuf)
  serait resté bloqué sur l'écran de vérification → bouton « Plus tard » (`VerifyScreen.onLater`,
  `CoupleState.verifyLater`, clé `foulov.verify_later` liée à la clé du partenaire), et la conversation dit
  « clés pas encore vérifiées, touche pour vérifier » (`_E2EBadge`). Une clé **changée** reste bloquante.
  Instructions Play mises à jour (« then "Plus tard" », 489 caractères avec la phrase) : `docs/play/guide/index.html`
  → **à recopier dans Play Console** (Informations de connexion).
- (25 nov.) Play Console, version 1 sautée : cause trouvée dans l'historique, c'était le **verrou d'orientation**
  portrait de l'écran de recadrage (retiré en 1.0.0+2, commit d4ddcc4), pas la capture d'écran. Rien ne reste.
  Play refuse toujours un numéro de version déjà envoyé, même jamais publié.
- Toucher un vocal ouvrait la visionneuse photo → `chat_screen.dart` (`_tap`, seulement photos/vidéos/stickers).
- Galerie = explorateur de fichiers, pas de sélection multiple → `main.dart` (`useAndroidPhotoPicker`), `media_preview.dart`.
- Pas de stickers → pack R2 (`sticker_pack.dart`, fonction `media` action `stickers`) + import (`stickers.dart`).
- Modifier un message → `core/src/chat.rs` (`Edit`, tag 20, contrôle de l'heure côté réception).
- Design des réponses bizarre → `_QuoteBox` / `_ReplyQuote` dans `chat_screen.dart`, saut via `super_sliver_list`.
- Thème sans aperçu → `personalize_screen.dart` réorganisé comme WhatsApp (pages Bulle / Fond d'écran avec aperçu).
- Stickers trop grands → 1/3 de la largeur (160 px max), heure dessous en pastille (`_StickerBubble`).
### En cours
- (aucun)
### À faire / à vérifier
- Vérifier sur un vrai téléphone la réception d'un sticker et d'une modification (testé seulement côté envoi).
- Une fois vu : en-tête « hors ligne » après démarrage à froid de l'émulateur, réglé par une relance de l'app. Cause non cherchée.

## Audit de sécurité (25 nov. 2026) — serveur **en production**, app dans la prochaine version
Rapport : `docs/revue/2026-11-revue-securite.md` ; `docs/SECURITY.md` passé en v0.2 (§5, §7, §8, §11).
- 7 symboles retirés (truquables par un serveur malveillant, 42 bits) : `core/src/sas.rs` supprimé ; vérification
  par invitation complète, QR ou liens `foulove:id:` → `couple_screens.dart` (`VerifyScreen`, `KeyChangeScreen`).
- `mark_verified(partenaire, clé)` : ne vérifie que la clé contrôlée (`store.rs`, `device.rs`, pont `device.rs`).
- « Code oublié » : verrou du téléphone, sinon remise à zéro (`app_lock.dart`, `main.dart`). Délais du code :
  exposant borné, erreur comptée avant la vérification, horloge monotone (`app/test/app_lock_test.dart`).
- Instant ne remplace plus une photo existante (`chat_media.rs` `insert_remote`, test dans `space.rs`).
- Transfert : clé vérifiée exigée dans le cœur (`offer_history(partner, dir)`), archive filtrée, abandon après échec
  (`transfer.rs`, `backup.rs`, test `une_archive_aux_noms_pieges_est_filtree`).
- Plafond des contenus inconnus (2 000), `temp_store = MEMORY`, clé SQLCipher effacée (`zeroize`).
- Serveur : migration `20261125120000_quotas.sql` (plafonds enveloppes + R2, verrou d'appairage), quota appelé par
  la fonction `media` (`take_media_quota`), tests `quotas.test.sql`. **Déployé le 25 nov.** (migrations + fonction
  `media`), compatible avec l'app 1.0.0+4.
- Android : `allowBackup=false` + `data_extraction_rules.xml` ; build release refusé sans `key.properties`.
- Site : `guide.md`, `securite.md` mis à jour (à déployer après le push GitHub, la page renvoie vers le rapport).
- Canal des enveloppes passé en privé (`chat_service.dart`, migration `…_canal_enveloppes_prive.sql` déployée,
  test `canaux.test.sql`). **Quand plus aucun testeur n'a la 1.0.0+4** : couper Supabase Realtime → Settings →
  « Allow public access » (aujourd'hui actif ; le couper avant casserait la réception en direct des anciennes versions).
- Formulation : « audité » (audit du code réalisé avec Claude) ; audit indépendant = prochaine étape (choix de
  l'utilisateur, `docs/AUDIT.md`).
- Site et GitHub : pas encore envoyés (le site renvoie au rapport sur GitHub) → à faire avec la 1.0.0+5.
- Les nouveaux écrans ne sont pas encore testés sur téléphone : à faire avec la prochaine version.

## Décisions
- 7 symboles supprimés (choix de l'utilisateur : personne ne les comparait) ; seuls les liens/QR/invitation vérifient.
- Stickers hébergés sur R2, pas dans l'app : l'AAB resterait > 200 Mo (limite Play). Seau privé, liens signés par lots (pas besoin d'accès public Cloudflare).
- Pas Supabase Storage (choix de l'utilisateur ; quota de téléchargement limité).
- Stickers et modifications sous de nouveaux numéros protobuf (19, 20) : les anciennes versions les gardent et les affichent après mise à jour.
- Fenêtre de modification 15 min (WhatsApp) ; refus si l'heure annoncée est invraisemblable ou si la modification arrive plus d'un jour après le message.
- Bibliothèque de stickers dans la base SQLCipher du téléphone, non sauvegardée pour l'instant.

## Prochaines étapes
- Attendre la validation de la 1.0.0+4 et les retours testeurs.
- Possible : inclure la bibliothèque de stickers dans la sauvegarde ; animations dans la grille du pack (miniatures fixes aujourd'hui).
