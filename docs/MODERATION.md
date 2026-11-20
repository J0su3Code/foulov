# Traiter un signalement

Procédure interne derrière les engagements publiés sur https://foulove.vercel.app/securite-enfants/ et dans les
conditions d'utilisation. Les échanges sont chiffrés de bout en bout : on agit sur le **compte**, jamais sur le contenu,
qu'on ne peut pas lire. Les signalements arrivent à hello@josuecode.com (app : Réglages → Aide → Signaler un problème).

## 1. Lire et trier (le jour même)

- Objet « Signalement — sécurité des enfants » : à traiter **avant tout le reste**.
- Identifier le compte visé : l'adresse e-mail donnée par la personne qui signale, ou celle de son partenaire
  (Supabase → Table Editor → `couple_members`, en partant du compte de la personne qui signale).
- Danger immédiat pour un enfant : prévenir tout de suite les autorités (17 / 112 en France).

## 2. Bloquer le compte

Supabase → Authentication → Users → le compte → **Ban user** (durée longue). Il ne peut plus se reconnecter ; sa
session en cours expire en une heure au plus.

## 3. Conserver les éléments

Avant toute suppression, garder (hors du dépôt, dans un dossier privé) :
- le signalement et ses pièces jointes ;
- l'identifiant, l'adresse e-mail, `created_at` et `last_sign_in_at` du compte ;
- l'identifiant de son couple (`couple_members.couple_id`) et la date de création du couple.

Durée : le temps prévu par la loi ou demandé par les autorités ; sinon un an au plus (voir la politique de
confidentialité).

## 4. Signaler aux autorités (contenus d'abus sur enfant)

- NCMEC CyberTipline : https://report.cybertip.org (compte « Electronic Service Provider » à demander une fois).
- France : PHAROS, https://www.internet-signalement.gouv.fr.
- Répondre aux réquisitions des forces de l'ordre avec les seuls éléments du point 3.

## 5. Supprimer

1. Cloudflare → R2 → `foulovmedia-private` : supprimer les préfixes `c/<couple_id>/` et `b/<user_id>/`.
   (La suppression depuis le tableau de bord Supabase **ne touche pas** R2 : la fonction `account` le fait seulement
   quand c'est l'utilisateur qui supprime son compte.)
2. Supabase → Table Editor → `couples` : supprimer la ligne `<couple_id>` (cascade : membres, invitations,
   enveloppes ; c'est ce que fait `leave_couple`). Indispensable si c'est l'autre qui avait créé la bulle.
3. Supabase → Authentication → Users → **Delete user** : la base supprime en cascade le profil, l'appareil, les clés
   et les jetons de notification.
4. Répondre à la personne qui a signalé, sans détail qui pourrait nuire à une enquête.
