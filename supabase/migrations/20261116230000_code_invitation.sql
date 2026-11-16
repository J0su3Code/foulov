-- Code d'invitation lisible à voix haute (docs/SECURITY.md §5) :
-- 10 caractères de l'alphabet Crockford base32 (sans I, L, O, U), soit 50 bits, affiché « K7Q4M-9XHPT ».
-- Valable une fois, 24 h, 10 tentatives par heure et par personne. Seul son hachage SHA-256 est stocké.
-- Le même code est inclus dans le QR code (avec l'empreinte de la clé d'identité et un secret d'appairage).

-- Forme canonique : majuscules, sans séparateurs, confusions corrigées (I, L → 1 ; O → 0).
create function public.normalize_invitation_code(code text) returns text
language sql immutable set search_path = '' as $$
  select translate(upper(regexp_replace(coalesce(code, ''), '[^0-9A-Za-z]', '', 'g')), 'ILO', '110');
$$;

create function public.new_invitation_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  b bytea := extensions.gen_random_bytes(10);
  out text := '';
begin
  -- 256 est un multiple de 32 : chaque caractère est tiré sans biais.
  for i in 0..9 loop
    out := out || substr(alphabet, (get_byte(b, i) & 31) + 1, 1);
  end loop;
  return out;
end;
$$;

create or replace function public.create_couple() returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  c uuid;
  code text := public.new_invitation_code();
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  if exists (select 1 from public.couple_members where user_id = me) then
    raise exception 'déjà dans un couple' using errcode = 'P0001';
  end if;
  insert into public.couples (created_by) values (me) returning id into c;
  insert into public.couple_members (couple_id, user_id) values (c, me);
  insert into public.invitations (couple_id, token_hash, created_by)
    values (c, extensions.digest(code, 'sha256'), me);
  return code;
end;
$$;

create or replace function public.renew_invitation() returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  c uuid := public.my_couple_id();
  code text := public.new_invitation_code();
begin
  if c is null then raise exception 'aucun couple' using errcode = 'P0001'; end if;
  if (select count(*) from public.couple_members where couple_id = c) >= 2 then
    raise exception 'couple complet' using errcode = 'P0001';
  end if;
  delete from public.invitations where couple_id = c and used_at is null;
  insert into public.invitations (couple_id, token_hash, created_by)
    values (c, extensions.digest(code, 'sha256'), me);
  return code;
end;
$$;

-- Un code invalide renvoie NULL (pas d'exception), pour que la tentative reste comptée.
create or replace function public.join_couple(token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  inv public.invitations%rowtype;
  code text := public.normalize_invitation_code(token);
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
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

-- Nettoyage : les tentatives de plus d'un jour ne servent plus à rien.
create function public.purge_join_attempts() returns void
language sql security definer set search_path = '' as $$
  delete from public.join_attempts where at < now() - interval '1 day';
$$;

revoke all on function public.normalize_invitation_code(text), public.new_invitation_code(),
  public.purge_join_attempts() from public, anon, authenticated;
