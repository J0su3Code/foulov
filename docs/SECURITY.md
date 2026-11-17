# Architecture de sécurité de FouLove

Version 0.1, 16 novembre 2026. Document de conception : rien de ce qui suit n'est encore audité.
Chaque promesse affichée dans l'app doit pouvoir être reliée à une section de ce document.

## 1. Objectifs

1. Seuls les deux téléphones d'un couple peuvent lire ce que le couple échange : messages, photos, vidéos, souvenirs, données du jardin.
2. Une fuite complète de nos serveurs (base de données, stockage, sauvegardes, journaux) ne révèle aucun contenu.
3. Personne ne peut se glisser entre les deux partenaires au moment de l'appairage sans que ça se voie.
4. Collecter le minimum de métadonnées, et dire exactement lesquelles.
5. Utiliser uniquement de la cryptographie éprouvée. **On n'invente aucun algorithme ni protocole.**

## 2. Modèle de menace

### Ce dont on protège

| Adversaire | Exemple | Protection |
|---|---|---|
| Serveur compromis | Fuite de la base Supabase ou du stockage R2, employé malveillant, réquisition | Chiffrement de bout en bout : le serveur ne détient que des données chiffrées et des clés publiques (§4, §6) |
| Attaquant réseau | Wi-Fi public, opérateur | TLS partout, en plus du chiffrement de bout en bout |
| Homme du milieu à l'appairage | Le serveur substitue ses propres clés | Vérification hors ligne : QR code ou 7 symboles comparés à voix haute (§5) |
| Intrus qui tente de rejoindre un couple | Code d'invitation deviné | Jetons à usage unique, longs, expirant en 24 h, tentatives limitées, couple plafonné à deux membres par la base (§5, §8) |
| Téléphone volé verrouillé | Perte, vol | Base locale chiffrée, clé protégée par la puce sécurisée du téléphone et libérée seulement après déverrouillage (§7) |
| Ordinateurs quantiques futurs | « Enregistrer maintenant, déchiffrer plus tard » | Échange de clés hybride classique + ML-KEM-1024, et ratchet post-quantique SPQR (§4) |
| Services de notification | Google (FCM), Apple (APNs) | Notifications à texte fixe, aucun contenu ni nom (§9) |

### Ce dont on ne peut pas protéger (et qu'on dira clairement)

- **Un téléphone déverrouillé ou infecté** par un logiciel espion : il voit ce que voit l'utilisateur.
- **Le partenaire lui-même** : il peut photographier son écran avec un autre appareil. Le blocage des captures d'écran fonctionne sur Android, pas parfaitement sur iOS.
- **La contrainte physique** : quelqu'un qui force l'utilisateur à déverrouiller.
- **Les métadonnées listées au §10**, qui restent visibles du serveur.

## 3. Briques retenues

