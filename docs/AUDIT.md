# Revue de sécurité de FouLove : le cahier des charges

Ce document prépare une **revue complète du code et de la sécurité**, à confier à une nouvelle session de Claude
Code, puis plus tard à une société d'audit indépendante. Il dit quoi examiner, dans quel ordre, et ce qu'on attend en
retour.

## Ce qu'une revue par Claude est, et n'est pas

Une revue par une IA est très utile : elle lit tout le code, cherche les erreurs connues, écrit des tests qui les
prouvent et propose des corrections. Mais ce n'est **pas un audit indépendant** au sens où l'entendent les
utilisateurs et les spécialistes : personne d'extérieur n'en porte la responsabilité, et elle n'est pas faite par des
cryptographes. Après la revue, le site pourra dire « revue de sécurité complète publiée » (avec le rapport), mais pas
« audité ».

Pour un vrai audit plus tard, sans budget :
- [Open Technology Fund — Red Team Lab](https://www.opentech.fund/labs/red-team-lab/) : audits gratuits pour les
  logiciels libres qui protègent la vie privée.
- [NLnet / NGI](https://nlnet.nl/) : financements européens pour le logiciel libre, audits de sécurité compris
  (réalisés par Radically Open Security).
- [OSTIF](https://ostif.org/) : organise et finance des audits de projets open source.

## Périmètre, par ordre d'importance

1. **Cœur cryptographique** (`core/src/`) : sessions libsignal (`session.rs`), chiffrement des fichiers STREAM et
   remplissage Padmé (`chat_media.rs`), invitation v2 et preuve HMAC (`invite.rs`), transfert d'historique
   (`transfer.rs`), sauvegarde (`backup.rs`, dérivation depuis la phrase BIP39), code FouLove Argon2id (`pin.rs`), base
   SQLCipher (`store.rs`). Questions : clés et nonces jamais réutilisés ? Comparaisons en temps constant ? Données
   sensibles effacées de la mémoire ? Erreurs qui ne fuient rien ? Entrées venues du réseau toutes validées ?
2. **Serveur** (`supabase/`) : règles d'accès (RLS) de chaque table, fonctions SQL `security definer`
   (`leave_couple`, appairage), fonctions `media`, `account`, `push` (authentification, liens pré-signés R2 et taille
   signée, purge, CORS), limitation des tentatives, tâches pg_cron. Un compte peut-il atteindre les données d'un autre
   couple, ou faire grossir la facture ?
3. **Pont et app** (`app/rust/src/api/`, `app/lib/`) : rien de sensible en clair sur le disque ou dans les journaux,
   verrou de l'app (`lock/app_lock.dart`), serveur vidéo local (`video_proxy.dart`), liens profonds et invitations
   collées, presse-papiers, captures, notifications, `AndroidManifest.xml`.
4. **Site** (`site/`) : page « Supprimer mon compte » (pas de fuite d'existence de compte, jeton jamais stocké),
   en-têtes de sécurité.
5. **Cohérence** : chaque promesse du site et de l'app doit correspondre au code et à `docs/SECURITY.md`.

## Méthode attendue

- Lire `docs/SECURITY.md` (modèle de menace) avant le code.
- Pour chaque problème : gravité (critique, haute, moyenne, basse), fichier et ligne, scénario d'attaque concret, et
  si possible **un test qui échoue** (`cargo test`, pgTAP dans `supabase/tests/database/`), puis la correction.
- Faire tourner les outils : `cargo audit` et `cargo deny` (dépendances Rust), `cargo clippy`, `flutter analyze`,
  `supabase db lint`, et les tests existants (68 tests Rust, 56 tests pgTAP).
- Ne rien déployer en production sans l'accord de l'éditeur ; ne jamais afficher de clé ou de mot de passe.

## Ce qu'on attend en retour

- Un rapport `docs/revue/2026-11-revue-securite.md` : résumé, tableau des problèmes, ce qui a été corrigé, ce qui
  reste, et les limites de la revue.
- Les corrections, avec leurs tests, en commits séparés.
- `docs/SECURITY.md` §11 mis à jour.

## Le message à donner à la nouvelle session

> Fais une revue de sécurité et une revue de code complètes de FouLove, en suivant `docs/AUDIT.md`. Commence par lire
> `docs/SECURITY.md`. Classe chaque problème par gravité, prouve-le par un test quand c'est possible, corrige-le, et
> écris le rapport demandé. Ne déploie rien en production sans me demander. Réponds-moi toujours en français simple.
