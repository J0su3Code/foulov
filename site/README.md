# Site de FouLove

Site public : **https://foulove.vercel.app** — présentation, guide pas à pas, sécurité, confidentialité, conditions,
sécurité des enfants, aide, et suppression du compte **sans l'app** (exigences Google Play).

Site statique [Astro](https://astro.build), sans cookie, sans mesure d'audience, sans rien charger d'un autre site
(polices hébergées ici). Seule la page « Supprimer mon compte » parle à Supabase (code par e-mail, puis fonction
`account`).

| Page | Fichier |
|---|---|
| Accueil | `src/pages/index.astro` (maquettes de l'app en HTML : `src/components/screens/`) |
| Guide pas à pas | `src/pages/guide.md` |
| Sécurité | `src/pages/securite.md` |
| Confidentialité (version de référence) | `src/pages/confidentialite.md` |
| Conditions d'utilisation | `src/pages/conditions.md` |
| Sécurité des enfants | `src/pages/securite-enfants.md` |
| Aide et signalement | `src/pages/aide.md` |
| Supprimer mon compte | `src/pages/supprimer-mon-compte.astro` |
| Mentions légales, 404 | `src/pages/mentions-legales.md`, `src/pages/404.astro` |

Polices : *Fraunces* (titres, réduite par `scripts/polices.sh`) et *Atkinson Hyperlegible Next* (texte), licence SIL OFL.
En-têtes de sécurité (CSP stricte, sans script en ligne) : `vercel.json`.

## Travailler dessus

```bash
npm install
npm run dev       # http://localhost:4321
npm run build     # dist/
```

## Mettre en ligne

Le projet Vercel (`foulove`, équipe `fou-lov`) n'est **pas** relié à GitHub : on déploie à la main, depuis ce dossier.

```bash
vercel deploy --prod
```

Nom de domaine : changer `SITE_URL` (ou la valeur par défaut dans `astro.config.mjs`) et `Links.siteUrl` dans
`app/lib/features/account/links.dart`, puis redéployer.
