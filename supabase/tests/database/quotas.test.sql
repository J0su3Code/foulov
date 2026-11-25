-- Limites d'utilisation (migration 20261125120000_quotas.sql) : un compte ne peut ni remplir la base ni faire
-- grimper la facture de stockage R2.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'ines@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'malik@test.local');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end; $$;
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; end; $$;
-- Malik dépose une enveloppe (non urgente : pas de notification) de `kb` Ko pour Inès.
create function pg_temp.send(kb integer) returns void language sql as $$
  insert into public.envelopes (couple_id, sender_id, recipient_id, kind, ciphertext, urgent)
  values ((select public.my_couple_id()), '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
          2, extensions.gen_random_bytes(1024) || decode(repeat('00', kb * 1024 - 1024), 'hex'), false);
$$;
grant execute on function pg_temp.send(integer) to authenticated;

-- ------------------------------------------------------------ couple
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_code as select public.create_couple() as code;
grant select on t_code to authenticated;
select pg_temp.as_admin();
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select isnt(public.join_couple((select code from t_code)), null, 'Malik rejoint Inès');

-- ------------------------------------------------------------ enveloppes en attente : 50 Mo au plus
select lives_ok($$ select pg_temp.send(256) from generate_series(1, 200) $$, '200 enveloppes de 256 Ko (50 Mo) passent');
select throws_ok($$ select pg_temp.send(256) $$, 'P0001', 'trop d''enveloppes en attente',
  'au-delà de 50 Mo en attente chez Inès, le dépôt est refusé');
select throws_ok($$ select * from public.envelope_usage $$, '42501', null, 'les compteurs ne sont pas lisibles');

-- Inès récupère tout : la place se libère.
select pg_temp.as_admin();
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
delete from public.envelopes;
select pg_temp.as_admin();
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select pg_temp.send(1) $$, 'une fois reçues, Malik peut de nouveau écrire');

-- ------------------------------------------------------------ par expéditeur : 200 Mo par jour
select pg_temp.as_admin();
update public.envelope_usage set bytes = 200 * 1024 * 1024 - 2048 where user_id = '22222222-2222-2222-2222-222222222222';
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select pg_temp.send(1) $$, 'sous la limite quotidienne : accepté');
select throws_ok($$ select pg_temp.send(2) $$, 'P0001', 'limite quotidienne d''envoi atteinte',
  'au-delà de 200 Mo envoyés dans la journée : refusé');

-- ------------------------------------------------------------ fichiers R2
select lives_ok($$ select public.take_media_quota(512 * 1024 * 1024) from generate_series(1, 6) $$, '3 Go dans la journée passent');
select throws_ok($$ select public.take_media_quota(1) $$, 'P0001', 'limite d''envoi de fichiers atteinte',
  'au-delà de 3 Go par jour : refusé');
select throws_ok($$ select * from public.media_usage $$, '42501', null, 'le compteur n''est pas lisible par le client');
select throws_ok($$ select public.take_media_quota(0) $$, '22023', 'taille invalide', 'une taille nulle est refusée');

select pg_temp.as_admin();
-- Inès a déjà envoyé 15 Go ces derniers jours.
insert into public.media_usage (user_id, day, uploads, bytes)
  select '11111111-1111-1111-1111-111111111111', (now() at time zone 'utc')::date - d, 10, 3::bigint * 1024 * 1024 * 1024
  from generate_series(1, 5) d;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select public.take_media_quota(1) $$, 'P0001', 'limite d''envoi de fichiers atteinte',
  'au-delà de 15 Go sur 30 jours : refusé');
select pg_temp.as_admin();
update public.media_usage set uploads = 300, bytes = 0 where user_id = '22222222-2222-2222-2222-222222222222';
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select public.take_media_quota(10) $$, 'P0001', 'limite d''envoi de fichiers atteinte',
  'au-delà de 300 envois par jour : refusé');

select pg_temp.as_admin();
set local role anon;
select throws_ok($$ select public.take_media_quota(10) $$, '42501', null, 'sans compte, aucun quota à réserver');

select * from finish();
rollback;
