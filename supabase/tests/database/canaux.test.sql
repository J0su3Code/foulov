-- Canaux temps réel privés : chacun n'écoute que son canal d'enveloppes et le canal de son couple.
begin;
create extension if not exists pgtap with schema extensions;
select plan(2);
select policies_are('realtime', 'messages',
  array['couple : écouter son canal', 'couple : publier sur son canal', 'enveloppes : écouter son canal'],
  'seules nos trois règles ouvrent les canaux temps réel');
select policy_cmd_is('realtime', 'messages', 'enveloppes : écouter son canal', 'select',
  'le canal des enveloppes ne sert qu''à écouter');
select * from finish();
rollback;
