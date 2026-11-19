-- Fermer sa bulle, supprimer son compte, nettoyage automatique (docs/SECURITY.md §8).
--
-- « Fermer notre bulle » : l'espace du couple est supprimé, et avec lui (en cascade) ses deux membres, ses
-- invitations et toutes les enveloppes en attente. Les fichiers chiffrés sur R2 sont retirés juste avant par la
-- fonction `account` (le serveur ne peut pas les lire, mais ils n'ont plus rien à faire là).
-- « Supprimer mon compte » : la fonction `account` supprime l'utilisateur (auth.users) ; tout ce qui le concerne
-- part en cascade (profil, appareil et pré-clés, jetons de notification, espace qu'il a créé ou rejoint).

create function public.leave_couple() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  c uuid := public.my_couple_id();
begin
  if c is null then
    raise exception 'aucun espace à fermer' using errcode = 'P0002';
  end if;
  delete from public.couples where id = c;
  return c;
end;
$$;
revoke all on function public.leave_couple() from public, anon;
grant execute on function public.leave_couple() to authenticated;

-- Nettoyage automatique (pg_cron) : enveloppes jamais récupérées après 30 jours, tentatives d'appairage après 1 jour.
create extension if not exists pg_cron;
select cron.schedule('foulove-enveloppes-oubliees', '17 3 * * *', $$select public.purge_stale_envelopes()$$);
select cron.schedule('foulove-tentatives-appairage', '41 * * * *', $$select public.purge_join_attempts()$$);
