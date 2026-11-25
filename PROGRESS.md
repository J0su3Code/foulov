# Suivi FouLove

## État actuel (25 nov. 2026)
- Test fermé Google Play. Dernier AAB : **1.0.0+4** (`~/Desktop/FouLove-1.0.0-build4.aab`), envoyé par l'utilisateur.
- Fonctionne : messages chiffrés, photos/vidéos/vocaux, instants, lettres, souvenirs, sauvegarde, thème.
- Ajouté dans 1.0.0+3 / +4 : stickers (pack de 2 037 sur R2 + import + favoris), modification 15 min,
  réponses façon WhatsApp avec saut au message, albums photo, aperçu avant envoi, galerie Android, nouveau thème.

## Retours testeurs
### Corrigés
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

## Décisions
- Stickers hébergés sur R2, pas dans l'app : l'AAB resterait > 200 Mo (limite Play). Seau privé, liens signés par lots (pas besoin d'accès public Cloudflare).
- Pas Supabase Storage (choix de l'utilisateur ; quota de téléchargement limité).
- Stickers et modifications sous de nouveaux numéros protobuf (19, 20) : les anciennes versions les gardent et les affichent après mise à jour.
- Fenêtre de modification 15 min (WhatsApp) ; refus si l'heure annoncée est invraisemblable ou si la modification arrive plus d'un jour après le message.
- Bibliothèque de stickers dans la base SQLCipher du téléphone, non sauvegardée pour l'instant.

## Prochaines étapes
- Attendre la validation de la 1.0.0+4 et les retours testeurs.
- Possible : inclure la bibliothèque de stickers dans la sauvegarde ; animations dans la grille du pack (miniatures fixes aujourd'hui).
