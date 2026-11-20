# Supprimer votre compte FouLove

Page publique (aussi donnée à Google Play) : **https://foulove.vercel.app/supprimer-mon-compte/**

On peut y supprimer son compte **sans l'app** : un code est envoyé à l'adresse du compte (Supabase Auth, sans création
de compte), puis la page appelle la fonction `account` avec `{"action":"delete"}`, exactement comme l'app.
Source : [`site/src/pages/supprimer-mon-compte.astro`](../site/src/pages/supprimer-mon-compte.astro).
