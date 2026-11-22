# Architecture de sécurité de FouLove

Version 0.1, 16 novembre 2026. Document de conception : rien de ce qui suit n'est encore audité.
Chaque promesse affichée dans l'app doit pouvoir être reliée à une section de ce document.

## 1. Objectifs

1. Seuls les deux téléphones d'un couple peuvent lire ce que le couple échange : messages, photos, vidéos, souvenirs, profil du couple, instants, lettres.
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
- Les clés privées ne sont jamais exportées, pas même dans la sauvegarde chiffrée (§7) : un téléphone restauré crée une nouvelle identité.

## 4bis. Messagerie

Implémentation : `core/src/chat.rs` (testée dans `core/tests/chat.rs`), transport dans `app/lib/features/chat/chat_service.dart`.

- **Contenu structuré puis chiffré.** Chaque contenu (texte, réponse citée, réaction, accusé « distribué » ou « lu ») est encodé en protobuf, précédé d'un octet de version, puis chiffré par la session Signal (§4).
- **Longueur masquée.** Avant chiffrement, le contenu est complété jusqu'au multiple de 160 octets suivant (remplissage de Signal : `0x80` puis des zéros). « Oui » et une phrase de 47 caractères donnent la même taille chiffrée ; un accusé de lecture, une réaction et un message court sont indiscernables par leur taille.
- **Modification d'un message.** L'auteur peut modifier un texte (ou la légende d'une photo ou vidéo) pendant 15 minutes après l'envoi. La modification est un contenu chiffré comme les autres ; elle ne réveille pas le téléphone du partenaire (`urgent` faux). Le destinataire ne l'applique qu'à un message de son auteur, avec une heure de modification plausible (après l'envoi, pas dans le futur, dans les 15 minutes à 2 minutes près pour les horloges), et seulement si elle arrive moins d'un jour après le message lui-même : un téléphone trafiqué ne peut pas réécrire un vieux message en mentant sur l'heure. La modification la plus récente l'emporte. Les vocaux et les stickers ne se modifient pas.
- **Stickers.** Un sticker voyage comme une photo (fichier chiffré sur R2, §6), sous un numéro de contenu à part : une version de l'app qui ne le connaît pas le garde chiffré dans la base locale et l'affiche après sa mise à jour. La bibliothèque de stickers (enregistrés, importés, favoris) reste dans la base SQLCipher du téléphone ; rien n'en est envoyé tant qu'on n'envoie pas un sticker. Le pack de stickers FouLove (commun à tous, non personnel) est rangé sur un seau R2 privé : la fonction `media` signe des liens de lecture par lots pour un utilisateur connecté ; les fichiers téléchargés restent en cache sur le téléphone. Le serveur peut savoir qu'un compte charge des stickers du pack, pas à qui ils sont envoyés : l'envoi reste chiffré comme une photo.
- **Historique uniquement sur les téléphones**, dans la base SQLCipher (§7). Le serveur ne garde une enveloppe que jusqu'à sa réception : le destinataire la supprime dès qu'elle est enregistrée. Une enveloppe jamais récupérée est effacée après 30 jours.
- **Ni perte, ni doublon, ni état incohérent.**
  - Déchiffrer et enregistrer se font dans une seule transaction : si l'app s'arrête au milieu, ni le ratchet ni l'historique n'avancent, et l'enveloppe est simplement retraitée.
  - Chaque enveloppe porte un identifiant aléatoire choisi par l'expéditeur. Une enveloppe déjà traitée n'est jamais appliquée deux fois.
  - À l'envoi, le message et son enveloppe chiffrée sont enregistrés ensemble dans une boîte d'envoi locale. Après une coupure réseau ou un redémarrage, la même enveloppe est renvoyée, jamais rechiffrée ; le serveur refuse le doublon par sa clé primaire.
- **Altération.** Une enveloppe modifiée en route est rejetée et écartée sans bloquer les suivantes. Un test modifie chaque octet, un par un : jamais un contenu modifié n'est accepté. Seuls des champs d'acheminement que Signal n'authentifie pas par conception (numéro de version, identifiants de pré-clés, et le chiffré ML-KEM quand la session est déjà ouverte) peuvent changer sans effet, le contenu restant intact.
- **Réception instantanée** par Supabase Realtime, filtrée par les règles d'accès : chacun n'est averti que des enveloppes qui lui sont destinées. À chaque reconnexion, l'app récupère tout ce qui est en attente.
- **Clé du partenaire changée** : les nouvelles enveloppes restent sur le serveur, non lues, et l'app demande de recomparer les 7 symboles (§5.7).

## 4ter. Dates importantes

- Chaque date (titre, jour, « chaque année », rappel) voyage **chiffrée** par la session Signal ; le serveur n'en voit rien. La modification la plus récente l'emporte, date par date ; une suppression laisse une trace datée pour qu'une ancienne version arrivée en retard ne la fasse pas réapparaître.
- Les **rappels sont programmés par le téléphone lui-même** (notifications locales) : aucun serveur ne sait quand ni quoi. Sur l'écran verrouillé, leur texte reste masqué si le téléphone masque les contenus sensibles.

## 4quater. Notre espace (profil du couple, instants, albums, lettres)

Code : `core/src/space.rs`, tests `core/tests/space.rs`.

- **Même transport que les messages.** Bio, histoire, anniversaires, style des bulles, photos du couple, instants,
  albums et lettres sont des contenus protobuf de la session Signal, remplis au multiple de 160 octets : le serveur ne
  distingue pas une lettre d'un message (seule la taille arrondie et l'indicateur `urgent` sont visibles).
- **Le plus récent l'emporte.** Réglages, photos du couple et albums sont horodatés ; une version ancienne arrivée en
  retard ne remplace jamais une plus récente. Les valeurs reçues sont validées (longueurs, formats, emplacements connus) ;
  une clé inconnue (version future) est ignorée.
- **Valeurs personnelles.** L'anniversaire et la couleur des bulles décrivent leur auteur : rangés `me.*` chez lui,
  `p.*` chez l'autre. L'année de naissance est facultative. Le surnom donné à l'autre ne quitte pas le téléphone.
- **Photos du couple** (photo à deux, couverture, fond) : fichiers chiffrés sur R2 exactement comme les photos de la
  conversation (§6). Remplacée ou retirée, l'ancienne est effacée du téléphone, et son auteur la supprime de R2 (table
  `r2_trash`). Une photo remplacée pendant son dépôt n'est jamais envoyée, et son objet part aussi à la corbeille.
