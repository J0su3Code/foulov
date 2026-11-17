-- Messagerie : réception instantanée des enveloppes chiffrées (docs/SECURITY.md §4bis).
--
-- Supabase Realtime diffuse les insertions de public.envelopes. La diffusion applique les règles d'accès (RLS) :
-- chacun ne reçoit que les enveloppes qui lui sont destinées (politique « enveloppes : lire les siennes »).
-- Le contenu reste chiffré de bout en bout : le serveur ne transporte que des octets illisibles.
alter publication supabase_realtime add table public.envelopes;

-- L'identifiant de chaque enveloppe est choisi par le téléphone (UUID aléatoire) : un renvoi après une coupure
-- réseau réutilise le même identifiant, et la clé primaire refuse le doublon. Rien à ajouter côté schéma.

-- Garde-fou : au plus 20 000 enveloppes en attente par destinataire (un téléphone resté hors ligne longtemps
-- en accumule quelques centaines). Au-delà, le dépôt est refusé plutôt que de remplir la base.
create function public.limit_pending_envelopes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.envelopes where recipient_id = new.recipient_id) >= 20000 then
    raise exception 'trop d''enveloppes en attente' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_pending_envelopes() from public, anon, authenticated;
create trigger envelopes_pending_limit before insert on public.envelopes
  for each row execute function public.limit_pending_envelopes();

-- Les enveloppes jamais récupérées (compte abandonné) sont effacées après 30 jours.
create function public.purge_stale_envelopes() returns void
language sql security definer set search_path = '' as $$
  delete from public.envelopes where created_at < now() - interval '30 days';
$$;
revoke all on function public.purge_stale_envelopes() from public, anon, authenticated;
