-- Canal temps réel des enveloppes en privé (revue de sécurité du 25 novembre 2026).
--
-- L'app écoutait l'arrivée de ses enveloppes sur un canal public `enveloppes-<son identifiant>`. Rien n'y fuyait (les
-- insertions diffusées respectent les règles d'accès de public.envelopes), mais un canal public empêche de désactiver
-- l'accès public de Realtime pour tout le projet. Désormais, seul le titulaire du compte peut rejoindre ce canal,
-- en privé. Une fois toutes les versions de l'app à jour (1.0.0+5 et plus), désactiver dans Supabase :
-- Realtime → Settings → « Allow public access ».
create policy "enveloppes : écouter son canal" on realtime.messages
  for select to authenticated
  using (realtime.topic() = 'enveloppes-' || (select auth.uid())::text);
