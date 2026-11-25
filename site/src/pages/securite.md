---
layout: ../layouts/Doc.astro
title: Comment FouLove protège votre bulle
eyebrow: Sécurité
description: Le chiffrement de bout en bout de FouLove expliqué simplement, ce dont il vous protège, et ses limites, dites clairement.
intro: Cette page explique simplement comment FouLove protège ce que vous partagez, ce dont elle vous protège, et ce qu’elle ne peut pas faire. Pour les détails techniques, notre document de conception est public.
updated: 25 novembre 2026
---

## Le principe : chiffré de bout en bout

Quand vous envoyez un message, une photo ou une lettre, votre téléphone le **chiffre** avant qu’il ne parte : il le transforme en une suite de caractères illisible. Seul le téléphone de votre amour possède la clé qui permet de le relire.

Entre les deux, nos serveurs ne font que transporter et ranger ces données illisibles. **Nous n’avons pas les clés** : elles sont créées sur vos téléphones et n’en sortent jamais. Même si quelqu’un s’emparait de nos serveurs, il n’y trouverait aucun message lisible.

Tout est chiffré de la même façon : messages, vocaux, photos et vidéos, instants, lettres et capsules, albums, et même votre profil de couple (prénoms, bio, dates, photo à deux).

## Ce dont FouLove vous protège

| Menace | Ce qui vous protège |
|---|---|
| Une fuite ou un piratage de nos serveurs | Ils ne contiennent que des données chiffrées et des clés publiques |
| Quelqu’un qui écoute le réseau (Wi-Fi public, opérateur) | Le chiffrement de bout en bout, en plus de la connexion sécurisée (TLS) |
| Quelqu’un qui se glisserait entre vous au moment de l’invitation | Vos téléphones vérifient leurs clés, grâce au secret de l’invitation, au QR code ou à vos liens échangés par une autre messagerie |
| Quelqu’un qui devine un code d’invitation | Code à usage unique, expirant en 24 h, tentatives limitées ; une bulle ne peut jamais compter plus de deux personnes |
| Un téléphone perdu ou volé, verrouillé | Les données de l’app sont rangées dans une base chiffrée, dont la clé est protégée par la puce de sécurité du téléphone |
| Quelqu’un qui emprunte votre téléphone | Le code FouLove, et l’empreinte ou le visage ; un code oublié ne se contourne pas en se reconnectant |
| Les ordinateurs quantiques de demain | Un échange de clés « post-quantique », conçu pour qu’on ne puisse pas déchiffrer plus tard ce qui est enregistré aujourd’hui |
| Les services de notification (Google) | Les notifications ont un texte fixe, sans nom ni contenu |

## Ce que FouLove ne peut pas faire

Nous préférons vous le dire clairement :

- **Un téléphone déverrouillé ou infecté** par un logiciel espion voit ce que vous voyez. Gardez votre téléphone à jour et verrouillé.
- **Votre partenaire** peut photographier son écran avec un autre appareil, comme avec n’importe quelle messagerie.
- **La contrainte** : si quelqu’un vous force à ouvrir l’app, le chiffrement n’y peut rien.
- **Certaines informations restent visibles** de nos serveurs, pour que les messages arrivent : votre adresse e-mail, le fait que vos deux comptes sont liés, l’heure et la taille arrondie des envois. La liste complète est sur la page [Confidentialité](/confidentialite/).
- **Les capsules** sont scellées par l’app jusqu’au jour choisi. C’est une promesse de l’app, pas un coffre-fort qui s’ouvrirait de lui-même à une date.

## Des briques éprouvées, rien d’inventé

En sécurité, inventer son propre chiffrement est la première erreur à ne pas commettre. FouLove s’appuie uniquement sur des outils reconnus :

- le **protocole Signal**, via la bibliothèque officielle *libsignal*, avec l’échange de clés **PQXDH** (protégé contre les ordinateurs quantiques grâce à ML-KEM-1024) et le *double ratchet* : voler les clés d’aujourd’hui ne permet pas de lire les messages d’hier ;
- **AES-256-GCM** pour les photos et vidéos, chiffrées par blocs, avec une taille arrondie pour ne pas trahir leur poids exact ;
- **SQLCipher** pour la base de données sur votre téléphone ;
- **Argon2id** pour protéger le code FouLove.

Avant l’envoi, les photos et vidéos sont réencodées sur votre téléphone : leur **position GPS** et les autres informations cachées sont retirées.

## Vérifier, plutôt que croire

- **Le code est public.** Tout FouLove, l’app, le cœur de chiffrement et le serveur, est publié sous licence AGPL-3.0 : [github.com/J0su3Code/foulov](https://github.com/J0su3Code/foulov).
- **La conception est publique.** Chaque promesse de l’app renvoie à notre [document de conception](https://github.com/J0su3Code/foulov/blob/main/docs/SECURITY.md), avec ses limites.
- **Les règles d’accès sont testées.** Des tests automatiques vérifient qu’un compte ne peut rien lire d’un autre couple.

- **Une revue de sécurité complète est publiée.** Le 25 novembre 2026, tout le code et le serveur ont été relus à la recherche de failles ; les problèmes trouvés ont été corrigés et le [rapport](https://github.com/J0su3Code/foulov/blob/main/docs/revue/2026-11-revue-securite.md) est public.

> **Pas encore d’audit indépendant.** Cette revue a été faite avec une intelligence artificielle, pas par une société de sécurité extérieure. Un audit indépendant est prévu. D’ici là, nous ne prétendrons pas être « plus sûrs » qu’une autre messagerie.

## Vous avez trouvé une faille ?

Merci de nous l’écrire en privé, avant de la rendre publique : **[hello@josuecode.com](mailto:hello@josuecode.com?subject=Faille%20de%20s%C3%A9curit%C3%A9)**, avec pour objet « Faille de sécurité ». Nous accusons réception sous 72 heures, puis nous vous informons de la correction.

Merci de ne pas accéder aux données d’autres personnes, et de ne pas perturber le service pendant vos recherches.