| Rôle | Brique | Pourquoi |
|---|---|---|
| Protocole de messagerie | [libsignal](https://github.com/signalapp/libsignal) (`libsignal-protocol`, Rust, AGPL-3.0-only), version épinglée | Implémentation de référence de Signal : X3DH/PQXDH, Double Ratchet, SPQR |
| Post-quantique | ML-KEM-1024 via `libcrux-ml-kem` (inclus dans libsignal) | Implémentation vérifiée formellement |
| Chiffrement des fichiers | AES-256-GCM en flux par blocs (§6) via les crates RustCrypto (`aes-gcm`, `hkdf`, `sha2`) | Standard, rapide grâce à l'accélération matérielle AES des téléphones |
| Dérivation depuis la phrase de récupération | Argon2id (`argon2`) | Résiste aux attaques par GPU |
| Pont Flutter ↔ Rust | `flutter_rust_bridge` | Un seul cœur cryptographique, identique sur Android et iOS |
| Base locale | SQLite + SQLCipher | Chiffrement de toute la base sur le téléphone |
| Coffre à clés | Android Keystore (StrongBox si disponible), iOS Keychain + Secure Enclave | La clé ne quitte jamais la puce sécurisée |

Toute la cryptographie vit dans une seule bibliothèque Rust (`core/`). Le code Dart n'implémente aucun algorithme : il appelle le cœur.

## 4. Identité et sessions

- **Une paire de clés d'identité par téléphone** (Curve25519), générée sur l'appareil.
  Version 1 : un seul téléphone actif par personne. Le multi-appareil viendra plus tard, avec la même rigueur.
- Le téléphone publie sur le serveur uniquement des **clés publiques** : clé d'identité, pré-clé signée, pré-clés ML-KEM-1024 signées et pré-clés à usage unique.
- La première session est établie par **PQXDH** (X25519 + ML-KEM-1024). Les messages suivants passent par le **triple ratchet** de libsignal (Double Ratchet + SPQR), qui apporte :
  - la *confidentialité persistante* : voler les clés d'aujourd'hui ne permet pas de lire les messages d'hier ;
  - l'*auto-guérison* : après une compromission passagère, les clés suivantes redeviennent sûres.
- Les clés privées ne sont jamais exportées, sauf dans la sauvegarde chiffrée (§7), et seulement si l'utilisateur l'active.

## 4bis. Messagerie

Implémentation : `core/src/chat.rs` (testée dans `core/tests/chat.rs`), transport dans `app/lib/features/chat/chat_service.dart`.

- **Contenu structuré puis chiffré.** Chaque contenu (texte, réponse citée, réaction, accusé « distribué » ou « lu ») est encodé en protobuf, précédé d'un octet de version, puis chiffré par la session Signal (§4).
- **Longueur masquée.** Avant chiffrement, le contenu est complété jusqu'au multiple de 160 octets suivant (remplissage de Signal : `0x80` puis des zéros). « Oui » et une phrase de 47 caractères donnent la même taille chiffrée ; un accusé de lecture, une réaction et un message court sont indiscernables par leur taille.
- **Historique uniquement sur les téléphones**, dans la base SQLCipher (§7). Le serveur ne garde une enveloppe que jusqu'à sa réception : le destinataire la supprime dès qu'elle est enregistrée. Une enveloppe jamais récupérée est effacée après 30 jours.
- **Ni perte, ni doublon, ni état incohérent.**
  - Déchiffrer et enregistrer se font dans une seule transaction : si l'app s'arrête au milieu, ni le ratchet ni l'historique n'avancent, et l'enveloppe est simplement retraitée.
  - Chaque enveloppe porte un identifiant aléatoire choisi par l'expéditeur. Une enveloppe déjà traitée n'est jamais appliquée deux fois.
  - À l'envoi, le message et son enveloppe chiffrée sont enregistrés ensemble dans une boîte d'envoi locale. Après une coupure réseau ou un redémarrage, la même enveloppe est renvoyée, jamais rechiffrée ; le serveur refuse le doublon par sa clé primaire.
- **Altération.** Une enveloppe modifiée en route est rejetée et écartée sans bloquer les suivantes. Un test modifie chaque octet, un par un : jamais un contenu modifié n'est accepté. Seuls des champs d'acheminement que Signal n'authentifie pas par conception (numéro de version, identifiants de pré-clés, et le chiffré ML-KEM quand la session est déjà ouverte) peuvent changer sans effet, le contenu restant intact.
- **Réception instantanée** par Supabase Realtime, filtrée par les règles d'accès : chacun n'est averti que des enveloppes qui lui sont destinées. À chaque reconnexion, l'app récupère tout ce qui est en attente.
- **Clé du partenaire changée** : les nouvelles enveloppes restent sur le serveur, non lues, et l'app demande de recomparer les 7 symboles (§5.7).

## 5. Appairage du couple

1. **Inès crée l'espace.** Le serveur crée un couple et un **code d'invitation** de 10 caractères en alphabet Crockford base32, par exemple `K7Q4M-9XHPT`.
   - L'alphabet exclut I, L, O et U ; à la saisie, I et L sont lus comme 1, et O comme 0.
   - Le code vaut 50 bits, s'utilise une seule fois et expire après 24 h.
   - Seul son hachage SHA-256 est stocké sur le serveur.
2. **En personne : QR code.** Le QR code d'Inès contient le code et l'empreinte de sa clé d'identité, `SHA-256("FouLov-ID-v1" ‖ clé)`. Malik le scanne :
   - son téléphone compare cette empreinte à la clé publiée par le serveur ; si elles diffèrent, l'appairage s'arrête et rien n'est envoyé ;
   - si elles correspondent, la clé d'Inès est marquée « vérifiée » chez Malik, sans action de sa part ;
   - côté Inès, la vérification se fait en comparant les 7 symboles : ils sont côte à côte, il suffit de regarder les deux écrans.
   *Prévu* : un secret d'appairage de 128 bits, inclus dans le QR code et jamais envoyé au serveur, pour confirmer aussi automatiquement la clé de Malik chez Inès.
3. **À distance : le code.** Inès dicte ou envoie le code, et Malik le tape. Les deux écrans affichent ensuite **7 symboles** :
   - ils sont dérivés de `SHA-256("FouLov-SAS-v1" ‖ longueurs ‖ clé_identité_A ‖ clé_identité_B)`, avec les clés triées, puis tirés d'une liste de 64 symboles (42 bits) ;
   - le couple les compare à voix haute ou en appel vidéo ;
   - tant que ce n'est pas fait, l'app affiche « clés non vérifiées ».
4. **Plus tard, lien d'invitation** (quand le domaine sera actif) : `https://foulove.org/rejoindre#K7Q4M9XHPT`. Le code est placé après le `#`, une partie du lien qui n'est jamais envoyée à un serveur web. Si le lien passe par une autre messagerie, celle-ci voit le code. Mais le code permet seulement de rejoindre, une seule fois, et la vérification par symboles détecte toute substitution de clé.
5. **Protection contre les essais au hasard** : 10 tentatives par heure et par compte. Un code invalide ne déclenche pas d'erreur, pour que la tentative soit bien comptée. Avec 50 bits, même un très grand nombre de comptes ne suffit pas pour tomber sur un code actif.
6. **Plafond de deux membres** : la base refuse un troisième membre, par une contrainte en base et pas seulement dans l'app.
7. **Si la clé de l'autre change** (nouveau téléphone), l'app l'annonce de façon visible et demande une nouvelle vérification.

## 6. Photos, vidéos et fichiers

1. Pour chaque fichier, le téléphone génère une **clé aléatoire de 256 bits**.
2. Le fichier est chiffré en **blocs de 64 Kio** avec AES-256-GCM. Chaque bloc a un nonce dérivé de son numéro et un drapeau « dernier bloc » : on ne peut ni réordonner, ni tronquer, ni mélanger des blocs sans que ça se détecte.
3. **Taille masquée** : le fichier chiffré est complété jusqu'au palier suivant, environ +12 % au maximum, pour ne pas révéler la taille exacte.
4. Envoi vers le bucket privé R2 `foulovmedia-private`, via une **URL pré-signée** courte (5 min), délivrée par une fonction serveur après vérification que l'utilisateur appartient au couple. Le nom de l'objet est un identifiant aléatoire.
5. La clé du fichier, son empreinte SHA-256 et ses métadonnées (type, dimensions, légende) **voyagent à l'intérieur du message chiffré**, jamais en clair.
6. Les miniatures sont des fichiers à part, chiffrés de la même façon.
7. Le bucket public `foulovmedia` n'est pas utilisé pour les contenus des couples.

## 7. Stockage local, verrouillage et récupération

- **Base locale** : SQLCipher. Sa clé de 256 bits est aléatoire et enveloppée par une clé matérielle non exportable : Android Keystore, ou Keychain iOS accessible seulement sur cet appareil, après le premier déverrouillage.
- **Verrouillage de l'app** (activé par défaut dès que le téléphone a un verrouillage d'écran) : empreinte, visage ou code du téléphone à l'ouverture et après une minute en arrière-plan. Le désactiver demande de s'authentifier. Sur Android 13 et plus, la vignette des apps récentes ne montre pas la conversation, sans bloquer les captures d'écran.
  - *Choix assumé, comme Signal* : c'est un verrou d'accès à l'interface. La clé de la base n'exige **pas** l'empreinte pour être utilisée : sur Android, une clé liée à l'authentification est détruite si l'utilisateur retire le verrouillage d'écran de son téléphone, et tout l'historique serait perdu. Une personne qui obtient le téléphone **déverrouillé** et le code de l'app pourrait donc lire la base. Ce choix sera réexaminé quand la sauvegarde chiffrée existera.
