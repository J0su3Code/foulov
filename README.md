# FouLove

L'espace privé d'un couple, « une bulle à deux ». Messages, instants, souvenirs, lettres et capsules :
tout est chiffré de bout en bout, sur vos deux téléphones.

> En développement. Pas encore publié sur les stores (Android d'abord, iPhone ensuite).
> Site : **[foulove.josuecode.com](https://foulove.josuecode.com)** — guide, sécurité, confidentialité, suppression du compte.

## Ce que FouLove promet, mot pour mot

- Vos messages, photos, vidéos, lettres et souvenirs sont chiffrés sur votre téléphone, et ne se déchiffrent que sur
  celui de votre partenaire.
- Nos serveurs ne stockent que des données chiffrées. FouLove n'a pas vos clés.
- Ce que nos serveurs voient quand même : que vos deux comptes sont liés, quand un contenu est envoyé, et sa taille
  arrondie. Le détail est dans [docs/SECURITY.md](docs/SECURITY.md) (§10).
- Si vous perdez vos deux téléphones sans votre phrase de récupération, vos échanges sont perdus. Personne ne peut les
  récupérer, pas même nous.

Le code est publié pour que chacun puisse vérifier ces promesses. Aucune affirmation de type « plus sûr que… » ne sera
faite avant un audit de sécurité indépendant.

## L'app

Quatre onglets : **Nous · Messages · Souvenirs · Lettres**. Crème et framboise le jour, prune la nuit.

| | |
|---|---|
| **Nous** (accueil) | Votre profil de couple : couverture, photo à deux, bio, jours ensemble, jours de flamme, vos instants, la prochaine date, le dernier mot doux |
| **Notre histoire** | Votre rencontre racontée, l'anniversaire de chacun, vos étapes (1 semaine → 50 ans), vous en chiffres, vos dates importantes (avec rappels) |
| **Instants** | Photo, vidéo (30 s) ou texte, visibles 24 h ; vu, réponse, retrait |
| **Messages** | Texte, photos, vidéos, vocaux, réactions, réponses, « en ligne » et « écrit… » (désactivables), suppression pour soi ou pour les deux |
| **Personnaliser** | 8 thèmes, 12 fonds en dégradé animé, 7 motifs dessinés, votre photo (flou, assombrissement), 4 styles et 3 formes de bulles, 16 couleurs, taille du texte |
| **Souvenirs** | Photos et vidéos par mois, albums partagés, vocaux |
| **Lettres** | Lettres longues, et capsules scellées jusqu'au jour choisi |

Sécurité au quotidien :

- **Appairage** : invitation envoyée par une autre messagerie (ou QR code), clés vérifiées automatiquement, sans
  symboles à comparer. Les 7 symboles restent possibles en appel vidéo.
- **Code FouLove** (6 chiffres), même si le téléphone n'a pas de verrouillage ; empreinte ou visage en raccourci.
- **Sauvegarde chiffrée** quotidienne avec une phrase de 24 mots ; ou, sur un nouveau téléphone, **récupération de
  l'historique depuis le téléphone de l'autre** (il accepte sur son écran).

## Architecture

| Couche | Choix |
|---|---|
| App | Flutter (Android, iOS), police système |
| Cœur cryptographique | Rust (`core/`) : libsignal (PQXDH avec ML-KEM-1024, double ratchet), base SQLCipher, fichiers en AES-256-GCM (STREAM) avec remplissage Padmé, Argon2id, HKDF, HMAC — rien d'inventé |
| Compte | Supabase Auth : Google, Apple ou code à usage unique par e-mail. Aucun mot de passe. |
| Données | Supabase Postgres, règles d'accès strictes (seuls les deux membres d'un couple), tests pgTAP |
| Veille | GitHub Actions appelle chaque jour `public.ping()`, pour que le plan gratuit de Supabase ne mette pas le projet en pause |
| Médias | Cloudflare R2, fichiers chiffrés avant l'envoi, liens pré-signés de courte durée |
| Notifications | Firebase (FCM) : texte fixe, jamais de contenu |

Conception complète, menaces couvertes et limites assumées : [docs/SECURITY.md](docs/SECURITY.md).

## Dépôt

| Dossier | Contenu |
|---|---|
| `app/` | Application Flutter (et le pont vers le cœur Rust) |
| `core/` | Cœur cryptographique en Rust, avec ses tests (`cargo test`) |
| `supabase/` | Schéma, règles d'accès, fonctions (`media`, `push`), tests |
| `animation/` | Intro « une bulle à deux » et icône : scènes Blender générées par code ([détails](animation/README.md)) |
| `design/` | Maquettes |
| `site/` | Site public (Astro, déployé à la main sur Vercel) : guide, pages légales, suppression du compte ([détails](site/README.md)) |
| `docs/` | Conception de la sécurité, publication Google Play |

## Licence

Code sous licence [GNU AGPL-3.0](LICENSE).
Le nom « FouLove » et le logo ne sont pas couverts par cette licence.
Éclairage et éléments 3D de [Poly Haven](https://polyhaven.com) sous licence CC0. Photos des maquettes :
[Unsplash](https://unsplash.com) (via Picsum), licence Unsplash.
