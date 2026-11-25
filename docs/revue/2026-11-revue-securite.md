# Audit de sécurité de FouLove — 25 novembre 2026

Audit complet du code et du serveur, réalisé avec Claude (Anthropic) à la demande de l'éditeur, en suivant
`docs/AUDIT.md`. Un audit indépendant, par une équipe extérieure, viendra le compléter (`docs/SECURITY.md` §11).

## Résumé

- **Ce qui est solide** : aucun secret dans le dépôt ni dans son historique ; serveur réel testé de l'extérieur
  (toutes les tables et fonctions refusent un visiteur sans compte) ; règles d'accès correctes ; chiffrement
  (libsignal PQXDH + triple ratchet, STREAM AES-256-GCM, preuve HMAC de l'invitation, sauvegarde, SQLCipher)
  correctement utilisé ; site avec de bons en-têtes de sécurité.
- **Le code public n'est pas une faille** : la sécurité repose sur des clés, pas sur le secret du code.
- **11 problèmes trouvés, tous corrigés** sauf les limites listées à la fin.

## Problèmes et corrections

| # | Gravité | Problème | Correction | Preuve |
|---|---|---|---|---|
| 1 | Critique | Les 7 symboles (42 bits, calculés sur les seules clés à long terme) pouvaient être truqués par un serveur malveillant : une recherche « des anniversaires » d'environ 2²¹ clés de chaque côté donne deux fausses clés qui affichent les mêmes symboles sur les deux téléphones. Concernait l'appairage par code seul et le changement de téléphone. | Symboles retirés (`core/src/sas.rs` supprimé). Vérification uniquement par invitation complète, QR code ou liens `foulove:id:` (empreinte de 256 bits) échangés par une autre messagerie. | Écrans `VerifyScreen`, `KeyChangeScreen` |
| 2 | Haute | « Code oublié ? » : se reconnecter (Google en un geste, ou code reçu dans l'app mail du même téléphone) retirait le code FouLove en gardant tout l'historique. Quiconque empruntait le téléphone déverrouillé lisait tout. | Le verrouillage du téléphone (empreinte, visage, code) remplace le code ; sinon, remise à zéro de ce téléphone. | `app_lock.dart` |
| 3 | Haute | Aucun plafond : un compte pouvait obtenir sans fin des liens d'envoi de 220 Mo vers R2 (facture) ; deux comptes pouvaient mettre 5 Go d'enveloppes en attente par destinataire et remplir la base (service bloqué pour tous). | Plafonds en base : 50 Mo / 5 000 enveloppes en attente par destinataire, 200 Mo / 20 000 par expéditeur et par jour ; R2 : 300 envois et 3 Go par jour, 15 Go sur 30 jours, par compte. | `quotas.test.sql` (14 tests) |
| 4 | Moyenne | Le partenaire pouvait envoyer un « instant » portant l'identifiant d'une de mes photos et la remplacer dans mon propre historique (`INSERT OR REPLACE`). | Un fichier reçu ne remplace jamais une ligne existante ; le contenu est refusé. | `un_instant_ne_remplace_jamais_une_photo_existante` |
| 5 | Moyenne | Délai du code FouLove : débordement de `pow(2, n)` vers la 64ᵉ erreur (plus aucun délai) ; erreur non comptée si l'app était fermée pendant la vérification ; délai contourné en avançant l'heure du téléphone. | Exposant borné, erreur enregistrée avant la vérification, horloge monotone. | `app/test/app_lock_test.dart` |
| 6 | Basse | Archive de transfert : noms de fichiers non vérifiés (`../`), objets R2 étrangers, réglages et photos du profil acceptés tels quels, archive illisible retentée à chaque ouverture. | Identifiants et noms d'objets validés, réglages et photos écartés, archive abandonnée après un échec. | `une_archive_aux_noms_pieges_est_filtree` |
| 7 | Basse | Deux contrôles n'existaient que dans l'interface : envoi de l'historique vers une clé non vérifiée ; « vérifiée » posé sur la clé enregistrée et non sur celle contrôlée. | Contrôlés dans le cœur : `offer_history(partenaire, …)` exige une clé vérifiée ; `mark_verified(partenaire, clé)` refuse une autre clé. | `tests/transfer.rs`, `tests/backup.rs` |
| 8 | Basse | Contenus « d'une version future » stockés sans limite. | Plafond de 2 000. | — |
| 9 | Basse | Les 10 essais d'appairage par heure pouvaient être dépassés par des requêtes simultanées. | Verrou par compte. | — |
| 10 | Basse | Android : sauvegarde automatique non désactivée ; version finale signée avec la clé de test si la vraie manquait. | `allowBackup=false`, `data_extraction_rules.xml` ; la compilation finale s'arrête sans `key.properties`. | — |
| 11 | Info | Clé SQLCipher gardée en mémoire après usage ; fichiers temporaires SQLite possibles hors chiffrement. | Copies de la clé effacées (`zeroize`) ; `temp_store = MEMORY`. | — |

## Ce qui reste (limites connues)

- **Canaux temps réel publics encore permis** (Realtime → Settings → « Allow public access » actif). L'arrivée des
  enveloppes passait par un canal public (sans fuite : les règles d'accès filtrent ce qui est diffusé). Il devient
  privé dans l'app 1.0.0+5 (migration `…_canal_enveloppes_prive.sql`, déployée) ; l'accès public sera coupé quand
  plus aucun testeur n'aura l'ancienne version (le couper avant bloquerait la réception en direct).
- La fonction `push` reste appelable sans compte (par conception : le déclencheur n'a pas de secret) ; elle ne fait
  rien sans un identifiant d'enveloppe valide, mais chaque appel compte dans le quota d'appels Supabase.
- Avec **beaucoup** de comptes, un attaquant peut encore consommer beaucoup de place : les plafonds sont par compte.
  À surveiller (tableau de bord Supabase et Cloudflare), et à resserrer si besoin.
- Le serveur pourrait renvoyer une **ancienne** sauvegarde valide (pas de contrôle de fraîcheur).
- `leave_couple` reste appelable directement : les fichiers chiffrés du couple restent alors sur R2 (illisibles).
- Les clés de fichiers et le secret de sauvegarde ne sont pas tous effacés de la mémoire après usage.
- Pas encore de vecteurs de test officiels, de `cargo audit` automatisé, ni d'audit indépendant (§11 de
  `docs/SECURITY.md`).

## Périmètre et limites

Lecture complète du serveur (migrations, fonctions), du cœur Rust et des parties sensibles de l'app ; tests du
serveur réel de l'extérieur, sans compte et sans rien modifier. Pas de test d'intrusion sur un téléphone réel, pas de
revue de libsignal elle-même, pas d'analyse des dépendances Flutter.