- **Instants (24 h).** Photo, vidéo (30 s) ou texte. Passé 24 h (ou retirés par leur auteur), ils sont effacés des deux
  téléphones et leurs fichiers retirés de R2. Un instant arrivé après son expiration n'est pas affiché. Ils ne figurent
  **jamais** dans la sauvegarde. « Vu » n'est envoyé qu'une fois. Une réponse est un message ordinaire qui copie le texte
  et la miniature de l'instant.
- **Capsules.** Une lettre dont l'ouverture est datée arrive tout de suite, chiffrée, et l'app la garde **scellée** chez
  les deux jusqu'à la date (le texte n'est pas rendu par le cœur avant). C'est une promesse de l'app, **pas** un verrou
  cryptographique dans le temps : quelqu'un qui extrairait la base SQLCipher déverrouillée de son propre téléphone
  pourrait la lire avant. L'interface ne prétend rien de plus.
- **Chiffres et jours de flamme** : calculés sur le téléphone à partir de l'historique local, jamais envoyés.

## 5. Appairage du couple

1. **Inès crée l'espace.** Le serveur crée un couple et un **code d'invitation** de 10 caractères en alphabet Crockford base32, par exemple `K7Q4M-9XHPT`.
   - L'alphabet exclut I, L, O et U ; à la saisie, I et L sont lus comme 1, et O comme 0.
   - Le code vaut 50 bits, s'utilise une seule fois et expire après 24 h.
   - Seul son hachage SHA-256 est stocké sur le serveur.
2. **En personne : QR code.** Le QR code d'Inès contient le code et l'empreinte de sa clé d'identité, `SHA-256("FouLov-ID-v1" ‖ clé)`. Malik le scanne :
   - son téléphone compare cette empreinte à la clé publiée par le serveur ; si elles diffèrent, l'appairage s'arrête et rien n'est envoyé ;
   - si elles correspondent, la clé d'Inès est marquée « vérifiée » chez Malik, sans action de sa part ;
   - côté Inès, la vérification se fait en comparant les 7 symboles : ils sont côte à côte, il suffit de regarder les deux écrans.
   Depuis l'invitation v2 (point 3), le QR code contient aussi le secret d'appairage : la clé de Malik est alors confirmée automatiquement chez Inès.
