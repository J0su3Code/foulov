# Publication sur Google Play — tout ce qu'il faut remplir

Tout est prêt à copier-coller dans la [Play Console](https://play.google.com/console). Les éléments entre crochets sont
à compléter par l'éditeur.

## 1. L'app

| Champ | Valeur |
|---|---|
| Nom de l'app (30 car. max) | **FouLove : une bulle à deux** |
| Identifiant | `org.foulov.app` |
| Langue par défaut | Français (France) |
| Type | Application, gratuite |
| Catégorie | Communication |
| Tags | Messagerie, Couple, Vie privée |
| E-mail de contact | josuecode@yahoo.com |
| Site web | https://github.com/J0su3Code/foulov |
| Politique de confidentialité | https://github.com/J0su3Code/foulov/blob/main/docs/CONFIDENTIALITE.md |
| Suppression du compte (lien) | https://github.com/J0su3Code/foulov/blob/main/docs/SUPPRESSION-COMPTE.md |

## 2. Fiche du Store

**Description courte** (80 car. max) :

> La messagerie privée de votre couple. Chiffrée de bout en bout, rien que vous deux.

**Description complète** (4 000 car. max) :

> FouLove, c'est votre bulle à deux : un espace rien qu'à vous, où chaque mot, chaque photo et chaque souvenir reste
> entre vous. Tout est chiffré sur votre téléphone, et seul celui de votre amour peut le lire. Pas même nous.
>
> 💞 NOUS — votre profil de couple
> Une photo à deux, une couverture, votre bio, vos jours ensemble et vos jours de flamme. Racontez votre rencontre,
> retrouvez l'anniversaire de chacun et célébrez vos étapes, de la première semaine à vos 50 ans.
>
> 💬 MESSAGES — rien que vous deux
> Mots doux, photos, vidéos, messages vocaux, réactions et réponses. Personnalisez votre conversation : 8 thèmes,
> des fonds en dégradé qui bougent doucement, des motifs (cœurs, étoiles, mots doux…), votre propre photo, 4 styles
> et 16 couleurs de bulles.
>
> ✨ INSTANTS — un moment de votre journée
> Une photo, une vidéo ou un mot, visible 24 heures, pour vous deux seulement.
>
> 📸 SOUVENIRS — tout ce que vous vous envoyez, rangé
> Vos photos et vidéos mois par mois, vos albums partagés, vos vocaux.
>
> 💌 LETTRES — les mots qui comptent
> Des lettres longues, à lire au calme, et des capsules qui ne s'ouvrent qu'au jour choisi.
>
> 🔒 UNE VRAIE CONFIDENTIALITÉ
> • Chiffrement de bout en bout (protocole Signal, avec protection post-quantique)
> • Aucune publicité, aucun traceur, aucune revente de données
> • Invitation à distance : vos téléphones se vérifient tout seuls
> • Code FouLove, même si votre téléphone n'a pas de verrouillage
> • Sauvegarde chiffrée avec une phrase de 24 mots, ou récupération depuis le téléphone de votre amour
> • Code public : chacun peut vérifier nos promesses
>
> FouLove ne demande ni votre numéro de téléphone, ni votre carnet d'adresses. Vous vous connectez avec Google ou un
> code reçu par e-mail.

## 3. Éléments graphiques

| Élément | Fichier |
|---|---|
| Icône 512 × 512 | `docs/play/icon-512.png` |
| Image de présentation 1 024 × 500 | `docs/play/feature-graphic.png` |
| Captures d'écran téléphone (2 à 8, 1 080 × 2 400) | `docs/play/captures/` — à faire avec un compte de démonstration (pas avec vos vraies photos) |

## 4. Sécurité des données (questionnaire)

**Votre app collecte-t-elle ou partage-t-elle des données utilisateur ?** Oui.
**Les données sont-elles chiffrées en transit ?** Oui (TLS, et chiffrement de bout en bout pour tout le contenu).
**Les utilisateurs peuvent-ils demander la suppression de leurs données ?** Oui (dans l'app, et par le lien ci-dessus).

| Catégorie Google | Collectée ? | Partagée ? | Facultatif ? | Usage | Remarque |
|---|---|---|---|---|---|
| Informations personnelles → **Adresse e-mail** | Oui | Non | Non | Gestion du compte | Connexion |
| Informations personnelles → Nom | Non | | | | Le prénom est chiffré de bout en bout : nous n'y avons pas accès |
| **Messages** (e-mails, SMS, autres messages in-app) | Non* | Non | | | *Chiffrés de bout en bout : Google précise que les données chiffrées de bout en bout, illisibles par le développeur, ne sont pas « collectées » |
| **Photos et vidéos** | Non* | Non | | | *Idem, chiffrées de bout en bout |
| **Fichiers audio** (vocaux) | Non* | Non | | | *Idem |
| Identifiants de l'appareil ou autres → **ID d'installation Firebase** | Oui | Non | Non | Fonctionnalités de l'app (notifications) | Supprimé à la déconnexion |
| Activité dans l'app → Autres actions (présence « en ligne », « écrit… ») | Oui | Non | **Oui** (désactivable) | Fonctionnalités de l'app | Jamais le contenu |
| Contacts, position, finances, santé, historique de navigation, journaux de plantage, diagnostics | Non | | | | |

Pratiques de sécurité à cocher : *Données chiffrées en transit* ; *Vous pouvez demander la suppression des données*.

## 5. Classification du contenu (IARC)

- Catégorie : **Réseaux sociaux / communication**.
- Les utilisateurs peuvent-ils communiquer entre eux ? **Oui** (uniquement entre les deux membres d'un couple, qui se
  sont invités l'un l'autre ; pas de mise en relation avec des inconnus).
- Partage de position : Non. Achats : Non. Contenus générés : oui, privés, entre deux personnes.
- Public visé : **16 ans et plus** (pas destiné aux enfants).

## 6. Autorisations et déclarations

| Autorisation | Pourquoi |
|---|---|
| `RECORD_AUDIO` | Enregistrer un message vocal, seulement quand on maintient le bouton micro |
| `CAMERA` (via le scanner de QR code et l'appareil photo) | Scanner le QR code d'invitation, prendre une photo ou une vidéo |
| `POST_NOTIFICATIONS` | Prévenir d'un nouveau message (texte fixe, sans contenu) et des rappels de vos dates |
| `INTERNET` | Acheminer les messages chiffrés |
| `USE_BIOMETRIC` | Ouvrir l'app avec l'empreinte ou le visage (facultatif) |
| `VIBRATE`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE` (FCM) | Notifications et reprise après une coupure réseau |

Aucune autorisation de stockage, de contacts ni de position.

- **Publicité** : l'app ne contient pas de publicité.
- **Identifiant publicitaire** : non utilisé.
- **Accès à l'app (pour la vérification Google)** : FouLove ne fonctionne qu'à deux. Fournir dans « Accès aux
  applications » un compte de démonstration déjà appairé, avec les instructions :
  « Connectez-vous avec le code reçu par e-mail à [adresse de démonstration] (ou donnez directement le code fixe de
  démonstration). L'espace est déjà relié à un second compte de démonstration ; vous pouvez écrire, envoyer des
  photos, publier un instant, écrire une lettre. Réglages → Zone sensible permet de fermer la bulle ou de supprimer
  le compte. »

## 7. Fabriquer et envoyer une version

```bash
cd app
# Augmenter le numéro de build dans pubspec.yaml (version: 1.0.0+N) à chaque envoi.
flutter build appbundle --release --dart-define-from-file=dart_defines.local.json
# Fichier à envoyer : build/app/outputs/bundle/release/app-release.aab
```

Signature : clé d'envoi `~/.foulove/foulove-upload.jks` (mot de passe dans `app/android/key.properties`, hors git ;
copie de sauvegarde dans le dossier `Secret Keys`). Activer la **signature d'application par Google Play** à la
première version : Google garde la clé de signature finale, et la clé d'envoi peut être remplacée si elle est perdue.

**Connexion Google** : *fait le 19 nov. 2026 pour la clé d'envoi.* Ajouter dans Firebase (Paramètres du projet → app Android `org.foulov.app` → Empreintes) :
- l'empreinte SHA-1 de la clé d'envoi : `20:5B:76:FD:9C:2F:7E:6A:94:84:22:D4:22:66:C6:EC:48:D4:68:20` ;
- son SHA-256 : `11:9B:18:CC:CF:FD:3E:65:99:44:16:1A:68:35:DE:ED:3F:4F:DF:A8:D4:49:62:43:07:6E:D8:20:B2:DF:26:14` ;
- après le premier envoi, l'empreinte de la **clé de signature d'application** indiquée par la Play Console
  (Intégrité de l'application → Signature de l'application).

Ces empreintes sont publiques (elles ne permettent pas de signer).
