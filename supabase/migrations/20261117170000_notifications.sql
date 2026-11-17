-- Notifications (docs/SECURITY.md §9) : texte fixe, aucun contenu, aucun nom.
--
-- Comme l'indicateur « urgent » de Signal, l'expéditeur indique seulement si une enveloppe mérite de réveiller le
-- téléphone du partenaire : oui pour un message ou une réaction, non pour un accusé de réception. C'est la seule
-- information ajoutée, et le contenu reste chiffré.

alter table public.envelopes add column urgent boolean not null default true;
-- Une enveloppe ne déclenche qu'une notification, même si la fonction est appelée plusieurs fois.
alter table public.envelopes add column pushed_at timestamptz;

-- Cibles de notification : identifiant d'installation Firebase (FID), une par installation de l'app.
create table public.push_tokens (
  token       text primary key check (length(token) between 16 and 4096),
  user_id     uuid not null references auth.users (id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios')),
  updated_at  timestamptz not null default now()
);
create index push_tokens_user on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
-- Aucune politique : les jetons ne sont lisibles par personne côté client, seulement gérés par les fonctions
-- ci-dessous (et lus par la fonction serveur d'envoi).

-- Enregistre le jeton de ce téléphone pour l'utilisateur connecté. Si le même téléphone change de compte,
-- le jeton passe au nouveau compte : l'ancien ne reçoit plus rien sur ce téléphone.
create function public.register_push_token(token text, platform text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then raise exception 'non authentifié' using errcode = '28000'; end if;
  insert into public.push_tokens (token, user_id, platform) values (token, me, platform)
    on conflict on constraint push_tokens_pkey
    do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
  -- Au plus 5 téléphones par compte : les jetons les plus anciens sont oubliés.
  delete from public.push_tokens p where p.user_id = me and p.token in (
    select t.token from public.push_tokens t where t.user_id = me order by t.updated_at desc offset 5);
end;
$$;

create function public.unregister_push_token(token text) returns void
language sql security definer set search_path = '' as $$
  delete from public.push_tokens p where p.token = unregister_push_token.token and p.user_id = (select auth.uid());
$$;

grant execute on function public.register_push_token(text, text), public.unregister_push_token(text) to authenticated;

-- À chaque enveloppe urgente, la fonction serveur « push » est appelée avec son seul identifiant (aléatoire, connu
-- uniquement de l'expéditeur et du destinataire). Elle vérifie elle-même l'enveloppe : aucun secret n'est stocké ici.
create extension if not exists pg_net with schema extensions;

create function public.notify_envelope() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.urgent then
    perform net.http_post(
      url := 'https://uaxouzccldvjhktcavlk.supabase.co/functions/v1/push',
      body := jsonb_build_object('envelope_id', new.id),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 5000
    );
  end if;
  return new;
end;
$$;
revoke all on function public.notify_envelope() from public, anon, authenticated;
create trigger envelopes_notify after insert on public.envelopes
  for each row execute function public.notify_envelope();
