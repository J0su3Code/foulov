-- Tests des règles d'accès (docs/SECURITY.md §8) : Inès et Malik forment un couple, Zoé est une intruse.
begin;
create extension if not exists pgtap with schema extensions;
select plan(38);

-- ------------------------------------------------------------ préparation
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
create function pg_temp.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; end; $$;
create function pg_temp.fake_device(uid uuid) returns void language sql as $$
  insert into public.devices (user_id, registration_id, identity_key, signed_prekey_id, signed_prekey,
    signed_prekey_sig, kyber_prekey_id, kyber_prekey, kyber_prekey_sig)
  values (uid, 42, decode(repeat('05', 33), 'hex'), 1, decode(repeat('05', 33), 'hex'), decode(repeat('ab', 64), 'hex'),
    1, decode(repeat('08', 1569), 'hex'), decode(repeat('cd', 64), 'hex'));
$$;

create function pg_temp.create_couple_code_sample() returns text language sql security definer as $$ select public.new_invitation_code() $$;

-- ------------------------------------------------------------ profils créés automatiquement
select is((select count(*)::int from public.profiles), 3, 'un profil est créé pour chaque inscription');

-- ------------------------------------------------------------ Inès crée le couple
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_token as select public.create_couple() as token;
select matches((select token from t_token), '^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{10}$', 'le code fait 10 caractères Crockford (50 bits)');
select isnt(pg_temp.create_couple_code_sample(), (select token from t_token), 'deux codes générés sont différents');
select throws_ok($$ select public.create_couple() $$, 'P0001', 'déjà dans un couple', 'impossible de créer un deuxième couple');
select is((select count(*)::int from public.couples), 1, 'Inès voit son couple');
select throws_ok($$ select * from public.invitations $$, '42501', null, 'les invitations ne sont pas lisibles directement');
select pg_temp.fake_device('11111111-1111-1111-1111-111111111111');
insert into public.one_time_prekeys values ('11111111-1111-1111-1111-111111111111', 7, decode(repeat('05', 33), 'hex'));
select throws_ok(
  $$ insert into public.devices (user_id, registration_id, identity_key, signed_prekey_id, signed_prekey, signed_prekey_sig, kyber_prekey_id, kyber_prekey, kyber_prekey_sig)
     values ('22222222-2222-2222-2222-222222222222', 1, decode(repeat('05', 33), 'hex'), 1, decode(repeat('05', 33), 'hex'), decode(repeat('ab', 64), 'hex'), 1, decode(repeat('08', 1569), 'hex'), decode(repeat('cd', 64), 'hex')) $$,
  '42501', null, 'impossible de publier des clés au nom de quelqu''un d''autre');

-- ------------------------------------------------------------ Zoé, seule et intruse
select pg_temp.as_admin();
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.couples), 0, 'Zoé ne voit aucun couple');
select is((select count(*)::int from public.couple_members), 0, 'Zoé ne voit aucun membre');
select is((select count(*)::int from public.devices), 0, 'Zoé ne voit aucune clé publique');
select is((select count(*)::int from public.one_time_prekeys), 0, 'Zoé ne voit aucune pré-clé');
select results_eq($$ select id from public.profiles $$, $$ values ('33333333-3333-3333-3333-333333333333'::uuid) $$, 'Zoé ne voit que son propre profil');
select is(public.join_couple('0000000000'), null, 'un code deviné est refusé');
select throws_ok($$ select * from public.claim_partner_bundle() $$, 'P0001', 'aucun partenaire', 'sans couple, pas de clés de partenaire');
select throws_ok($$ select * from public.join_attempts $$, '42501', null, 'les tentatives ne sont pas lisibles');
select throws_ok($$ select public.handle_new_user() $$, '42501', null, 'les fonctions internes ne sont pas appelables');

-- ------------------------------------------------------------ Malik rejoint
select pg_temp.as_admin();
grant select on t_token to authenticated;
create temp table t_couple as select id from public.couples;
grant select on t_couple to authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select isnt((select public.join_couple(lower(substr((select token from t_token), 1, 5)) || '-' || lower(substr((select token from t_token), 6)))), null,
  'Malik rejoint en tapant le code en minuscules avec un tiret');