3. **À distance : l'invitation complète** (`core/src/invite.rs`, tests `core/tests/invite.rs`). Inès l'envoie par une
   autre messagerie (WhatsApp, SMS…) ; Malik la copie et la colle. Elle contient `foulove:2:<code>:<empreinte>:<secret>` :
   - l'**empreinte** de la clé d'Inès : le téléphone de Malik la compare à la clé publiée par le serveur (comme le QR) ;
   - un **secret de 128 bits**, tiré sur le téléphone d'Inès et jamais envoyé à notre serveur. Le premier message
     chiffré de Malik contient `HMAC-SHA256(secret, « FouLove-join-v1 » ‖ clé de Malik ‖ clé d'Inès)` ; le téléphone
     d'Inès la recalcule avec la clé de la session ouverte : si elle correspond, la clé de Malik est vérifiée.
   - Résultat : **aucun symbole à comparer**, et un serveur malveillant ne peut pas se glisser entre vous sans le contenu
     de l'invitation. Limite assumée : si la même personne contrôle notre serveur **et** la messagerie qui a transporté
     l'invitation, elle pourrait le faire. Les 7 symboles restent alors la vérification ultime, en appel vidéo.
   - Le QR code contient la même invitation : en personne aussi, les deux côtés sont vérifiés automatiquement.
   - Le code seul (10 caractères tapés) marche toujours ; il faut alors comparer les 7 symboles
     (`SHA-256("FouLov-SAS-v1" ‖ longueurs ‖ clés triées)`, 64 symboles, 42 bits).
4. **Nouveau téléphone : liens de retrouvailles.** Chacun peut envoyer `foulove:id:<empreinte de sa clé>` par une autre
   messagerie ; l'autre le colle, et la clé est acceptée si elle correspond exactement à celle reçue. Même modèle de
   confiance que l'invitation (la messagerie qui transporte le lien doit être distincte de notre serveur).
5. **Protection contre les essais au hasard** : 10 tentatives par heure et par compte. Un code invalide ne déclenche pas d'erreur, pour que la tentative soit bien comptée. Avec 50 bits, même un très grand nombre de comptes ne suffit pas pour tomber sur un code actif.
6. **Plafond de deux membres** : la base refuse un troisième membre, par une contrainte en base et pas seulement dans l'app.
7. **Si la clé de l'autre change** (nouveau téléphone), l'app l'annonce de façon visible et demande une nouvelle vérification.

## 6. Photos, vidéos et fichiers

