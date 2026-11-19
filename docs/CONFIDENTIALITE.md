# Politique de confidentialité de FouLove

*Dernière mise à jour : 19 novembre 2026*

FouLove est une messagerie privée pour les couples. Elle est conçue pour que **personne d'autre que vous deux**,
pas même nous, ne puisse lire ce que vous partagez. Cette page explique, sans jargon, ce que nous recevons, ce que
nous ne recevons jamais, et ce que vous pouvez faire.

**Éditeur et contact** : [NOM DE L'ÉDITEUR] — [ADRESSE E-MAIL DE CONTACT]

---

## 1. Ce qui reste entre vous deux (chiffré de bout en bout)

Ces contenus sont chiffrés sur votre téléphone **avant** de partir, et ne se déchiffrent que sur celui de votre
partenaire. Nos serveurs ne transportent que des données illisibles, et nous n'avons pas les clés :

- vos messages, réactions, réponses, messages vocaux ;
- vos photos, vidéos et leurs légendes ;
- vos instants, lettres et capsules ;
- votre profil de couple : prénoms, surnoms, bio, votre histoire, vos anniversaires, vos dates, la photo à deux, la
  couverture, le fond et les couleurs de votre conversation ;
- vos albums et vos souvenirs ;
- votre sauvegarde (chiffrée avec une clé tirée de votre phrase de 24 mots, que nous n'avons jamais).

Sur votre téléphone, ces données sont rangées dans une base chiffrée. Le code FouLove et le verrouillage par
empreinte protègent l'accès à l'app.

## 2. Ce que nos serveurs voient quand même

Pour acheminer vos messages, certaines informations sont nécessairement visibles de nos serveurs :

| Information | Pourquoi |
|---|---|
| Votre adresse e-mail, ou votre identifiant Google ou Apple | Vous connecter |
| Que vos deux comptes forment un couple | Acheminer les messages entre vous |
| L'heure à laquelle un contenu chiffré est envoyé, et leur nombre | Acheminer et ordonner |
| La taille approximative des contenus chiffrés (arrondie) | Les stocker |
| Le jeton de notification de votre téléphone | Vous prévenir d'un nouveau message (texte fixe, jamais de contenu) |
| Quand vous avez l'app ouverte (« en ligne ») et quand vous écrivez (« écrit… ») — désactivable | Les indicateurs de présence |
| Les clés publiques de votre téléphone | Permettre le chiffrement |
| Les adresses IP, dans les journaux techniques de nos hébergeurs | Le fonctionnement du réseau |

Nous ne voyons **jamais** : le contenu de vos échanges, vos photos, vos noms de fichiers, vos légendes, vos dates, vos
surnoms, votre bio, vos lettres, vos instants, votre carnet d'adresses ou votre numéro de téléphone.

## 3. Ce que nous ne faisons pas

- Aucune publicité.
- Aucune revente, aucun partage de vos données à des fins commerciales.
- Aucun outil de mesure d'audience, aucun traceur publicitaire.
- Aucune lecture de vos échanges : techniquement, nous ne le pouvons pas.

## 4. Nos hébergeurs (sous-traitants)

| Service | Rôle | Lieu |
|---|---|---|
| Supabase | Comptes, acheminement des messages chiffrés | Union européenne (Francfort, Allemagne) |
| Cloudflare R2 | Stockage des fichiers chiffrés (photos, vidéos, vocaux, sauvegardes) | Réseau Cloudflare |
| Google Firebase Cloud Messaging | Envoi des notifications (texte fixe, sans contenu) | Google |
| Google Sign-In / Sign in with Apple | Connexion, si vous les choisissez | Google / Apple |

Ces services ne reçoivent que des données chiffrées ou les informations techniques listées au point 2.

## 5. Combien de temps

- **Messages en transit** : supprimés du serveur dès que le téléphone de votre partenaire les a reçus, et au plus tard
  après 30 jours s'ils ne sont jamais récupérés.
- **Fichiers chiffrés** (photos, vidéos, vocaux) : tant que votre bulle existe ; supprimés quand vous fermez votre
  bulle ou supprimez votre compte. Les fichiers des instants sont supprimés après 24 heures.
- **Sauvegarde chiffrée** : une seule, remplacée à chaque nouvelle sauvegarde ; supprimée avec votre compte ou quand la
  bulle est fermée.
- **Compte** : jusqu'à ce que vous le supprimiez.
- **Tentatives d'appairage** (anti-abus) : 1 jour.

## 6. Vos droits et vos choix

- **Fermer votre bulle** : Réglages → Zone sensible → *Fermer notre bulle*. Tout le contenu partagé est effacé de nos
  serveurs ; votre compte reste.
- **Supprimer votre compte** : Réglages → Zone sensible → *Supprimer mon compte* (ou, sans bulle, le menu « … » de
  l'accueil). Votre compte et toutes les données qui s'y rattachent sont supprimés de nos serveurs, et l'app efface ce
  téléphone. Vous pouvez aussi le demander par e-mail : voir [la page dédiée](SUPPRESSION-COMPTE.md).
- **Indicateurs « en ligne » et « écrit… »** : désactivables dans les réglages.
- Conformément au RGPD, vous pouvez demander l'accès, la rectification ou l'effacement des données vous concernant, et
  introduire une réclamation auprès de l'autorité de protection des données de votre pays (en France, la CNIL).
  Écrivez-nous : [ADRESSE E-MAIL DE CONTACT].

Comme vos échanges sont chiffrés de bout en bout, ils ne sont lisibles que sur vos téléphones : si vous perdez vos deux
téléphones sans votre phrase de récupération, personne ne peut les récupérer, pas même nous.

## 7. Âge

FouLove s'adresse aux personnes de 16 ans et plus.

## 8. Code ouvert

Le code de FouLove est public, pour que chacun puisse vérifier ces promesses :
[github.com/J0su3Code/foulov](https://github.com/J0su3Code/foulov). Les détails techniques sont dans
[SECURITY.md](SECURITY.md).

## 9. Modifications

Si cette politique change, la date en haut de page est mise à jour, et l'app vous le signale pour tout changement
important.
