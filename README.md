# FouLove

L'espace privé d'un couple : messages, photos, souvenirs et un jardin qui pousse avec votre histoire.
Tout est chiffré de bout en bout, sur vos deux téléphones.

> Projet en cours de développement. Rien n'est encore publié sur les stores.

## Ce que FouLove promet, mot pour mot

- Vos messages, photos, vidéos et souvenirs sont chiffrés sur votre téléphone, puis déchiffrés uniquement sur celui de votre partenaire.
- Nos serveurs ne stockent que des données chiffrées. FouLove n'a pas vos clés.
- Ce que nos serveurs voient quand même : que vos deux comptes sont liés, l'heure d'envoi d'un contenu et la taille des fichiers.
- Si vous perdez vos deux téléphones sans votre phrase de récupération, vos échanges sont perdus. Personne ne peut les récupérer, pas même nous.

Le code est publié pour que chacun puisse vérifier ces promesses. Aucune affirmation de type « plus sûr que… » ne sera faite avant un audit de sécurité indépendant.

## Architecture prévue

| Couche | Choix |
|---|---|
| App | Flutter (Android, iOS), police système |
| Compte | Supabase Auth : Google, Apple ou code à usage unique par e-mail. Aucun mot de passe. |
| Données | Supabase Postgres avec règles d'accès strictes (seuls les deux membres d'un couple) |
| Médias | Cloudflare R2, fichiers chiffrés avant l'envoi, URLs pré-signées |
| Chiffrement | Clés propres à chaque téléphone (Android Keystore / Secure Enclave), appairage par QR code + vérification de 7 symboles, protocole de la famille Signal, échange de clés hybride post-quantique, phrase de récupération |
| Notifications | Texte fixe, sans contenu |

## Dépôt

| Dossier | Contenu |
|---|---|
| `app/` | Application Flutter |
| `animation/` | Intro cinématique : scène Blender et textures générées par code ([détails](animation/README.md)) |
| `design/` | Maquettes |

## Licence

Code sous licence [GNU AGPL-3.0](LICENSE).
Le nom « FouLove » et le logo ne sont pas couverts par cette licence.
Les éléments 3D et matières de Poly Haven utilisés pour l'intro sont sous licence CC0.