0. **Métadonnées retirées avant tout** : une photo est réencodée en JPEG (2048 px au plus) sur le téléphone, ce qui supprime ses données EXIF (position GPS, modèle du téléphone, date de prise de vue). Elles ne quittent jamais le téléphone.
1. Pour chaque fichier, le téléphone génère une **clé aléatoire de 256 bits**.
2. Le fichier est chiffré en **blocs de 64 Kio** avec AES-256-GCM. Chaque bloc a un nonce dérivé de son numéro et un drapeau « dernier bloc » : on ne peut ni réordonner, ni tronquer, ni mélanger des blocs sans que ça se détecte.
3. **Taille masquée** : le fichier chiffré est complété jusqu'au palier suivant, environ +12 % au maximum, pour ne pas révéler la taille exacte.
4. Envoi vers le bucket privé R2 `foulovmedia-private`, via une **URL pré-signée** courte (5 min), délivrée par la fonction serveur `media` après vérification que l'utilisateur appartient au couple. Le nom de l'objet est aléatoire (`c/<couple>/<128 bits>`), et **la taille exacte du fichier chiffré fait partie de la signature** (SigV4 écrite avec WebCrypto, `supabase/functions/media/presign.ts`) : un lien ne permet de déposer qu'un objet de cette taille, sous ce nom. Chacun n'obtient de lien de lecture que pour les objets de son couple.
5. La clé du fichier, son empreinte SHA-256 et ses métadonnées (type, dimensions, légende) **voyagent à l'intérieur du message chiffré**, jamais en clair.
6. Les miniatures sont des fichiers à part, chiffrés de la même façon.
7. Le bucket public `foulovmedia` n'est pas utilisé pour les contenus des couples.
8. **Réception** : la miniature (dans le message chiffré) s'affiche aussitôt ; le fichier est téléchargé, sa taille et son empreinte SHA-256 vérifiées, sinon il est effacé et marqué illisible.
9. **Vidéos** : réencodées en MP4 720p sur le téléphone (ce qui retire aussi leurs métadonnées, position comprise), puis chiffrées par blocs depuis le fichier, sans jamais être chargées entières en mémoire. Les copies en clair créées par le réencodage et par le sélecteur sont effacées dès le chiffrement terminé. Chaque bloc STREAM s'authentifie seul (numéro de bloc et drapeau « dernier bloc » dans le nonce) : on peut lire n'importe quelle plage, et une altération ou une troncature est détectée.
10. **Lecture des vidéos sans fichier en clair** : le lecteur du système lit une adresse locale (`video_proxy.dart`). Ce serveur interne n'écoute que sur 127.0.0.1, exige un jeton aléatoire de 128 bits propre à chaque lancement de l'app, et déchiffre à la volée les plages demandées. Android n'autorise le HTTP non chiffré que vers 127.0.0.1 (`network_security_config.xml`) ; tout le reste passe par TLS.
11. **Sur le téléphone, les fichiers restent chiffrés** ; leur clé ne quitte jamais la base SQLCipher. Une photo n'est déchiffrée qu'**en mémoire**, pour l'affichage : rien n'est jamais écrit en clair, et les photos n'apparaissent pas dans la galerie du téléphone.

## 7. Stockage local, verrouillage et récupération

- **Base locale** : SQLCipher. Sa clé de 256 bits est aléatoire et enveloppée par une clé matérielle non exportable : Android Keystore, ou Keychain iOS accessible seulement sur cet appareil, après le premier déverrouillage.
- **Verrouillage de l'app** (activé par défaut dès que le téléphone a un verrouillage d'écran) : empreinte, visage ou code du téléphone à l'ouverture et après une minute en arrière-plan. Le désactiver demande de s'authentifier. Sur Android 13 et plus, la vignette des apps récentes ne montre pas la conversation, sans bloquer les captures d'écran.
  - *Choix assumé, comme Signal* : c'est un verrou d'accès à l'interface. La clé de la base n'exige **pas** l'empreinte pour être utilisée : sur Android, une clé liée à l'authentification est détruite si l'utilisateur retire le verrouillage d'écran de son téléphone, et tout l'historique serait perdu. Une personne qui obtient le téléphone **déverrouillé** et le code de l'app pourrait donc lire la base. Ce choix sera réexaminé quand la sauvegarde chiffrée existera.
- **Effacement à distance** du contenu local par l'utilisateur depuis un autre appareil : prévu plus tard.
- **Sauvegarde chiffrée** (activée par défaut, désactivable) :
  - à la création du compte, l'app affiche une **phrase de récupération de 24 mots** (256 bits) à noter sur papier ;
  - clé de sauvegarde dérivée de la phrase (détail ci-dessous) ;
  - la sauvegarde (historique, clés des fichiers, profil du couple, albums, lettres) est chiffrée avec cette clé puis déposée sur R2 ;
  - **sans la phrase, personne ne peut la lire, pas même nous**. Phrase perdue et téléphones perdus = données perdues. L'app le dit clairement.
- **Clé de chaque sauvegarde** : HKDF-SHA256(secret de la phrase, sel aléatoire de 256 bits). La phrase vaut déjà 256 bits aléatoires (BIP39, liste française, accents facultatifs à la saisie) : une dérivation lente comme Argon2 n'ajouterait rien contre la force brute. La sauvegarde ne contient **jamais** les clés Signal.
- **Restauration** sur un nouveau téléphone : après la connexion, l'app propose la phrase si une sauvegarde existe et que le téléphone n'a aucun historique (écran protégé contre les captures). Le téléphone crée une **nouvelle identité**, rouvre une session avec le partenaire et le couple compare ses 7 symboles.
- **Côté partenaire** : à chaque chargement, l'app compare la clé publiée par le serveur à celle en laquelle elle a confiance. Si elles diffèrent, l'écran « La clé de ton amour a changé » s'affiche avant tout le reste ; les nouveaux messages restent chiffrés et illisibles jusqu'à la comparaison des 7 symboles de la nouvelle clé. Une substitution par le serveur se verrait ainsi immédiatement.