select is((select count(*)::int from public.couple_members), 2, 'Malik voit les deux membres');
select is(public.my_partner_id(), '11111111-1111-1111-1111-111111111111'::uuid, 'le partenaire de Malik est Inès');
select pg_temp.fake_device('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.devices), 2, 'Malik voit ses clés et celles d''Inès');
select is((select one_time_prekey_id from public.claim_partner_bundle()), 7, 'Malik obtient une pré-clé à usage unique d''Inès');
select is((select one_time_prekey_id from public.claim_partner_bundle()), null, 'la pré-clé ne peut servir qu''une fois');
insert into public.envelopes (couple_id, sender_id, recipient_id, kind, ciphertext)
  values (public.my_couple_id(), '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 3, '\x0102');
select pass('Malik envoie une enveloppe chiffrée à Inès');
select throws_ok(
  $$ insert into public.envelopes (couple_id, sender_id, recipient_id, kind, ciphertext)
     values (public.my_couple_id(), '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 2, '\x01') $$,
  '42501', null, 'Malik ne peut pas envoyer au nom d''Inès');
select is((select count(*)::int from public.envelopes), 0, 'Malik ne relit pas ce qu''il a envoyé');

-- ------------------------------------------------------------ Zoé essaie le jeton déjà utilisé et d'écrire
select pg_temp.as_admin();
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is(public.join_couple((select token from t_token)), null, 'un jeton ne sert qu''une fois');
select throws_ok(
  $$ insert into public.envelopes (couple_id, sender_id, recipient_id, kind, ciphertext)
     values ((select id from t_couple), '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 2, '\x01') $$,
  '42501', null, 'Zoé ne peut pas écrire dans le couple, même en connaissant son identifiant');
select is((select count(*)::int from public.envelopes), 0, 'Zoé ne lit aucune enveloppe');

-- Troisième membre : refusé par la base elle-même, même en contournant les fonctions.
select pg_temp.as_admin();
select throws_ok(
  $$ insert into public.couple_members (couple_id, user_id) select id, '33333333-3333-3333-3333-333333333333' from public.couples limit 1 $$,
  'P0001', 'couple complet', 'un couple ne dépasse jamais deux membres');

-- Limitation des tentatives : 10 par heure.
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
-- Zoé a déjà fait 2 tentatives ; 8 de plus atteignent la limite de 10.
do $$ begin
  for i in 1..8 loop perform public.join_couple('0000000000'); end loop;
end $$;
select throws_ok($$ select public.join_couple('0000000000') $$, 'P0001', 'trop de tentatives, réessaie dans une heure', 'au-delà de 10 tentatives par heure, refus');
select throws_ok($$ select public.new_invitation_code() $$, '42501', null, 'la génération de codes n''est pas appelable directement');

-- ------------------------------------------------------------ Inès reçoit puis supprime
select pg_temp.as_admin();
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.envelopes), 1, 'Inès reçoit l''enveloppe de Malik');
delete from public.envelopes;
select pg_temp.as_admin();
select is((select count(*)::int from public.envelopes), 0, 'après réception, l''enveloppe disparaît du serveur');

-- ------------------------------------------------------------ anonyme : rien
select pg_temp.as_admin();
set local role anon;
select throws_ok($$ select * from public.couples $$, '42501', null, 'un visiteur non connecté ne lit rien');
select throws_ok($$ select public.create_couple() $$, '42501', null, 'un visiteur non connecté ne peut rien créer');

-- ------------------------------------------------------------ normalisation
reset role;
select is(public.normalize_invitation_code(' k7q4m-9xhpt '), 'K7Q4M9XHPT', 'espaces, tiret et minuscules tolérés');
select is(public.normalize_invitation_code('ILO'), '110', 'I, L et O sont lus comme 1, 1 et 0');

-- ------------------------------------------------------------ toutes les tables ont RLS
reset role;
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity), 0,
  'RLS est activé sur toutes les tables publiques');

select * from finish();
rollback;
