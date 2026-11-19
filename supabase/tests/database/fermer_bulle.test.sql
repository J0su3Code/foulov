-- « Fermer notre bulle » : seul un membre peut fermer son espace, et tout part en cascade, chez les deux.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'ines@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'malik@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'zoe@test.local');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end; $$;
create function pg_temp.as_admin() returns void language plpgsql as $$ begin execute 'reset role'; end; $$;

-- Inès et Malik forment un couple, avec une enveloppe en attente.
insert into public.couples (id, created_by) values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');
insert into public.couple_members (couple_id, user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');
insert into public.envelopes (id, couple_id, sender_id, recipient_id, kind, ciphertext) values
  (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 2, '\x01');

-- Zoé (sans espace) ne peut rien fermer.
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select throws_ok('select public.leave_couple()', 'P0002', null, 'sans espace : rien à fermer');
select pg_temp.as_admin();
select is((select count(*)::int from public.couple_members), 2, 'le couple d''Inès et Malik est intact');

-- Anonyme : refusé.
set local role anon;
select throws_ok('select public.leave_couple()', '42501', null, 'anonyme : refusé');
select pg_temp.as_admin();

-- Malik ferme la bulle : espace, membres et enveloppes disparaissent, pour les deux.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.leave_couple(), 'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'Malik ferme leur bulle');
select pg_temp.as_admin();
select is((select count(*)::int from public.couples), 0, 'espace supprimé');
select is((select count(*)::int from public.couple_members), 0, 'les deux membres sont libres');
select is((select count(*)::int from public.envelopes), 0, 'enveloppes en attente supprimées');
select is((select count(*)::int from auth.users), 3, 'les comptes, eux, restent');

select * from finish();
rollback;
