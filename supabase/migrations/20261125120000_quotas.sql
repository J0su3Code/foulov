-- Limites d'utilisation (revue de sécurité du 25 novembre 2026, docs/SECURITY.md §8).
--
-- L'inscription est ouverte : sans plafonds, un seul compte pouvait déposer sans fin des fichiers de 220 Mo sur R2
-- (facture), et deux comptes d'une même personne pouvaient remplir la base (5 Go en attente par destinataire),
-- ce qui bloquait le service pour tout le monde. Les plafonds ci-dessous restent très au-dessus d'un usage normal.

-- ============================================================ enveloppes

-- Consommation par expéditeur et par jour (UTC) : nombre d'enveloppes et octets chiffrés.
create table public.envelope_usage (
  user_id  uuid not null references auth.users (id) on delete cascade,
  day      date not null default (now() at time zone 'utc')::date,
  count    integer not null default 0,
  bytes    bigint not null default 0,
  primary key (user_id, day)
);
alter table public.envelope_usage enable row level security;
-- Aucune politique : invisible des clients, tenue par le déclencheur ci-dessous.

-- Remplace le garde-fou de 20 000 enveloppes (jusqu'à 5 Go en attente par destinataire).
create or replace function public.limit_pending_envelopes() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  pending_count integer;
  pending_bytes bigint;
  used public.envelope_usage%rowtype;
begin
  -- En attente chez le destinataire : 5 000 enveloppes et 50 Mo au plus (un téléphone hors ligne une semaine en
  -- accumule quelques centaines, de quelques Ko chacune).
  select count(*), coalesce(sum(octet_length(e.ciphertext)), 0) into pending_count, pending_bytes
    from public.envelopes e where e.recipient_id = new.recipient_id;
  if pending_count >= 5000 or pending_bytes + octet_length(new.ciphertext) > 50 * 1024 * 1024 then
    raise exception 'trop d''enveloppes en attente' using errcode = 'P0001';
  end if;
  -- Par expéditeur et par jour : 20 000 enveloppes et 200 Mo.
  insert into public.envelope_usage as u (user_id, count, bytes)
    values (new.sender_id, 1, octet_length(new.ciphertext))
    on conflict (user_id, day) do update set count = u.count + 1, bytes = u.bytes + excluded.bytes
    returning * into used;
  if used.count > 20000 or used.bytes > 200 * 1024 * 1024 then
    raise exception 'limite quotidienne d''envoi atteinte' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_pending_envelopes() from public, anon, authenticated;

-- ============================================================ fichiers sur R2

-- Liens d'envoi délivrés par la fonction `media`, par compte et par jour (photos, vidéos, sauvegardes, transferts).
create table public.media_usage (
  user_id  uuid not null references auth.users (id) on delete cascade,
  day      date not null default (now() at time zone 'utc')::date,
  uploads  integer not null default 0,
  bytes    bigint not null default 0,
  primary key (user_id, day)
);
alter table public.media_usage enable row level security;

-- Réserve `size` octets pour un envoi de l'utilisateur courant. Échoue (et ne compte rien) au-delà de :
-- 300 envois et 3 Go par jour, 15 Go sur 30 jours glissants.
create function public.take_media_quota(size bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  today public.media_usage%rowtype;
  month bigint;
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  if size is null or size < 1 or size > 600 * 1024 * 1024 then
    raise exception 'taille invalide' using errcode = '22023';
  end if;
  insert into public.media_usage as u (user_id, uploads, bytes) values (me, 1, size)
    on conflict (user_id, day) do update set uploads = u.uploads + 1, bytes = u.bytes + excluded.bytes
    returning * into today;
  select coalesce(sum(m.bytes), 0) into month from public.media_usage m
    where m.user_id = me and m.day > (now() at time zone 'utc')::date - 30;
  if today.uploads > 300 or today.bytes > 3::bigint * 1024 * 1024 * 1024 or month > 15::bigint * 1024 * 1024 * 1024 then
    raise exception 'limite d''envoi de fichiers atteinte' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function public.take_media_quota(bigint) from public, anon;
grant execute on function public.take_media_quota(bigint) to authenticated;

-- Nettoyage : les compteurs de plus de 40 jours ne servent plus.
create function public.purge_usage() returns void
language sql security definer set search_path = '' as $$
  delete from public.envelope_usage where day < (now() at time zone 'utc')::date - 40;
  delete from public.media_usage where day < (now() at time zone 'utc')::date - 40;
$$;
revoke all on function public.purge_usage() from public, anon, authenticated;
select cron.schedule('foulove-compteurs', '23 4 * * *', $$select public.purge_usage()$$);

-- ============================================================ appairage

-- Les 10 essais par heure étaient comptés puis enregistrés sans verrou : des requêtes simultanées pouvaient en
-- passer davantage. Un verrou par compte (le temps de la transaction) rend le compte exact.
create or replace function public.join_couple(token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  inv public.invitations%rowtype;
  code text := public.normalize_invitation_code(token);
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended('foulove-join:' || me::text, 0));
  if (select count(*) from public.join_attempts where user_id = me and at > now() - interval '1 hour') >= 10 then
    raise exception 'trop de tentatives, réessaie dans une heure' using errcode = 'P0001';
  end if;
  insert into public.join_attempts (user_id) values (me);
  if exists (select 1 from public.couple_members where user_id = me) then
    raise exception 'déjà dans un couple' using errcode = 'P0001';
  end if;
  if length(code) <> 10 then return null; end if;
  select * into inv from public.invitations
    where token_hash = extensions.digest(code, 'sha256') and used_at is null and expires_at > now()
    for update;
  if not found then return null; end if;
  insert into public.couple_members (couple_id, user_id) values (inv.couple_id, me);
  update public.invitations set used_at = now() where id = inv.id;
  return inv.couple_id;
end;
$$;
