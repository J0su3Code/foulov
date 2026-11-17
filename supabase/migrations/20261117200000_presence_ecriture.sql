-- Indicateurs « en ligne » et « en train d'écrire » (docs/SECURITY.md §10).
--
-- Canal temps réel privé `couple:<identifiant du couple>` (Supabase Realtime, autorisation par RLS) : seuls les
-- deux membres du couple peuvent y écouter ou y publier. Les messages qui y passent ne contiennent aucun contenu,
-- seulement « présent » et « écrit en ce moment ». Chacun peut les désactiver dans l'app.

create policy "couple : écouter son canal" on realtime.messages
  for select to authenticated
  using (realtime.topic() = 'couple:' || (select public.my_couple_id())::text);

create policy "couple : publier sur son canal" on realtime.messages
  for insert to authenticated
  with check (realtime.topic() = 'couple:' || (select public.my_couple_id())::text);