### Code FouLove (`core/src/pin.rs`, `app/lib/features/lock/app_lock.dart`)

- Six chiffres propres à l'app, utilisables même si le téléphone n'a aucun verrouillage d'écran.
- Seule une empreinte **Argon2id** est gardée (sel aléatoire de 128 bits, 46 Mio, 1 passe, réglage OWASP), dans le
  coffre du système. Six chiffres ne font que 10⁶ possibilités : la protection vient de l'empreinte enfermée dans le
  coffre et des **délais** imposés après 5 erreurs (30 s, puis doublés jusqu'à 1 h), conservés même si l'app est
  fermée. C'est un verrou d'interface, comme celui du téléphone ; la base locale reste chiffrée par sa propre clé.
- Changer ou retirer le code demande le code actuel. **Code oublié** : reconnexion par e-mail, puis le code est retiré.
- L'empreinte ou le visage peuvent servir de raccourci.

### Récupérer l'historique depuis l'autre téléphone (`core/src/transfer.rs`, tests `core/tests/transfer.rs`)

Pour un nouveau téléphone sans phrase de récupération :
- il **demande** l'historique par un message chiffré (identifiant aléatoire) ; seule une réponse à cette demande est
  acceptée ;
- l'autre téléphone ne propose d'accepter que si la clé du nouveau téléphone est **vérifiée** (symboles ou liens) ;
- s'il accepte, son historique (messages, clés des photos et vidéos, dates, albums, lettres — jamais les clés Signal
  ni les instants) est emballé **vu depuis l'autre côté**, chiffré avec une clé aléatoire (STREAM AES-256-GCM, Padmé),
  déposé sur R2 comme une photo ; la clé et l'empreinte SHA-256 voyagent dans un message chiffré ;
- le nouveau téléphone vérifie l'empreinte, importe, puis retire l'archive de R2. Le serveur ne voit qu'un fichier
  illisible de taille arrondie.

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
- **Fermer sa bulle / supprimer son compte** (`supabase/functions/account`, migration `…_fermer_bulle.sql`, tests
  `fermer_bulle.test.sql`) : les fichiers chiffrés du couple (`c/<couple>/`) et la sauvegarde (`b/<compte>/`) sont
  supprimés de R2, puis l'espace (cascade : membres, invitations, enveloppes) ; pour un compte, l'utilisateur lui-même
  (cascade : tout le reste). Le téléphone est remis à zéro (base, fichiers, clés, rappels). L'autre téléphone voit
  « Votre bulle a été fermée » et peut tout effacer à son tour (sa sauvegarde comprise).
- **Nettoyage automatique** (pg_cron) : enveloppes jamais récupérées après 30 jours, tentatives d'appairage après 1 jour.

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
| Quand l'un de vous a l'app ouverte (« en ligne ») et quand il écrit (« écrit… »), jamais ce qu'il écrit. Canal temps réel privé, réservé aux deux membres du couple par les règles d'accès. **Désactivable** dans les Réglages (rubrique Confidentialité) (on ne voit alors plus non plus ceux de l'autre) | Indicateurs de présence et d'écriture |
| Les adresses IP, dans les journaux techniques de nos hébergeurs (Supabase, Cloudflare), selon leurs politiques | Fonctionnement du réseau ; nous n'ajoutons aucun journal applicatif contenant des IP |

Jamais : contenu, noms de fichiers, légendes, dates du couple, surnoms, bio, histoire, anniversaires, lettres, instants, carnet d'adresses, numéro de téléphone.

## 11. Ce qu'il reste à faire avant d'affirmer quoi que ce soit publiquement

- [x] Implémentation du cœur `core/` avec tests (`cargo test`) ; vecteurs de test officiels encore à ajouter.
- [x] Tests automatisés des règles d'accès Supabase (pgTAP, `supabase/tests/database/`).
- [ ] Revue de code externe de `core/` et des règles serveur.
- [ ] **Audit de sécurité indépendant** avant toute comparaison publique avec d'autres messageries.
- [ ] Programme de signalement de vulnérabilités (adresse dédiée, délai de réponse publié).
