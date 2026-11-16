-- FouLov : schéma initial.
-- Principes (docs/SECURITY.md §8) :
--   * le serveur ne stocke que des clés publiques, des enveloppes chiffrées et l'appartenance au couple ;
--   * RLS activé sur TOUTES les tables ; aucune table n'est lisible sans politique explicite ;
--   * les opérations sensibles passent par des fonctions SECURITY DEFINER au search_path vide ;
--   * un couple compte au plus deux membres, garanti par la base elle-même.

create extension if not exists pgcrypto with schema extensions;

-- ============================================================ tables

-- Profil technique : rien de personnel (pas de nom, pas de photo : ces données sont chiffrées côté couple).
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.couples (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- Une personne appartient à un seul couple (contrainte unique sur user_id).
create table public.couple_members (
  couple_id   uuid not null references public.couples (id) on delete cascade,
  user_id     uuid not null unique references auth.users (id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (couple_id, user_id)
);

-- Invitations : seul le hachage SHA-256 du jeton est stocké.
create table public.invitations (
  id          uuid primary key default gen_random_uuid(),
  couple_id   uuid not null references public.couples (id) on delete cascade,
  token_hash  bytea not null unique check (octet_length(token_hash) = 32),
  created_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours',
  used_at     timestamptz
);

-- Tentatives pour rejoindre un couple : limitation anti-devinette.
create table public.join_attempts (
  user_id     uuid not null references auth.users (id) on delete cascade,
  at          timestamptz not null default now()
);
create index join_attempts_user_at on public.join_attempts (user_id, at);

-- Clés publiques Signal d'un téléphone (version 1 : un téléphone actif par personne).
create table public.devices (
  user_id             uuid primary key references auth.users (id) on delete cascade,
  registration_id     integer not null check (registration_id between 1 and 16380),
  device_id           integer not null default 1 check (device_id between 1 and 127),
  identity_key        bytea not null check (octet_length(identity_key) = 33),
  signed_prekey_id    integer not null,
  signed_prekey       bytea not null check (octet_length(signed_prekey) = 33),
  signed_prekey_sig   bytea not null check (octet_length(signed_prekey_sig) = 64),
  kyber_prekey_id     integer not null,
  kyber_prekey        bytea not null check (octet_length(kyber_prekey) between 1500 and 1700),
  kyber_prekey_sig    bytea not null check (octet_length(kyber_prekey_sig) = 64),
  updated_at          timestamptz not null default now()
);

-- Pré-clés à usage unique : consommées une par une par le partenaire.
create table public.one_time_prekeys (
  user_id     uuid not null references public.devices (user_id) on delete cascade,
  prekey_id   integer not null,
  public_key  bytea not null check (octet_length(public_key) = 33),
  primary key (user_id, prekey_id)
);

-- Enveloppes chiffrées en transit. Supprimées par le destinataire après réception :
-- l'historique vit sur les téléphones (et dans la sauvegarde chiffrée), pas sur le serveur.
create table public.envelopes (
  id            uuid primary key default gen_random_uuid(),
  couple_id     uuid not null references public.couples (id) on delete cascade,
  sender_id     uuid not null references auth.users (id) on delete cascade,
  recipient_id  uuid not null references auth.users (id) on delete cascade,
  kind          smallint not null check (kind in (2, 3)),   -- 3 = PreKeySignalMessage, 2 = SignalMessage
  ciphertext    bytea not null check (octet_length(ciphertext) between 1 and 262144),
  created_at    timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index envelopes_recipient on public.envelopes (recipient_id, created_at);

-- ============================================================ fonctions utilitaires

-- Couple de l'utilisateur courant (null s'il n'en a pas). SECURITY DEFINER : évite la récursion RLS.
create function public.my_couple_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select couple_id from public.couple_members where user_id = (select auth.uid());
$$;

-- Partenaire de l'utilisateur courant (null s'il est seul).
create function public.my_partner_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.user_id from public.couple_members m
  where m.couple_id = public.my_couple_id() and m.user_id <> (select auth.uid());
$$;

-- Un couple ne dépasse jamais deux membres, même avec des requêtes simultanées.
create function public.enforce_two_members() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.couples where id = new.couple_id for update;
  if (select count(*) from public.couple_members where couple_id = new.couple_id) >= 2 then
    raise exception 'couple complet' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger couple_members_max_two before insert on public.couple_members
  for each row execute function public.enforce_two_members();

-- Profil créé automatiquement à l'inscription.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================ fonctions appelées par l'app

-- Crée l'espace du couple et renvoie un jeton d'invitation (128 bits, base64url). Le jeton n'est jamais stocké en clair.
create function public.create_couple() returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  c uuid;
  token bytea := extensions.gen_random_bytes(16);
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  if exists (select 1 from public.couple_members where user_id = me) then
    raise exception 'déjà dans un couple' using errcode = 'P0001';
  end if;
  insert into public.couples (created_by) values (me) returning id into c;
  insert into public.couple_members (couple_id, user_id) values (c, me);
  insert into public.invitations (couple_id, token_hash, created_by)
    values (c, extensions.digest(token, 'sha256'), me);
  return rtrim(translate(encode(token, 'base64'), '+/', '-_'), '=');
end;
$$;

-- Nouvelle invitation pour un couple encore incomplet (les précédentes sont annulées).
create function public.renew_invitation() returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  c uuid := public.my_couple_id();
  token bytea := extensions.gen_random_bytes(16);
begin
  if c is null then raise exception 'aucun couple' using errcode = 'P0001'; end if;
  if (select count(*) from public.couple_members where couple_id = c) >= 2 then
    raise exception 'couple complet' using errcode = 'P0001';
  end if;
  delete from public.invitations where couple_id = c and used_at is null;
  insert into public.invitations (couple_id, token_hash, created_by)
    values (c, extensions.digest(token, 'sha256'), me);
  return rtrim(translate(encode(token, 'base64'), '+/', '-_'), '=');
end;
$$;

-- Rejoint un couple avec un jeton. Limité à 10 tentatives par heure et par personne.
-- Un jeton invalide renvoie NULL (pas d'exception) : sinon l'annulation de la transaction effacerait la
-- tentative enregistrée et la limitation ne compterait jamais les échecs.
create function public.join_couple(token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  inv public.invitations%rowtype;
  raw bytea;
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  if (select count(*) from public.join_attempts where user_id = me and at > now() - interval '1 hour') >= 10 then
    raise exception 'trop de tentatives, réessaie dans une heure' using errcode = 'P0001';
  end if;
  insert into public.join_attempts (user_id) values (me);
  if exists (select 1 from public.couple_members where user_id = me) then
    raise exception 'déjà dans un couple' using errcode = 'P0001';
  end if;
  begin
    raw := decode(translate(token, '-_', '+/') || repeat('=', (4 - length(token) % 4) % 4), 'base64');
  exception when others then
    return null;
  end;
  select * into inv from public.invitations
    where token_hash = extensions.digest(raw, 'sha256') and used_at is null and expires_at > now()
    for update;
  if not found then return null; end if;
  insert into public.couple_members (couple_id, user_id) values (inv.couple_id, me);
  update public.invitations set used_at = now() where id = inv.id;
  return inv.couple_id;
end;
$$;

-- Clés publiques du partenaire, avec une pré-clé à usage unique consommée de façon atomique.
create function public.claim_partner_bundle()
returns table (
  user_id uuid, registration_id integer, device_id integer, identity_key bytea,
  signed_prekey_id integer, signed_prekey bytea, signed_prekey_sig bytea,
  kyber_prekey_id integer, kyber_prekey bytea, kyber_prekey_sig bytea,
  one_time_prekey_id integer, one_time_prekey bytea
)
language plpgsql security definer set search_path = '' as $$
declare
  p uuid := public.my_partner_id();
  otk record;
begin
  if p is null then raise exception 'aucun partenaire' using errcode = 'P0001'; end if;
  delete from public.one_time_prekeys k
    where (k.user_id, k.prekey_id) = (
      select o.user_id, o.prekey_id from public.one_time_prekeys o
      where o.user_id = p order by o.prekey_id limit 1 for update skip locked)
    returning k.prekey_id, k.public_key into otk;
  return query
    select d.user_id, d.registration_id, d.device_id, d.identity_key,
           d.signed_prekey_id, d.signed_prekey, d.signed_prekey_sig,
           d.kyber_prekey_id, d.kyber_prekey, d.kyber_prekey_sig,
           otk.prekey_id, otk.public_key
    from public.devices d where d.user_id = p;
end;
$$;

-- ============================================================ RLS : tout est fermé par défaut

alter table public.profiles          enable row level security;
alter table public.couples           enable row level security;
alter table public.couple_members    enable row level security;
alter table public.invitations       enable row level security;
alter table public.join_attempts     enable row level security;
alter table public.devices           enable row level security;
alter table public.one_time_prekeys  enable row level security;
alter table public.envelopes         enable row level security;

create policy "profil : le sien" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy "couple : le sien" on public.couples
  for select to authenticated using (id = (select public.my_couple_id()));

create policy "membres : de son couple" on public.couple_members
  for select to authenticated using (couple_id = (select public.my_couple_id()));

-- invitations, join_attempts : aucune politique → inaccessibles directement (fonctions uniquement).

create policy "appareil : lire le sien ou celui du partenaire" on public.devices
  for select to authenticated
  using (user_id = (select auth.uid()) or user_id = (select public.my_partner_id()));
create policy "appareil : publier le sien" on public.devices
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "appareil : mettre à jour le sien" on public.devices
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "appareil : supprimer le sien" on public.devices
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "pré-clés : les siennes" on public.one_time_prekeys
  for select to authenticated using (user_id = (select auth.uid()));
create policy "pré-clés : publier les siennes" on public.one_time_prekeys
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "pré-clés : supprimer les siennes" on public.one_time_prekeys
  for delete to authenticated using (user_id = (select auth.uid()));

-- Envoyer : seulement à son partenaire, dans son couple, en son propre nom.
create policy "enveloppes : envoyer au partenaire" on public.envelopes
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and recipient_id = (select public.my_partner_id())
    and couple_id = (select public.my_couple_id())
  );
-- Recevoir puis supprimer : seulement ce qui nous est destiné.
create policy "enveloppes : lire les siennes" on public.envelopes
  for select to authenticated using (recipient_id = (select auth.uid()));
create policy "enveloppes : supprimer après réception" on public.envelopes
  for delete to authenticated using (recipient_id = (select auth.uid()));

-- ============================================================ droits

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant select on public.profiles, public.couples, public.couple_members to authenticated;
grant select, insert, update, delete on public.devices to authenticated;
grant select, insert, delete on public.one_time_prekeys to authenticated;
grant select, insert, delete on public.envelopes to authenticated;

grant execute on function public.create_couple(), public.renew_invitation(), public.join_couple(text),
  public.claim_partner_bundle(), public.my_couple_id(), public.my_partner_id() to authenticated;

-- Les nouvelles tables ou fonctions ne seront jamais ouvertes par défaut.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;