- **Effacement à distance** du contenu local par l'utilisateur depuis un autre appareil : prévu plus tard.
- **Sauvegarde chiffrée** (activée par défaut, désactivable) :
  - à la création du compte, l'app affiche une **phrase de récupération de 24 mots** (256 bits) à noter sur papier ;
  - clé de sauvegarde = Argon2id(phrase, sel stocké avec la sauvegarde) ;
  - la sauvegarde (historique, clés des fichiers, état du jardin) est chiffrée avec cette clé puis déposée sur R2 ;
  - **sans la phrase, personne ne peut la lire, pas même nous**. Phrase perdue et téléphones perdus = données perdues. L'app le dit clairement.
- **Restauration** sur un nouveau téléphone : nouvelles clés d'identité, restauration de l'historique depuis la sauvegarde, puis nouvelle vérification avec le partenaire (§5.6).

## 8. Serveur (Supabase)

- **Comptes** : Supabase Auth, avec Google, Apple ou code à usage unique par e-mail. Aucun mot de passe.
- **Règles d'accès (RLS)** activées sur **toutes** les tables, sans exception. Un utilisateur ne lit et n'écrit que :
  - son propre profil technique ;
  - les lignes du couple dont il est membre ;
  - les clés publiques de son partenaire.
- **Le serveur ne stocke** que : enveloppes chiffrées, clés publiques, appartenance au couple, jetons d'invitation hachés, jetons de notification.
- **Pas de liste** de couples ou d'utilisateurs accessible aux clients.
- Les opérations sensibles (rejoindre un couple, URL pré-signée) passent par des **fonctions serveur**, avec limitation des tentatives.
- Les règles d'accès sont **testées automatiquement** : une suite de tests vérifie qu'un utilisateur A ne peut rien lire du couple B.
- Les clés secrètes Supabase et R2 ne sont **jamais** dans l'app ni dans le dépôt.

## 9. Notifications

Une fonction serveur (`supabase/functions/push`) envoie une notification au texte fixe, « FouLove · Nouveau message 💌 », sans contenu, sans nom, sans aperçu. Le contenu est déchiffré seulement quand l'utilisateur ouvre l'app.

- Chaque enveloppe porte un indicateur `urgent`, comme chez Signal : vrai pour un message ou une réaction, faux pour un accusé de réception, qui ne réveille donc jamais le téléphone. C'est la seule information ajoutée pour les notifications.
- Le déclencheur en base transmet à la fonction le seul identifiant de l'enveloppe (aléatoire). La fonction vérifie elle-même que l'enveloppe est urgente, récente et pas encore notifiée : une seule notification par enveloppe, aucun secret stocké en base.
- La cible est l'identifiant d'installation Firebase (FID) du téléphone, gardé dans une table fermée aux clients. Il est retiré à la déconnexion.
- Plusieurs messages d'affilée remplacent la même notification ; elle s'efface à l'ouverture de la conversation.

## 10. Métadonnées visibles du serveur

C'est la liste exacte affichée dans l'app :

| Visible | Pourquoi |
|---|---|
| Votre adresse e-mail (ou identifiant Google/Apple) | Se connecter |
| Que deux comptes forment un couple | Acheminer les messages |
| L'heure d'envoi de chaque contenu | Acheminer et ordonner |
| Le nombre d'enveloppes échangées et leur rythme. Le serveur ne distingue pas un message d'un accusé de lecture ou d'une réaction, mais un rythme (message puis accusé quelques secondes après) peut se deviner | Acheminer |
| La taille approximative des contenus chiffrés (§6.3) | Stockage |
| Les jetons de notification | Réveiller l'app |
| Les adresses IP, dans les journaux techniques de nos hébergeurs (Supabase, Cloudflare), selon leurs politiques | Fonctionnement du réseau ; nous n'ajoutons aucun journal applicatif contenant des IP |

Jamais : contenu, noms de fichiers, légendes, dates du couple, surnoms, réponses aux questions, état du jardin, carnet d'adresses, numéro de téléphone.

## 11. Ce qu'il reste à faire avant d'affirmer quoi que ce soit publiquement

- [ ] Implémentation du cœur `core/` avec tests unitaires et vecteurs de test.
- [ ] Tests automatisés des règles d'accès Supabase.
- [ ] Revue de code externe de `core/` et des règles serveur.
- [ ] **Audit de sécurité indépendant** avant toute comparaison publique avec d'autres messageries.
- [ ] Programme de signalement de vulnérabilités (adresse dédiée, délai de réponse publié).
